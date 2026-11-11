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

    public func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (Connection) async throws -> sending Result
    ) async throws -> sending Result {
        let target = try WebSocketTarget(request)
        let sslContext = target.secure ? try self.sslContext.get() : nil
        let pending = try await ClientBootstrap(group: group)
            .connectTimeout(connectTimeout)
            .connect(host: target.host, port: target.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSLClientHandler(context: sslContext, serverHostname: target.host)
                        )
                    }
                    return try configureWebSocketClient(channel, head: target.head)
                }
            }
        return try await withWebSocket(pending, body)
    }

    public struct Connection: DatabaseTransportConnection {
        let messages: NIOAsyncChannelInboundStream<ByteBuffer>
        let outbound: NIOAsyncChannelOutboundWriter<ByteBuffer>
        let channel: any Channel

        public var inbound: some AsyncSequence<DatabaseFrame, any Error> {
            messages.map { DatabaseFrame($0) }
        }

        public func send(_ frame: DatabaseFrame) async throws {
            try await outbound.write(frame.byteBuffer)
        }
    }
}

extension NIODatabaseTransport.Connection: DatabaseTransportImmediateSending {
    /// Writes to the channel, which takes writes from any thread in order.
    func sendImmediately(_ frame: DatabaseFrame) {
        channel.writeAndFlush(frame.byteBuffer, promise: nil)
    }
}

/// Where a WebSocket request goes, and its upgrade request.
struct WebSocketTarget: Sendable {
    let host: String
    let port: Int
    let secure: Bool
    let head: HTTPRequestHead

    init(_ request: DatabaseTransportRequest) throws {
        let url = request.url
        guard let host = url.host, let scheme = url.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
            throw DatabaseTransportError.invalidURL(url)
        }
        self.host = host
        secure = scheme == "wss"
        port = url.port ?? (secure ? 443 : 80)

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: url.port.map { "\(host):\($0)" } ?? host)
        for (name, value) in request.headers {
            headers.add(name: name, value: value)
        }
        var uri = url.path.isEmpty ? "/" : url.path
        if let query = url.query {
            uri += "?\(query)"
        }
        head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)
    }
}

/// A connected channel whose WebSocket upgrade is under way.
struct PendingWebSocket: Sendable {
    let channel: any Channel
    let upgrade: EventLoopFuture<WebSocketUpgrade>
}

/// The result of a WebSocket upgrade.
enum WebSocketUpgrade: Sendable {
    case upgraded(NIOAsyncChannel<ByteBuffer, ByteBuffer>)
    case notUpgraded
}

/// Adds the HTTP client, the upgrade to a WebSocket and the WebSocket
/// handlers to a connected channel (after any TLS handler).
func configureWebSocketClient(_ channel: any Channel, head: HTTPRequestHead) throws
    -> PendingWebSocket {
    let upgrader = NIOTypedWebSocketClientUpgrader<WebSocketUpgrade>(
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
    let configuration = NIOTypedHTTPClientUpgradeConfiguration<WebSocketUpgrade>(
        upgradeRequestHead: head,
        upgraders: [upgrader],
        notUpgradingCompletionHandler: { channel in
            channel.close(promise: nil)
            return channel.eventLoop.makeSucceededFuture(.notUpgraded)
        }
    )
    var pipeline = NIOUpgradableHTTPClientPipelineConfiguration(upgradeConfiguration: configuration)
    // The server's first message can arrive in the same read as its upgrade
    // response; the default drops it.
    pipeline.leftOverBytesStrategy = .forwardBytes
    let upgrade = try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(configuration: pipeline)
    return PendingWebSocket(channel: channel, upgrade: upgrade)
}

/// Waits for the upgrade, runs `body` with the connection, and closes it.
func withWebSocket<Result>(
    _ pending: PendingWebSocket,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (NIODatabaseTransport.Connection) async throws -> sending Result
) async throws -> sending Result {
    // The upgrade doesn't end on cancellation, and nothing times out the TLS
    // handshake or the upgrade response, so a stalled server would keep the
    // client offline until the OS gives up on the socket (upstream #9682).
    // Closing the channel fails the upgrade.
    let upgrade = try await withTaskCancellationHandler {
        try await pending.upgrade.get()
    } onCancel: {
        pending.channel.close(promise: nil)
    }
    switch upgrade {
    case .notUpgraded:
        throw DatabaseTransportError.upgradeRejected
    case .upgraded(let channel):
        return try await channel.executeThenClose { inbound, outbound in
            try await body(NIODatabaseTransport.Connection(messages: inbound, outbound: outbound,
                                                           channel: channel.channel))
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

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // After the close handshake, the connection ended as it should, even
        // if the socket then reports the peer's reset (as Network.framework
        // does).
        guard !sentClose else {
            context.close(promise: nil)
            return
        }
        context.fireErrorCaught(error)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: unwrapOutboundIn(data))
        context.write(wrapOutboundOut(frame), promise: promise)
    }
}
