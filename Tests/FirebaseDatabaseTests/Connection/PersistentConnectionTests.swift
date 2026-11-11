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
import Testing

/// The connection's lifecycle against a scripted server, on a manual clock.
@DatabaseActor
@Suite(.timeLimit(.minutes(1)))
struct PersistentConnectionTests {
    let server = ScriptedServer()
    let clock = ManualClock()
    let connectivity = TestConnectivity()
    let delegate = RecordingConnectionDelegate()
    let host = "test-\(UUID().uuidString.prefix(8).lowercased()).example.com"
    let connection: FPersistentConnection

    init() {
        var config = FTestHelpers.defaultConfig()
        config.transport = server
        config.clock = DatabaseClock(clock)
        config.connectivity = connectivity
        connection = FPersistentConnection(repoInfo: FRepoInfo(host: host, isSecure: false, withNamespace: "test"),
                                           config: config)
        connection.delegate = delegate
    }

    /// Opens the connection and completes the handshake on connection `number`.
    @discardableResult
    private func connect(_ number: Int = 1) async throws -> ScriptedConnection {
        connection.open()
        let wire = try await server.connection(number)
        wire.hello()
        try await eventually("connected") { delegate.connects == number }
        return wire
    }

    private func shutDown() {
        connection.shutdown()
        UserDefaults.standard.removeObject(forKey: "firebase:host:\(host)")
    }

    @Test func connectsWhenOpened() async throws {
        let wire = try await connect()
        #expect(wire.request.url.absoluteString.hasPrefix("ws://\(host)/.ws?v=5&ns=test"))
        #expect(wire.request.headers["X-Firebase-GMPID"] == "fake-app-id")
        // The first connection reports its SDK version.
        _ = try await wire.nextRequest("s")
        shutDown()
        try await wire.waitUntilClosed()
    }

    @Test func listensAreSentWhenConnected() async throws {
        connection.listen(.defaultQueryAtPath(FPath(with: "a")), tagId: nil, hash: EmptyHash()) { _ in }
        let wire = try await connect()
        let listen = try await wire.nextRequest("q")
        #expect(listen.body["p"] as? String == "/a")
        shutDown()
    }

    @Test func putsAreResentAfterADrop() async throws {
        let first = try await connect()
        let status = Mutex<String?>(nil)
        connection.putData(1, forPath: "/a", withHash: nil) { result, _ in
            status.withLock { $0 = result }
        }
        _ = try await first.nextRequest("p")
        first.fail()
        try await eventually("disconnected") { delegate.disconnects == 1 }

        // The backoff after a short connection: up to a second.
        try await eventually("backoff") { clock.pendingSleeps.contains { $0 <= .seconds(1) && $0 > .zero } }
        clock.advance(by: .seconds(1))
        let second = try await server.connection(2)
        second.hello(sessionID: "second")
        let put = try await second.nextRequest("p")
        #expect(put.body["p"] as? String == "/a")
        // The new connection resumes the session.
        #expect(second.request.url.query?.contains("ls=session") == true)
        second.respond(to: put.number)
        try await eventually("put acknowledged") { status.withLock { $0 } == "ok" }
        shutDown()
    }

    @Test func onDisconnectActionsCompleteAndSurviveADrop() async throws {
        let first = try await connect()
        let status = Mutex<String?>(nil)
        connection.onDisconnectPutData(1, forPath: FPath(with: "a")) { result, _ in
            status.withLock { $0 = result }
        }
        _ = try await first.nextRequest("o")
        first.fail()
        try await eventually("backoff") { clock.pendingSleeps.contains { $0 > .zero && $0 <= .seconds(1) } }
        clock.advance(by: .seconds(1))
        let second = try await server.connection(2)
        second.hello()
        let resent = try await second.nextRequest("o")
        // Success responses have no reason; they still complete.
        second.respond(to: resent.number)
        try await eventually("onDisconnect acknowledged") { status.withLock { $0 } == "ok" }
        shutDown()
    }

    @Test func aSentGetFailsWhenTheConnectionDrops() async throws {
        let wire = try await connect()
        async let result = connection.getDataAtPath("/a", withParams: [:])
        _ = try await wire.nextRequest("g")
        wire.fail()
        #expect(await result.status == "failed")
        shutDown()
    }

    @Test func aGetWaitsForTheConnectionThenTimesOut() async throws {
        async let result = connection.getDataAtPath("/a", withParams: [:])
        try await eventually("get timer") { clock.pendingSleeps.contains(.seconds(3)) }
        clock.advance(by: .seconds(3))
        #expect(await result.status == "failed")
        shutDown()
    }

    @Test func cancellingAGetRemovesIt() async throws {
        let task = Task { await connection.getDataAtPath("/a", withParams: [:]) }
        task.cancel()
        #expect(await task.value.errorReason == "cancelled")
        shutDown()
    }

    @Test func aServerResetReconnectsAtOnceToTheNewHost() async throws {
        let first = try await connect()
        first.control("r", "moved.\(host)")
        let second = try await server.connection(2)
        #expect(second.request.url.host == "moved.\(host)")
        shutDown()
    }

    @Test func aServerShutdownStopsReconnecting() async throws {
        let first = try await connect()
        first.control("s", "bye")
        try await first.waitUntilClosed()
        try await eventually("disconnected") { delegate.disconnects == 1 }
        clock.advance(by: .seconds(60))
        try await Task.sleep(for: .milliseconds(50))
        #expect(server.connections.count == 1)
        #expect(connection.isInterruptedForReason(kFInterruptReasonServerKill))
        shutDown()
    }

    @Test func aMissingHandshakeTimesOut() async throws {
        connection.open()
        let first = try await server.connection(1)
        try await eventually("handshake timer") { clock.pendingSleeps.contains(.seconds(30)) }
        clock.advance(by: .seconds(30))
        try await first.waitUntilClosed()
        try await eventually("disconnected") { delegate.disconnects == 1 }
        shutDown()
    }

    @Test func failedAttemptsBackOff() async throws {
        server.failNextConnection()
        server.failNextConnection()
        connection.open()
        try await eventually("first backoff") { clock.pendingSleeps.contains { $0 > .zero && $0 <= .seconds(1) } }
        clock.advance(by: .seconds(1))
        try await eventually("second backoff") { clock.pendingSleeps.contains { $0 > .zero && $0 <= .seconds(1.3) } }
        clock.advance(by: .seconds(1.3))
        _ = try await server.connection(1)
        shutDown()
    }

    @Test func sendsKeepAlivesWhenIdle() async throws {
        let wire = try await connect()
        try await eventually("keep-alive timer") { clock.pendingSleeps.contains { $0 > .seconds(40) && $0 <= .seconds(45) } }
        clock.advance(by: .seconds(45))
        try await eventually("keep-alive") { wire.sent.contains("0") }
        shutDown()
    }

    @Test func interruptingClosesAndResumingReconnects() async throws {
        let first = try await connect()
        connection.interruptForReason(kFInterruptReasonRepoInterrupt)
        try await first.waitUntilClosed()
        try await Task.sleep(for: .milliseconds(20))
        #expect(server.connections.count == 1)
        connection.resumeForReason(kFInterruptReasonRepoInterrupt)
        _ = try await server.connection(2)
        shutDown()
    }

    @Test func aNetworkChangeChecksTheConnection() async throws {
        let first = try await connect()
        connectivity.change()
        let probe = try await first.nextRequest("s")
        // The first stats request is the SDK's; the check follows.
        let check = probe.body["c"] as? [String: Any] == [:] ? probe : try await first.nextRequest("s")
        first.respond(to: check.number)
        // Messages are handled in order: once this one is, so is the answer.
        first.push(json: ["t": "d", "d": ["a": "d", "b": ["p": "after", "d": 1]]])
        try await eventually("answer handled") { delegate.updates.count == 1 }
        try await eventually("probe timer") { clock.pendingSleeps.contains(.seconds(10)) }
        clock.advance(by: .seconds(10))
        try await Task.sleep(for: .milliseconds(20))
        #expect(!first.isClosed)

        // Unanswered, the connection is replaced at once.
        connectivity.change()
        _ = try await first.nextRequest("s")
        try await eventually("probe timer") { clock.pendingSleeps.contains(.seconds(10)) }
        clock.advance(by: .seconds(10))
        try await first.waitUntilClosed()
        _ = try await server.connection(2)
        shutDown()
    }

    @Test func aNetworkChangeCutsTheBackoffShort() async throws {
        server.failNextConnection()
        connection.open()
        try await eventually("backoff") { clock.pendingSleeps.contains { $0 > .zero && $0 <= .seconds(1) } }
        connectivity.change()
        _ = try await server.connection(1)
        shutDown()
    }

    @Test func shutdownClosesTheConnection() async throws {
        let wire = try await connect()
        connection.shutdown()
        try await wire.waitUntilClosed()
        // The transport closes just before the actor reports the disconnect.
        try await eventually("disconnected") { delegate.disconnects == 1 }
        UserDefaults.standard.removeObject(forKey: "firebase:host:\(host)")
    }
}

private struct EmptyHash: FSyncTreeHash {
    var simpleHash: String { "" }
    var compoundHash: FCompoundHashWrapper { fatalError("not used") }
    var includeCompoundHash: Bool { false }
}

/// The backoff's delays, without jitter.
struct BackoffTests {
    /// The delay in milliseconds (the arithmetic is in floating point).
    private func milliseconds(_ backoff: inout Backoff) -> Int {
        Int((backoff.nextDelay() / .milliseconds(1)).rounded())
    }

    @Test func growsFromTheMinimumToTheMaximum() {
        var backoff = Backoff()
        backoff.random = { 1 }
        #expect(milliseconds(&backoff) == 0)
        #expect(milliseconds(&backoff) == 1000)
        #expect(milliseconds(&backoff) == 1300)
        for _ in 0 ..< 20 {
            _ = backoff.nextDelay()
        }
        #expect(milliseconds(&backoff) == 30000)
        backoff.reset()
        #expect(milliseconds(&backoff) == 0)
        #expect(milliseconds(&backoff) == 1000)
    }

    @Test func jitterShortensTheDelay() {
        var backoff = Backoff()
        backoff.random = { 0 }
        _ = backoff.nextDelay()
        #expect(milliseconds(&backoff) == 300)
    }
}

extension Dictionary where Key == String, Value == Any {
    fileprivate static func == (lhs: Self?, rhs: Self) -> Bool {
        lhs.map { NSDictionary(dictionary: $0).isEqual(to: rhs) } ?? false
    }
}
