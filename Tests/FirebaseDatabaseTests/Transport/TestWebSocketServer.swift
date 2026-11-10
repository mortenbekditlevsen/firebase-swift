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
import NIOWebSocket

/// A local WebSocket server for the transport tests. The path picks the
/// behavior:
/// - `/echo`: echoes every message.
/// - `/headers`: sends the upgrade request's `X-Test` header, then echoes.
/// - `/close`: closes with a close frame.
/// - `/drop`: drops the TCP connection without a close frame.
/// - `/fragments`: sends one message in three fragments, split inside a
///   multibyte character.
/// - `/ping`: pings, then sends "pong:<data>" when the pong arrives.
/// - `/missing`: refuses the upgrade with 404.
final class TestWebSocketServer: Sendable {
    private let channel: any Channel

    var port: Int { channel.localAddress!.port! }

    func url(_ path: String) -> URL {
        URL(string: "ws://127.0.0.1:\(port)\(path)")!
    }

    private init(channel: any Channel) {
        self.channel = channel
    }

    static func start() async throws -> TestWebSocketServer {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    maxFrameSize: 4 << 20,
                    shouldUpgrade: { channel, head in
                        channel.eventLoop.makeSucceededFuture(head.uri.hasPrefix("/missing") ? nil : HTTPHeaders())
                    },
                    upgradePipelineHandler: { channel, head in
                        channel.pipeline.addHandler(ServerHandler(path: head.uri, headers: head.headers))
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { context in
                        context.pipeline.removeHandler(name: "notFound", promise: nil)
                    })
                ).flatMap {
                    channel.pipeline.addHandler(NotFoundHandler(), name: "notFound")
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        return TestWebSocketServer(channel: channel)
    }

    func close() async throws {
        try await channel.close()
    }
}

/// Answers requests that weren't upgraded with 404.
private final class NotFoundHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .end = unwrapInboundIn(data) else { return }
        let head = HTTPResponseHead(version: .http1_1, status: .notFound, headers: ["Content-Length": "0"])
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).assumeIsolated().whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

private final class ServerHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let path: String
    private let headers: HTTPHeaders
    private var sentClose = false

    init(path: String, headers: HTTPHeaders) {
        self.path = path
        self.headers = headers
    }

    func handlerAdded(context: ChannelHandlerContext) {
        switch path {
        case "/headers":
            send(text: headers.first(name: "X-Test") ?? "", context: context)
        case "/close":
            sentClose = true
            var data = context.channel.allocator.buffer(capacity: 2)
            data.write(webSocketErrorCode: .normalClosure)
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: data)),
                                  promise: nil)
        case "/drop":
            context.close(promise: nil)
        case "/fragments":
            let bytes = Array("héllo wörld".utf8)
            // "é" is two bytes, at 1 and 2: split between them.
            let parts = [bytes[0 ..< 2], bytes[2 ..< 8], bytes[8...]]
            for (index, part) in parts.enumerated() {
                let frame = WebSocketFrame(fin: index == parts.count - 1,
                                           opcode: index == 0 ? .text : .continuation,
                                           data: ByteBuffer(bytes: part))
                context.write(wrapOutboundOut(frame), promise: nil)
            }
            context.flush()
        case "/ping":
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .ping,
                                                                 data: ByteBuffer(string: "probe"))),
                                  promise: nil)
        default:
            break
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text, .binary:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: frame.opcode,
                                                                 data: frame.unmaskedData)),
                                  promise: nil)
        case .pong:
            send(text: "pong:" + String(buffer: frame.unmaskedData), context: context)
        case .connectionClose:
            if sentClose {
                context.close(promise: nil)
            } else {
                sentClose = true
                context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose,
                                                                     data: frame.unmaskedData)))
                    .assumeIsolated().whenComplete { _ in context.close(promise: nil) }
            }
        default:
            break
        }
    }

    private func send(text: String, context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text,
                                                             data: ByteBuffer(string: text))),
                              promise: nil)
    }
}
