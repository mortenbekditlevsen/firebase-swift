// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket

/// WebSocket connections over SwiftNIO, with TLS from swift-nio-ssl.
///
/// Connections share an event loop group (by default NIO's singleton), so
/// connecting doesn't create threads.
public struct NIODatabaseTransport: DatabaseTransport {
    private let group: any EventLoopGroup
    private let sslContext: Result<NIOSSLContext, any Error>
    private let connectTimeout: TimeAmount

    /// - Parameters:
    ///   - eventLoopGroup: The group connections run on.
    ///   - tlsConfiguration: The TLS configuration for `wss` connections.
    ///   - connectTimeout: How long connecting (TCP) may take.
    public init(
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        tlsConfiguration: TLSConfiguration = .makeClientConfiguration(),
        connectTimeout: TimeAmount = .seconds(30)
    ) {
        group = eventLoopGroup
        sslContext = Result { try NIOSSLContext(configuration: tlsConfiguration) }
        self.connectTimeout = connectTimeout
    }

    private enum Upgrade: Sendable {
        case upgraded(NIOAsyncChannel<ByteBuffer, ByteBuffer>)
        case notUpgraded
    }

    public func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (Connection) async throws -> sending Result
    ) async throws -> sending Result {
        let url = request.url
        guard let host = url.host, let scheme = url.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
            throw DatabaseTransportError.invalidURL(url)
        }
        let secure = scheme == "wss"
        let port = url.port ?? (secure ? 443 : 80)
        let sslContext = secure ? try self.sslContext.get() : nil

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: url.port.map { "\(host):\($0)" } ?? host)
        for (name, value) in request.headers {
            headers.add(name: name, value: value)
        }
        var uri = url.path.isEmpty ? "/" : url.path
        if let query = url.query {
            uri += "?\(query)"
        }
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)

        let upgrade: EventLoopFuture<Upgrade> = try await ClientBootstrap(group: group)
            .connectTimeout(connectTimeout)
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        )
                    }
                    let upgrader = NIOTypedWebSocketClientUpgrader<Upgrade>(
                        maxFrameSize: maxDatabaseMessageSize,
                        upgradePipelineHandler: { channel, _ in
                            channel.eventLoop.makeCompletedFuture {
                                // Fragmented messages arrive whole.
                                try channel.pipeline.syncOperations.addHandler(
                                    NIOWebSocketFrameAggregator(
                                        minNonFinalFragmentSize: 0,
                                        maxAccumulatedFrameCount: .max,
                                        maxAccumulatedFrameSize: maxDatabaseMessageSize
                                    )
                                )
                                try channel.pipeline.syncOperations.addHandler(WebSocketMessageHandler())
                                return .upgraded(try NIOAsyncChannel(wrappingChannelSynchronously: channel))
                            }
                        }
                    )
                    let configuration = NIOTypedHTTPClientUpgradeConfiguration<Upgrade>(
                        upgradeRequestHead: head,
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.close(promise: nil)
                            return channel.eventLoop.makeSucceededFuture(.notUpgraded)
                        }
                    )
                    var pipeline = NIOUpgradableHTTPClientPipelineConfiguration(upgradeConfiguration: configuration)
                    // The server's first message can arrive in the same read as
                    // its upgrade response; the default drops it.
                    pipeline.leftOverBytesStrategy = .forwardBytes
                    return try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                        configuration: pipeline
                    )
                }
            }

        switch try await upgrade.get() {
        case .notUpgraded:
            throw DatabaseTransportError.upgradeRejected
        case .upgraded(let channel):
            return try await channel.executeThenClose { inbound, outbound in
                try await body(Connection(messages: inbound, outbound: outbound))
            }
        }
    }

    public struct Connection: DatabaseTransportConnection {
        let messages: NIOAsyncChannelInboundStream<ByteBuffer>
        let outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>

        public var inbound: some AsyncSequence<DatabaseFrame, any Error> {
            messages.map { DatabaseFrame($0) }
        }

        public func send(_ frame: DatabaseFrame) async throws {
            try await outbound.write(frame.byteBuffer)
        }
    }
}

/// Between WebSocket frames and the text messages they carry: answers pings
/// and the server's close, and masks outgoing frames (as clients must).
private final class WebSocketMessageHandler: ChannelDuplexHandler {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = WebSocketFrame

    private var sentClose = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text, .binary:
            context.fireChannelRead(wrapInboundOut(frame.unmaskedData))
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            // Echo the close (with its code), then close the connection, which
            // finishes the inbound sequence.
            guard !sentClose else {
                context.close(promise: nil)
                return
            }
            sentClose = true
            var data = frame.unmaskedData
            let code = data.readWebSocketErrorCode() ?? .normalClosure
            var payload = context.channel.allocator.buffer(capacity: 2)
            payload.write(webSocketErrorCode: code)
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: .random(), data: payload)
            context.writeAndFlush(wrapOutboundOut(close)).assumeIsolated().whenComplete { _ in
                context.close(promise: nil)
            }
        case .pong, .continuation:
            break
        default:
            context.close(promise: nil)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: unwrapOutboundIn(data))
        context.write(wrapOutboundOut(frame), promise: promise)
    }
}
