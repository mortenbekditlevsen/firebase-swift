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
import Synchronization

struct ScriptedServerTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Polls `condition` until it holds, for up to five seconds.
func eventually(_ what: String, isolation: isolated (any Actor)? = #isolation,
                _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while try await !condition() {
        guard ContinuousClock.now < deadline else { throw ScriptedServerTimeout(description: "timed out: \(what)") }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// A transport whose server is the test: it sees each connection, the
/// messages the client sends, and sends the server's messages.
final class ScriptedServer: DatabaseTransport {
    private let state = Mutex<(connections: [ScriptedConnection], failures: [any Error])>(([], []))

    /// The connections made so far.
    var connections: [ScriptedConnection] { state.withLock { $0.connections } }

    /// Makes the next connection attempt fail.
    func failNextConnection(with error: any Error = URLError(.cannotConnectToHost)) {
        state.withLock { $0.failures.append(error) }
    }

    /// The `number`th connection (from 1), once it's made.
    func connection(_ number: Int) async throws -> ScriptedConnection {
        try await eventually("connection \(number)") { connections.count >= number }
        return connections[number - 1]
    }

    func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (ScriptedConnection) async throws -> sending Result
    ) async throws -> sending Result {
        if let failure = state.withLock({ $0.failures.isEmpty ? nil : $0.failures.removeFirst() }) {
            throw failure
        }
        let connection = ScriptedConnection(request: request)
        state.withLock { $0.connections.append(connection) }
        defer { connection.markClosed() }
        return try await body(connection)
    }
}

final class ScriptedConnection: DatabaseTransportConnection {
    let request: DatabaseTransportRequest
    let inbound: AsyncThrowingStream<DatabaseFrame, any Error>
    private let continuation: AsyncThrowingStream<DatabaseFrame, any Error>.Continuation
    private let state = Mutex<(sent: [String], closed: Bool, read: Int)>(([], false, 0))

    init(request: DatabaseTransportRequest) {
        self.request = request
        (inbound, continuation) = AsyncThrowingStream.makeStream()
    }

    func send(_ frame: DatabaseFrame) async throws {
        state.withLock { $0.sent.append(frame.string) }
    }

    fileprivate func markClosed() {
        state.withLock { $0.closed = true }
    }

    // MARK: The server's side

    /// Whether the client closed the connection (or it ended).
    var isClosed: Bool { state.withLock { $0.closed } }

    /// Everything the client sent.
    var sent: [String] { state.withLock { $0.sent } }

    func waitUntilClosed() async throws {
        try await eventually("connection closed") { isClosed }
    }

    /// Sends a frame as the server.
    func push(_ text: String) {
        continuation.yield(DatabaseFrame(text))
    }

    func push(json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        push(String(decoding: data, as: UTF8.self))
    }

    func hello(sessionID: String = "session", host: String? = nil) {
        var handshake: [String: Any] = ["ts": 1_700_000_000_000, "v": "5", "s": sessionID]
        handshake["h"] = host
        push(json: ["t": "c", "d": ["t": "h", "d": handshake]])
    }

    func control(_ type: String, _ data: Any) {
        push(json: ["t": "c", "d": ["t": type, "d": data]])
    }

    /// Answers request `number`.
    func respond(to number: Int, status: String = "ok", data: Any? = nil) {
        var body: [String: Any] = ["s": status]
        body["d"] = data
        push(json: ["t": "d", "d": ["r": number, "b": body]])
    }

    /// Closes the connection as the server would.
    func close() {
        continuation.finish()
    }

    /// Breaks the connection.
    func fail() {
        continuation.finish(throwing: URLError(.networkConnectionLost))
    }

    struct Request {
        let number: Int
        let action: String
        let body: [String: Any]
    }

    /// The next request the client sends with `action`, skipping others.
    func nextRequest(_ action: String) async throws -> Request {
        var found: Request?
        try await eventually("a \(action) request") {
            state.withLock { state in
                while state.read < state.sent.count {
                    let text = state.sent[state.read]
                    state.read += 1
                    guard let request = Self.parse(text), request.action == action else { continue }
                    found = request
                    return true
                }
                return false
            }
        }
        return found!
    }

    private static func parse(_ text: String) -> Request? {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let data = json["d"] as? [String: Any],
              let number = data["r"] as? Int,
              let action = data["a"] as? String
        else { return nil }
        return Request(number: number, action: action, body: data["b"] as? [String: Any] ?? [:])
    }
}

/// Network changes on demand.
final class TestConnectivity: ConnectivityMonitor {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func changes() -> AsyncStream<Void> { stream }

    func change() {
        continuation.yield()
    }
}

/// Records what the connection tells the repo.
@DatabaseActor
final class RecordingConnectionDelegate: FPersistentConnectionDelegate {
    var connects = 0
    var disconnects = 0
    var updates: [(path: String, message: Any)] = []

    nonisolated init() {}

    func onDataUpdate(_ fpconnection: FPersistentConnection, forPath pathString: String, message: Any,
                      isMerge: Bool, tagId: Int?) {
        updates.append((pathString, message))
    }

    func onRangeMerge(_ ranges: [FRangeMerge], forPath pathString: String, tagId: Int?) {}

    func onConnect(_ fpconnection: FPersistentConnection) {
        connects += 1
    }

    func onDisconnect(_ fpconnection: FPersistentConnection) {
        disconnects += 1
    }

    func onServerInfoUpdate(_ fpconnection: FPersistentConnection, updates: [String: Any]) {}
}
