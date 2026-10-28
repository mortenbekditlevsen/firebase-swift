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

import FirebaseShared
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing

@Suite struct AsyncLinesTests {
  private func lines(of chunks: [String]) async throws -> [String] {
    let stream = AsyncThrowingStream<Data, Error> { continuation in
      for chunk in chunks { continuation.yield(Data(chunk.utf8)) }
      continuation.finish()
    }
    var result: [String] = []
    for try await line in stream.asyncLines { result.append(line) }
    return result
  }

  @Test func splitsLinesAcrossChunkBoundaries() async throws {
    #expect(try await lines(of: ["data: {\"a\"", ":1}\ndata: ", "{\"b\":2}\n"])
      == ["data: {\"a\":1}", "data: {\"b\":2}"])
  }

  @Test func skipsEmptyLinesAndStripsCarriageReturns() async throws {
    #expect(try await lines(of: ["one\r\n\r\n", "\ntwo\r\n"]) == ["one", "two"])
  }

  @Test func emitsTrailingLineWithoutNewline() async throws {
    #expect(try await lines(of: ["first\nlast"]) == ["first", "last"])
  }

  @Test func propagatesErrors() async throws {
    struct Failure: Error {}
    let stream = AsyncThrowingStream<Data, Error> { continuation in
      continuation.yield(Data("partial".utf8))
      continuation.finish(throwing: Failure())
    }
    await #expect(throws: Failure.self) {
      for try await _ in stream.asyncLines {}
    }
  }
}

@Suite struct ChunkedBytesTests {
  @Test func streamsChunkedHTTPBody() async throws {
    let parts = (0 ..< 8).map { i in Data(repeating: UInt8(i), count: 32 * 1024) }
    let server = try await StreamingServer.start(parts: parts)
    defer { server.stop() }

    let (chunks, response) = try await URLSession.shared
      .chunkedBytes(for: URLRequest(url: server.url))
    var received = Data()
    for try await chunk in chunks { received.append(chunk) }

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(received == parts.reduce(Data(), +))
  }

  @Test func throwsWhenConnectionIsRefused() async throws {
    // Port 9 (discard) is essentially never listening on CI machines or containers.
    let url = try #require(URL(string: "http://127.0.0.1:9/"))
    await #expect(throws: (any Error).self) {
      let (chunks, _) = try await URLSession.shared.chunkedBytes(for: URLRequest(url: url))
      for try await _ in chunks {}
    }
  }
}

/// A one-route HTTP server that answers every request with `parts`, written
/// as separate chunks of a `Transfer-Encoding: chunked` body.
private struct StreamingServer {
  let url: URL
  private let group: MultiThreadedEventLoopGroup
  private let channel: Channel

  static func start(parts: [Data]) async throws -> StreamingServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let channel = try await ServerBootstrap(group: group)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(Handler(parts: parts))
        }
      }
      .bind(host: "127.0.0.1", port: 0)
      .get()
    let port = try #require(channel.localAddress?.port)
    let url = try #require(URL(string: "http://127.0.0.1:\(port)/stream"))
    return StreamingServer(url: url, group: group, channel: channel)
  }

  func stop() {
    try? channel.close().wait()
    try? group.syncShutdownGracefully()
  }

  private final class Handler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    let parts: [Data]

    init(parts: [Data]) { self.parts = parts }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      guard case .end = unwrapInboundIn(data) else { return }
      let head = HTTPResponseHead(version: .http1_1, status: .ok,
                                  headers: ["Transfer-Encoding": "chunked"])
      context.write(wrapOutboundOut(.head(head)), promise: nil)
      for part in parts {
        let buffer = context.channel.allocator.buffer(bytes: part)
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
      }
      context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
  }
}
