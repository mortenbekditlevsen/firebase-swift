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

import FirebaseAuth
@testable import FirebaseDatabase
import Foundation
import Testing

/// Uses the rules in Tests/Emulator/database.rules.json: `public/` is open,
/// `users/$uid` is readable and writable only by that signed-in user.
@Suite(.enabled(if: Emulators.database != nil && Emulators.auth != nil,
                "Needs the Database and Auth emulators"),
       .timeLimit(.minutes(1)))
struct DatabaseIntegrationTests {
  /// A location only this test uses, under the open `public/` path.
  private func scratchRef(_ database: Database) -> DatabaseReference {
    database.reference().child("public").child(UUID().uuidString)
  }

  /// Runs `operation` again when the Database emulator fails it with "An internal error
  /// occurred". Under load the emulator (4.11.2) can throw a NullPointerException while flushing a
  /// batch of writes ("Encountered unknown exception while flushing batch" in
  /// database-debug.log), and answers every write in the batch with that error. The SDK reports
  /// it, as upstream does. A write that was applied anyway would show up in the test's totals.
  private static func retryingEmulatorBatchFailures<T>(
    _ operation: () async throws -> T
  ) async throws -> T {
    for _ in 0 ..< 2 {
      do {
        return try await operation()
      } catch let error as NSError where error.domain == "com.firebase"
        && error.localizedDescription == "An internal error occurred" {
        continue
      }
    }
    return try await operation()
  }

  @Test func writesAndReadsAValue() async throws {
    let ref = try scratchRef(EmulatorApp().database())

    try await ref.setValueAndWait(["name": "Ada", "born": 1815, "tags": ["math", "poetry"]])
    let snapshot = try await ref.getData()

    #expect(snapshot.exists())
    #expect(snapshot.key == ref.key)
    #expect(snapshot.childSnapshot(forPath: "name").value as? String == "Ada")
    #expect((snapshot.childSnapshot(forPath: "born").value as? NSNumber)?.intValue == 1815)
    #expect(snapshot.childSnapshot(forPath: "tags").childrenCount == 2)
    #expect(snapshot.hasChild("tags/1"))
    #expect(!snapshot.hasChild("died"))
  }

  /// Server data arrives as JSON, where 0 and 1 must stay numbers and only
  /// `true`/`false` are Booleans.
  @Test func numbersAndBooleansKeepTheirTypes() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["yes": true, "no": false, "one": 1, "zero": 0])

    // A second app, so the values come from the server rather than the local cache.
    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect(fromServer.childSnapshot(forPath: "yes").value as? Bool == true)
    #expect(fromServer.childSnapshot(forPath: "no").value as? Bool == false)
    // `as? Bool` also matches the numbers 0 and 1 on Linux, so check the type.
    for key in ["yes", "no"] {
      let value = try #require(fromServer.childSnapshot(forPath: key).value as? NSNumber)
      #expect(isBoolean(value), "\(key) came back as a number")
    }
    for key in ["one", "zero"] {
      let value = try #require(fromServer.childSnapshot(forPath: key).value as? NSNumber)
      #expect(!isBoolean(value), "\(key) came back as a Boolean")
    }
  }

  /// 64-bit integers keep every digit through the server (doubles have 53
  /// bits), as upstream's and Android's.
  @Test func largeIntegersKeepTheirPrecision() async throws {
    let big: Int64 = 1_542_405_709_418_655_810
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["big": big, "counter": big])
    try await ref.child("counter").setValueAndWait(ServerValue.increment(1))

    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect((fromServer.childSnapshot(forPath: "big").value as? NSNumber)?.int64Value == big)
    #expect((fromServer.childSnapshot(forPath: "counter").value as? NSNumber)?.int64Value
      == big + 1)
  }

  @Test func updatesMergeAndRemovalsDelete() async throws {
    let ref = try scratchRef(EmulatorApp().database())

    try await ref.setValueAndWait(["name": "Ada", "born": 1815])
    try await ref.updateChildValuesAndWait(["born": 1816, "died": 1852])
    var snapshot = try await ref.getData()
    #expect(snapshot.childSnapshot(forPath: "name").value as? String == "Ada")
    #expect((snapshot.childSnapshot(forPath: "born").value as? NSNumber)?.intValue == 1816)
    #expect((snapshot.childSnapshot(forPath: "died").value as? NSNumber)?.intValue == 1852)

    try await ref.child("died").removeValueAndWait()
    snapshot = try await ref.getData()
    #expect(!snapshot.hasChild("died"))

    try await ref.removeValueAndWait()
    snapshot = try await ref.getData()
    #expect(!snapshot.exists())
  }

  @Test func queriesOrderAndLimit() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    for (name, score) in [("a", 30), ("b", 10), ("c", 20), ("d", 40)] {
      try await ref.child(name).setValueAndWait(["score": score])
    }

    let lowest = try await ref.queryOrderedByChild("score").queryLimitedToFirst(2).getData()
    #expect(lowest.children.map(\.key) == ["b", "c"])

    let range = try await ref.queryOrderedByChild("score")
      .queryStartingAtValue(20).queryEndingAtValue(30).getData()
    let rangeKeys = range.children.map(\.key)
    #expect(rangeKeys == ["c", "a"])

    let last = try await ref.queryOrderedByKey().queryLimitedToLast(1).getData()
    #expect(last.children.map(\.key) == ["d"])
  }

  @Test func autoIDsSortInCreationOrder() async throws {
    let database = try EmulatorApp().database()
    // IDs start with the server's time: the local clock plus the server's
    // offset, known once connected. Connect first, so all IDs use it (a client
    // whose clock differs from the emulator's, as in a Linux VM on a Mac, would
    // otherwise make its first ID with a different clock).
    try await scratchRef(database).setValueAndWait(true)
    let ref = scratchRef(database)
    var keys: [String] = []
    for i in 0 ..< 3 {
      let child = ref.childByAutoId()
      try await child.setValueAndWait(i)
      keys.append(try #require(child.key))
    }

    #expect(keys == keys.sorted())
    let snapshot = try await ref.queryOrderedByKey().getData()
    #expect(snapshot.children.map(\.key) == keys)
  }

  @Test func serverTimestampsResolve() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    let before = Date().timeIntervalSince1970 * 1000

    try await ref.setValueAndWait(["at": ServerValue.timestamp])
    let at = try #require(try await ref.child("at").getData().value as? NSNumber).doubleValue

    // The emulator and the test share a clock, give or take a minute.
    #expect(abs(at - before) < 60_000)
  }

  @Test func serverIncrementsAccumulate() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(1)
    try await ref.setValueAndWait(ServerValue.increment(2))
    try await ref.setValueAndWait(ServerValue.increment(3))

    #expect((try await ref.getData().value as? NSNumber)?.intValue == 6)
  }

  @Test func valueObserversSeeChanges() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    var values = ref.values().makeAsyncIterator()
    #expect(try await values.next()?.exists() == false)
    try await ref.setValueAndWait(1)
    #expect((try await values.next()?.value as? NSNumber)?.intValue == 1)
    ref.setValue(2)
    #expect((try await values.next()?.value as? NSNumber)?.intValue == 2)
  }

  // Upstream 13.2.0 (#16721): testGetForChildOfObservedNodeReturnsChildValue.
  @Test func getDataOfAChildOfAnObservedLocationReturnsTheChild() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["a": ["name": "Test"], "b": ["name": "Test2"]])
    var values = ref.values().makeAsyncIterator()
    _ = try await values.next()

    let child = try await ref.child("a").getData()
    #expect(child.value as? [String: String] == ["name": "Test"])
  }

  // Upstream 13.2.0 (#16721): testGetForChildOfKeptSyncedNodeReturnsChildValue.
  @Test func getDataOfAChildOfAKeptSyncedLocationReturnsTheChild() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["a": ["name": "Test"], "b": ["name": "Test2"]])
    ref.keepSynced(true)
    // Waits for the synced data. The listen ends, so only keepSynced keeps it.
    _ = try await ref.firstValue()

    let child = try await ref.child("a").getData()
    #expect(child.value as? [String: String] == ["name": "Test"])
    ref.keepSynced(false)
  }

  // The tests below are upstream 13.2.0's (#16722) testGetForFilteredQueryDoesNotChange…
  // Port note: upstream records every event and compares the list after the get. Here a write
  // after the get must be the listener's next event; one the get caused would come first.

  @Test func aFilteredGetLeavesAFilteredListenerAtTheSameLocationAlone() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    let letters = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
    try await ref.setValueAndWait(Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, $0 + 1) }))

    // The children from "f" on, like the newest messages of a chat.
    var values = ref.queryOrderedByKey().queryStartingAtValue("f").values().makeAsyncIterator()
    #expect(try await values.next()?.childrenCount == 5)

    // The three before "f", like a page of older messages.
    let page = try await ref.queryOrderedByKey().queryEndingBeforeValue("f").queryLimitedToLast(3).getData()
    #expect(page.value as? [String: Int] == ["c": 3, "d": 4, "e": 5])

    ref.child("k").setValue(11)
    #expect(try await values.next()?.childrenCount == 6)
  }

  // https://github.com/firebase/firebase-ios-sdk/issues/8286
  @Test func aFilteredGetLeavesADefaultListenerAtTheSameLocationAlone() async throws {
    // Without persistence (the default), so that the listener doesn't start with cached data.
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["child1": ["name": "child1"], "child2": ["name": "child2"]])

    // The get starts before the listener has data, so it isn't answered from it.
    // Making the iterator registers the listener.
    let values = ref.values().makeAsyncIterator()
    let first = Task { [values] in
      var values = values
      return try await values.next()
    }
    let child = try await ref.queryOrderedByKey().queryEqualToValue("child2").getData()
    #expect(child.value as? [String: [String: String]] == ["child2": ["name": "child2"]])
    #expect(try await first.value?.childrenCount == 2)
  }

  @Test func aFilteredGetLeavesAListenerBelowItsLocationAlone() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["a": 1, "b": 2, "c": 3, "d": 4])
    var values = ref.child("a").values().makeAsyncIterator()
    #expect(try await values.next()?.value as? Int == 1)

    // The result doesn't include the observed child.
    let last = try await ref.queryOrderedByKey().queryLimitedToLast(2).getData()
    #expect(last.value as? [String: Int] == ["c": 3, "d": 4])

    ref.child("a").setValue(100)
    #expect(try await values.next()?.value as? Int == 100)
  }

  @Test func aFilteredGetDoesntOverwriteThePersistenceCache() async throws {
    let writer = try scratchRef(EmulatorApp().database())
    let database = try EmulatorApp().database()
    database.isPersistenceEnabled = true
    let reader = database.reference().child(writer.parent!.key!).child(writer.key!)
    let value = ["a": 1, "b": 2, "c": 3, "d": 4]
    try await writer.setValueAndWait(value)

    // Caches the whole value of the location.
    #expect(try await reader.getData().value as? [String: Int] == value)
    let last = try await reader.queryOrderedByKey().queryLimitedToLast(2).getData()
    #expect(last.value as? [String: Int] == ["c": 3, "d": 4])

    database.goOffline()
    defer { database.goOnline() }
    // While offline, the value comes from the persistence cache.
    #expect(try await reader.firstValue().value as? [String: Int] == value)
  }

  @Test func childObserversSeeAddsChangesAndRemovals() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    var events = ref.childEvents([.added, .changed, .removed]).makeAsyncIterator()
    // In order, though none waits for the server.
    ref.child("x").setValue(1)
    ref.child("x").setValue(2)
    ref.child("x").removeValue()
    var received: [String] = []
    for _ in 0 ..< 3 {
      let event = try #require(try await events.next())
      received.append("\(event.kind) \(event.snapshot.key ?? "?")")
    }
    #expect(received == ["added x", "changed x", "removed x"])
  }

  @Test func concurrentTransactionsDontLoseUpdates() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(0)
    // Several apps, each with its own connection and local cache, so the
    // server rejects stale attempts and the blocks rerun.
    let refs = try (0 ..< 3).map { _ in
      try EmulatorApp().database().reference().child(ref.parent!.key!).child(ref.key!)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for counter in refs {
        group.addTask {
          for _ in 0 ..< 5 {
            let (committed, _) = try await Self.retryingEmulatorBatchFailures {
              try await counter.runTransaction { currentData in
                currentData.value = ((currentData.value as? NSNumber)?.intValue ?? 0) + 1
                return .success(withValue: currentData)
              }
            }
            #expect(committed)
          }
        }
      }
      try await group.waitForAll()
    }

    let total = (try await ref.getData().value as? NSNumber)?.intValue
    #expect(total == 15)
  }

  @Test func abortedTransactionsLeaveTheDataAlone() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait("original")

    let (committed, _) = try await ref.runTransaction { currentData in
      currentData.value = "discarded"
      return .abort()
    }

    // The returned snapshot is the client's local view when the block aborted,
    // which is empty here: nothing listens to `ref`, so it isn't cached.
    #expect(!committed)
    #expect(try await ref.getData().value as? String == "original")
  }

  @Test func transactionsCanEditChildren() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["likes": 1, "title": "Post"])

    let (committed, snapshot) = try await ref.runTransaction { currentData in
      let likes = (currentData.childData(byAppendingPath: "likes").value as? NSNumber)?.intValue ?? 0
      currentData[childPath: "likes"].value = likes + 1
      currentData[childPath: "likedBy/ada"].value = true
      return .success(withValue: currentData)
    }

    #expect(committed)
    #expect((snapshot.childSnapshot(forPath: "likes").value as? NSNumber)?.intValue == 2)
    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect((fromServer.childSnapshot(forPath: "likes").value as? NSNumber)?.intValue == 2)
    #expect(fromServer.childSnapshot(forPath: "likedBy/ada").value as? Bool == true)
    #expect(fromServer.childSnapshot(forPath: "title").value as? String == "Post")
  }

  /// The server only accepts a transaction if the client's hash of the current
  /// data matches its own, and children with priorities are hashed differently.
  @Test func transactionsWorkOnDataWithPriorities() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.child("a").setValueAndWait(1, andPriority: 2)
    try await ref.child("b").setValueAndWait(2, andPriority: 1)

    let (committed, _) = try await ref.runTransaction { currentData in
      currentData[childPath: "c"].value = 3
      return .success(withValue: currentData)
    }

    #expect(committed)
    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect((fromServer.childSnapshot(forPath: "c").value as? NSNumber)?.intValue == 3)
    #expect((fromServer.childSnapshot(forPath: "a").priority as? NSNumber)?.intValue == 2)
  }

  /// After a network change the connection checks it's alive with a request
  /// (empty stats) that the server must answer, or it reconnects.
  @Test func theServerAnswersConnectionChecks() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(1)
    let connection = await ref.repo.connection
    await connection.networkMayHaveChanged()
    #expect(await connection.isCheckingConnection)
    try await eventually(timeout: .seconds(5)) { await !connection.isCheckingConnection }
  }

  @Test func onDisconnectWritesApplyWhenTheClientDisconnects() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValueAndWait(["online": true, "session": "abc", "kept": "yes"])

    ref.child("online").onDisconnect.setValue(false)
    ref.child("session").onDisconnect.removeValue()
    ref.child("status").onDisconnect.updateChildValues(["state": "offline"])
    ref.child("kept").onDisconnect.setValue("overwritten")
    ref.child("kept").onDisconnect.cancel()
    // The earlier ones are sent before this one, on the same connection.
    try await ref.child("barrier").onDisconnect.setValueAndWait(1)

    ref.database.goOffline()

    // Read through a second app, which never had the onDisconnect writes locally.
    let other = try EmulatorApp().database().reference().child(ref.parent!.key!).child(ref.key!)
    try? await eventually {
      (try? await other.child("online").getData().value as? Bool) == false
    }
    let snapshot = try await other.getData()
    #expect(snapshot.childSnapshot(forPath: "online").value as? Bool == false)
    #expect(!snapshot.hasChild("session"))
    #expect(snapshot.childSnapshot(forPath: "status/state").value as? String == "offline")
    #expect(snapshot.childSnapshot(forPath: "kept").value as? String == "yes")
  }

  @Test func unauthenticatedWritesToProtectedPathsFail() async throws {
    let database = try EmulatorApp().database()
    await #expect(throws: (any Error).self) {
      try await database.reference().child("users/nobody").setValueAndWait(1)
    }
  }

  @Test func rulesSeeTheSignedInUser() async throws {
    let emulatorApp = try EmulatorApp()
    let database = try emulatorApp.database()
    let uid = try await emulatorApp.auth.signInAnonymously().user.uid

    let mine = database.reference().child("users").child(uid)
    try await eventually {
      do {
        try await mine.setValueAndWait(["text": "hello"])
        return true
      } catch {
        return false
      }
    }
    #expect(try await mine.child("text").getData().value as? String == "hello")

    await #expect(throws: (any Error).self) {
      try await database.reference().child("users/someone-else").setValueAndWait(1)
    }
  }

  @Test func signingOutRevokesAccess() async throws {
    let emulatorApp = try EmulatorApp()
    let database = try emulatorApp.database()
    let uid = try await emulatorApp.auth.signInAnonymously().user.uid
    let mine = database.reference().child("users").child(uid)
    try await eventually {
      do {
        try await mine.setValueAndWait(1)
        return true
      } catch {
        return false
      }
    }

    try emulatorApp.auth.signOut()

    // The connection unauthenticates asynchronously; then writes are rejected.
    try await eventually {
      do {
        try await mine.setValueAndWait(2)
        return false
      } catch {
        return true
      }
    }
  }
}

/// Whether `value` is a Boolean, as opposed to an `NSNumber` holding 0 or 1.
private func isBoolean(_ value: NSNumber) -> Bool {
  #if canImport(Darwin)
    return value === kCFBooleanTrue || value === kCFBooleanFalse
  #else
    return String(cString: value.objCType) == "c"
  #endif
}
