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

/// The public API against a scripted server: order, completion, listening.
@Suite(.timeLimit(.minutes(1)))
struct DatabaseAPITests {
    let server = ScriptedServer()
    let database: Database
    let host = "api-\(UUID().uuidString.prefix(8).lowercased()).example.com"

    init() {
        var config = FTestHelpers.configForName("api-\(UUID().uuidString)")
        config.transport = server
        config.connectivity = nil
        (database, _) = Database.createDatabaseForTests(
            FRepoInfo(host: host, isSecure: false, withNamespace: "test"), config: config
        )
    }

    private var root: DatabaseReference { database.reference() }

    /// The connection, after the handshake.
    private func connected() async throws -> ScriptedConnection {
        _ = root // creates the repo, which connects
        let wire = try await server.connection(1)
        wire.hello()
        return wire
    }

    private func pushData(_ wire: ScriptedConnection, path: String, _ data: Any) {
        wire.push(json: ["t": "d", "d": ["a": "d", "b": ["p": path, "d": data]]])
    }

    @Test func referencesByPathAndURL() {
        let byChild = root.child("a").child("b")
        #expect(database.reference(withPath: "a/b").url == byChild.url)
        #expect(database.reference(withPath: "a/b").key == "b")
        #expect(database.reference(fromURL: byChild.url).url == byChild.url)
    }

    @Test func writesReachTheServerInTheOrderTheyreMade() async throws {
        let wire = try await connected()
        let ref = root.child("counter")
        for value in 0 ..< 100 {
            if value.isMultiple(of: 3) {
                ref.updateChildValues(["n": value])
            } else {
                ref.child("n").setValue(value)
            }
        }
        var values: [Int] = []
        while values.count < 100 {
            let request = try await wire.nextRequest(values.count.isMultiple(of: 3) ? "m" : "p")
            let data = request.body["d"]
            values.append(((data as? [String: Any])?["n"] ?? data) as! Int)
        }
        #expect(values == Array(0 ..< 100))
    }

    @Test func waitingWritesCompleteWithTheAcknowledgement() async throws {
        let wire = try await connected()
        let accepted = Task { try await root.child("a").setValueAndWait(1) }
        wire.respond(to: try await wire.nextRequest("p").number)
        try await accepted.value

        let rejected = Task { try await root.child("b").updateChildValuesAndWait(["x": 1]) }
        wire.respond(to: try await wire.nextRequest("m").number, status: "permission_denied")
        await #expect(throws: (any Error).self) { try await rejected.value }
    }

    @Test func iteratingListensAndStoppingUnlistens() async throws {
        let wire = try await connected()
        let ref = root.child("items")
        let reader = Task {
            var seen: [Int] = []
            for try await snapshot in ref.values() {
                seen.append((snapshot.value as? NSNumber)?.intValue ?? -1)
                if seen.count == 2 { break }
            }
            return seen
        }
        let listen = try await wire.nextRequest("q")
        #expect(listen.body["p"] as? String == "/items")
        pushData(wire, path: "items", 1)
        wire.respond(to: listen.number, data: [:])
        // A local write is seen at once.
        ref.setValue(2)
        #expect(try await reader.value == [1, 2])
        let unlisten = try await wire.nextRequest("n")
        #expect(unlisten.body["p"] as? String == "/items")
    }

    @Test func childEventsCarryTheirKindAndSibling() async throws {
        _ = try await connected()
        let ref = root.child("list")
        var events = ref.childEvents([.added, .removed]).makeAsyncIterator()
        ref.updateChildValues(["a": 1, "b": 2])
        let first = try #require(try await events.next())
        let second = try #require(try await events.next())
        #expect(first.kind == .added && first.snapshot.key == "a" && first.previousSiblingKey == nil)
        #expect(second.kind == .added && second.snapshot.key == "b" && second.previousSiblingKey == "a")
        ref.child("a").removeValue()
        let removed = try #require(try await events.next())
        #expect(removed.kind == .removed && removed.snapshot.key == "a")
    }

    @Test func aRevokedListenThrows() async throws {
        let wire = try await connected()
        let reader = Task {
            for try await _ in root.child("secret").values() {}
        }
        let listen = try await wire.nextRequest("q")
        wire.respond(to: listen.number, status: "permission_denied")
        await #expect(throws: (any Error).self) { try await reader.value }
    }

    @Test func firstValueUsesLocalData() async throws {
        _ = try await connected()
        let ref = root.child("local")
        ref.setValue("here")
        let snapshot = try await ref.firstValue()
        #expect(snapshot.value as? String == "here")
    }

    @Test func onDisconnectWritesCompleteInBothForms() async throws {
        let wire = try await connected()
        let ref = root.child("presence")
        ref.onDisconnect.setValue(false)
        let queued = try await wire.nextRequest("o")
        #expect(queued.body["d"] as? Bool == false)

        let waiting = Task { try await ref.onDisconnect.removeValueAndWait() }
        wire.respond(to: try await wire.nextRequest("o").number)
        try await waiting.value

        let cancelling = Task { try await ref.onDisconnect.cancelAndWait() }
        wire.respond(to: try await wire.nextRequest("oc").number)
        try await cancelling.value
    }

    private struct Item: Codable, Equatable, Sendable {
        var name: String
        var count: Int
    }

    @Test func typedSequencesDecode() async throws {
        _ = try await connected()
        let ref = root.child("typed")
        var values = ref.child("one").values(as: Item?.self).makeAsyncIterator()
        var children = ref.child("list").childEvents(as: Item.self, [.added]).makeAsyncIterator()
        try ref.child("one").setValue(from: Item(name: "a", count: 1))
        try ref.child("list/x").setValue(from: Item(name: "x", count: 2))
        #expect(try await values.next() == Item(name: "a", count: 1))
        let added = try #require(try await children.next())
        #expect(added.key == "x" && added.value == Item(name: "x", count: 2) && added.kind == .added)
        ref.child("one").removeValue()
        #expect(try await values.next() == .some(nil))
    }

    @Test func aTypedSequenceThrowsIfTheDataDoesntDecode() async throws {
        _ = try await connected()
        let ref = root.child("bad")
        ref.setValue("not an item")
        await #expect(throws: DecodingError.self) {
            for try await _ in ref.values(as: Item.self) {}
        }
    }

    @Test func typedTransactions() async throws {
        let wire = try await connected()
        let ref = root.child("item")
        let transaction = Task {
            try await ref.runTransaction(as: Item.self) { item in
                item = Item(name: "n", count: (item?.count ?? 0) + 1)
            }
        }
        wire.respond(to: try await wire.nextRequest("q").number, data: [:])
        let put = try await wire.nextRequest("p")
        #expect((put.body["d"] as? [String: Any])?["count"] as? Int == 1)
        wire.respond(to: put.number)
        #expect(try await transaction.value == Item(name: "n", count: 1))

        // Throwing aborts, and the error comes out.
        struct Stop: Error {}
        await #expect(throws: Stop.self) {
            try await ref.runTransaction(as: Item.self) { _ in throw Stop() }
        }
    }

    @Test func transactionsCommitWithTheServersAcknowledgement() async throws {
        let wire = try await connected()
        let ref = root.child("likes")
        let transaction = Task {
            try await ref.runTransaction { data in
                data.value = ((data.value as? NSNumber)?.intValue ?? 0) + 1
                return .success(withValue: data)
            }
        }
        // The transaction listens at its location; write acknowledgements wait
        // for the listens' (as upstream).
        let listen = try await wire.nextRequest("q")
        wire.respond(to: listen.number, data: [:])
        let put = try await wire.nextRequest("p")
        #expect(put.body["h"] != nil)
        #expect(put.body["d"] as? Int == 1)
        wire.respond(to: put.number)
        let (committed, snapshot) = try await transaction.value
        #expect(committed)
        #expect(snapshot.value as? Int == 1)
    }
}
