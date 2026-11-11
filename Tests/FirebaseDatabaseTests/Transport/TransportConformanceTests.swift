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

@testable import FirebaseDatabase
import Foundation
import Testing

/// The `DatabaseTransport` contract, checked for each transport against a
/// local WebSocket server.
@Suite(.timeLimit(.minutes(1)))
struct TransportConformanceTests {
    enum Kind: String, CaseIterable, CustomTestStringConvertible {
        case nio
        #if canImport(Darwin)
            case urlSession
            case networkFramework
        #endif

        var testDescription: String { rawValue }

        var transport: any DatabaseTransport {
            switch self {
            case .nio: NIODatabaseTransport()
            #if canImport(Darwin)
                case .urlSession: URLSessionDatabaseTransport()
                case .networkFramework: NIOTSDatabaseTransport()
            #endif
            }
        }
    }

    /// How the inbound messages ended.
    enum End: Equatable {
        case finished
        case failed
    }

    /// Connects with `kind`'s transport and runs `body`.
    private func connect<Result: Sendable>(
        _ kind: Kind, to url: URL, headers: [String: String] = [:],
        _ body: @escaping (any DatabaseTransportConnection) async throws -> Result
    ) async throws -> Result {
        try await connect(kind.transport, to: url, headers: headers, body)
    }

    private func connect<Transport: DatabaseTransport, Result: Sendable>(
        _ transport: Transport, to url: URL, headers: [String: String],
        _ body: @escaping (any DatabaseTransportConnection) async throws -> Result
    ) async throws -> Result {
        try await transport.withConnection(to: DatabaseTransportRequest(url: url, headers: headers),
                                           isolation: #isolation) { connection in
            try await body(connection)
        }
    }

    /// Reads messages until the sequence ends.
    private static func drain(_ connection: any DatabaseTransportConnection) async -> (messages: [String], end: End) {
        var messages: [String] = []
        do {
            for try await frame in connection.inbound {
                messages.append(frame.string)
            }
            return (messages, .finished)
        } catch {
            return (messages, .failed)
        }
    }

    private static func first(_ connection: any DatabaseTransportConnection) async throws -> String? {
        for try await frame in connection.inbound {
            return frame.string
        }
        return nil
    }

    @Test(arguments: Kind.allCases)
    func echoes(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let reply = try await connect(kind, to: server.url("/echo")) { connection in
            try await connection.send(DatabaseFrame("hello ✓"))
            return try await Self.first(connection)
        }
        #expect(reply == "hello ✓")
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func sendsTheHeaders(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let reply = try await connect(kind, to: server.url("/headers"), headers: ["X-Test": "value"]) { connection in
            try await Self.first(connection)
        }
        #expect(reply == "value")
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func aServerCloseFinishesTheMessages(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let end = try await connect(kind, to: server.url("/close")) { connection in
            await Self.drain(connection).end
        }
        #expect(end == .finished)
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func aDroppedConnectionEndsTheMessages(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        // Without a close frame, ending either way is a disconnect.
        let messages = try await connect(kind, to: server.url("/drop")) { connection in
            await Self.drain(connection).messages
        }
        #expect(messages.isEmpty)
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func aRefusedConnectionThrows(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let url = server.url("/echo")
        try await server.close()
        await #expect(throws: (any Error).self) {
            try await connect(kind, to: url) { _ in }
        }
    }

    @Test(arguments: Kind.allCases)
    func aRefusedUpgradeThrows(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        await #expect(throws: (any Error).self) {
            try await connect(kind, to: server.url("/missing")) { _ in }
        }
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func carriesLargeMessages(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let message = String(repeating: "abcdefghæøå", count: 100_000) // ~1.4 MB
        let reply = try await connect(kind, to: server.url("/echo")) { connection in
            try await connection.send(DatabaseFrame(message))
            return try await Self.first(connection)
        }
        #expect(reply == message)
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func joinsFragmentsSplitInsideACharacter(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let reply = try await connect(kind, to: server.url("/fragments")) { connection in
            try await Self.first(connection)
        }
        #expect(reply == "héllo wörld")
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func answersPings(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let reply = try await connect(kind, to: server.url("/ping")) { connection in
            try await Self.first(connection)
        }
        #expect(reply == "pong:probe")
        try await server.close()
    }

    @Test(arguments: Kind.allCases)
    func cancellationEndsTheConnection(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.start()
        let connected = AsyncStream<Void>.makeStream()
        let task = Task {
            try await connect(kind, to: server.url("/echo")) { connection in
                connected.continuation.yield()
                _ = await Self.drain(connection)
            }
        }
        for await _ in connected.stream { break }
        let start = ContinuousClock.now
        task.cancel()
        _ = await task.result
        #expect(ContinuousClock.now - start < .seconds(2))
        try await server.close()
    }

    // Upstream 13.2.0 (#16725) stops waiting for a connection attempt that timed out: it could
    // hang in the TLS handshake for hours (#9682). The session's handshake timeout cancels the
    // transport, so cancelling must end an attempt that the server never answers.
    @Test(arguments: Kind.allCases)
    func cancellationEndsAStalledUpgrade(_ kind: Kind) async throws {
        let server = try await TestWebSocketServer.startSilent()
        let task = Task {
            try await connect(kind, to: server.url("/echo")) { _ in }
        }
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        _ = await task.result
        #expect(ContinuousClock.now - start < .seconds(2))
        try await server.close()
    }
}
