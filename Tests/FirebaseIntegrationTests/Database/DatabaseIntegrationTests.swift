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

  @Test func writesAndReadsAValue() async throws {
    let ref = try scratchRef(EmulatorApp().database())

    try await ref.setValue(["name": "Ada", "born": 1815, "tags": ["math", "poetry"]])
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
    try await ref.setValue(["yes": true, "no": false, "one": 1, "zero": 0])

    // A second app, so the values come from the server rather than the local cache.
    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect(fromServer.childSnapshot(forPath: "yes").value as? Bool == true)
    #expect(fromServer.childSnapshot(forPath: "no").value as? Bool == false)
    for key in ["one", "zero"] {
      let value = try #require(fromServer.childSnapshot(forPath: key).value as? NSNumber)
      #expect(!isBoolean(value), "\(key) came back as a Boolean")
    }
  }

  @Test func updatesMergeAndRemovalsDelete() async throws {
    let ref = try scratchRef(EmulatorApp().database())

    try await ref.setValue(["name": "Ada", "born": 1815])
    try await ref.updateChildValues(["born": 1816, "died": 1852])
    var snapshot = try await ref.getData()
    #expect(snapshot.childSnapshot(forPath: "name").value as? String == "Ada")
    #expect((snapshot.childSnapshot(forPath: "born").value as? NSNumber)?.intValue == 1816)
    #expect((snapshot.childSnapshot(forPath: "died").value as? NSNumber)?.intValue == 1852)

    try await ref.child("died").removeValue()
    snapshot = try await ref.getData()
    #expect(!snapshot.hasChild("died"))

    try await ref.removeValue()
    snapshot = try await ref.getData()
    #expect(!snapshot.exists())
  }

  @Test func queriesOrderAndLimit() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    for (name, score) in [("a", 30), ("b", 10), ("c", 20), ("d", 40)] {
      try await ref.child(name).setValue(["score": score])
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
    let ref = try scratchRef(EmulatorApp().database())
    var keys: [String] = []
    for i in 0 ..< 3 {
      let child = ref.childByAutoId()
      try await child.setValue(i)
      keys.append(try #require(child.key))
    }

    #expect(keys == keys.sorted())
    let snapshot = try await ref.queryOrderedByKey().getData()
    #expect(snapshot.children.map(\.key) == keys)
  }

  @Test func serverTimestampsResolve() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    let before = Date().timeIntervalSince1970 * 1000

    try await ref.setValue(["at": ServerValue.timestamp])
    let at = try #require(try await ref.child("at").getData().value as? NSNumber).doubleValue

    // The emulator and the test share a clock, give or take a minute.
    #expect(abs(at - before) < 60_000)
  }

  @Test func serverIncrementsAccumulate() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValue(1)
    try await ref.setValue(ServerValue.increment(2))
    try await ref.setValue(ServerValue.increment(3))

    #expect((try await ref.getData().value as? NSNumber)?.intValue == 6)
  }

  @Test func valueObserversSeeChanges() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    let seen = Locked<[Int?]>([])
    let handle = ref.observeEventType(.value) { snapshot in
      seen.withLock { $0.append((snapshot.value as? NSNumber)?.intValue) }
    }
    defer { ref.removeObserverWithHandle(handle) }

    try? await eventually { seen.withLock { $0 } == [nil] }
    try await ref.setValue(1)
    try await ref.setValue(2)
    try? await eventually { seen.withLock { $0 } == [nil, 1, 2] }
    let values = seen.withLock { $0 }
    #expect(values == [nil, 1, 2])
  }

  @Test func childObserversSeeAddsChangesAndRemovals() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    let events = Locked<[String]>([])
    let handles = [
      ref.observeEventType(.childAdded) { snapshot in
        events.withLock { $0.append("added \(snapshot.key ?? "?")") }
      },
      ref.observeEventType(.childChanged) { snapshot in
        events.withLock { $0.append("changed \(snapshot.key ?? "?")") }
      },
      ref.observeEventType(.childRemoved) { snapshot in
        events.withLock { $0.append("removed \(snapshot.key ?? "?")") }
      },
    ]
    defer { handles.forEach(ref.removeObserverWithHandle) }

    try await ref.child("x").setValue(1)
    try await ref.child("x").setValue(2)
    try await ref.child("x").removeValue()
    try? await eventually {
      events.withLock { $0 } == ["added x", "changed x", "removed x"]
    }
    let received = events.withLock { $0 }
    #expect(received == ["added x", "changed x", "removed x"])
  }

  @Test func concurrentTransactionsDontLoseUpdates() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValue(0)
    // Several apps, each with its own connection and local cache, so the
    // server rejects stale attempts and the blocks rerun.
    let refs = try (0 ..< 3).map { _ in
      try EmulatorApp().database().reference().child(ref.parent!.key!).child(ref.key!)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for counter in refs {
        group.addTask {
          for _ in 0 ..< 5 {
            let (committed, _) = try await counter.runTransactionBlock { currentData in
              currentData.value = ((currentData.value as? NSNumber)?.intValue ?? 0) + 1
              return .success(withValue: currentData)
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
    try await ref.setValue("original")

    let (committed, _) = try await ref.runTransactionBlock { currentData in
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
    try await ref.setValue(["likes": 1, "title": "Post"])

    let (committed, snapshot) = try await ref.runTransactionBlock { currentData in
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
    try await ref.child("a").setValue(1, andPriority: 2)
    try await ref.child("b").setValue(2, andPriority: 1)

    let (committed, _) = try await ref.runTransactionBlock { currentData in
      currentData[childPath: "c"].value = 3
      return .success(withValue: currentData)
    }

    #expect(committed)
    let fromServer = try await EmulatorApp().database().reference().child(ref.parent!.key!)
      .child(ref.key!).getData()
    #expect((fromServer.childSnapshot(forPath: "c").value as? NSNumber)?.intValue == 3)
    #expect((fromServer.childSnapshot(forPath: "a").priority as? NSNumber)?.intValue == 2)
  }

  @Test func onDisconnectWritesApplyWhenTheClientDisconnects() async throws {
    let ref = try scratchRef(EmulatorApp().database())
    try await ref.setValue(["online": true, "session": "abc", "kept": "yes"])

    ref.child("online").onDisconnectSetValue(false)
    ref.child("session").onDisconnectRemoveValue()
    ref.child("status").onDisconnectUpdateChildValues(["state": "offline"])
    ref.child("kept").onDisconnectSetValue("overwritten")
    ref.child("kept").cancelDisconnectOperations()
    // The public calls don't report back, so wait for the server to queue one
    // more operation; the earlier ones are sent before it on the same connection.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      ref.child("barrier").onDisconnectSetValue(1) { error, _ in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }

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
      try await database.reference().child("users/nobody").setValue(1)
    }
  }

  @Test func rulesSeeTheSignedInUser() async throws {
    let emulatorApp = try EmulatorApp()
    let database = try emulatorApp.database()
    let uid = try await emulatorApp.auth.signInAnonymously().user.uid

    let mine = database.reference().child("users").child(uid)
    try await eventually {
      do {
        try await mine.setValue(["text": "hello"])
        return true
      } catch {
        return false
      }
    }
    #expect(try await mine.child("text").getData().value as? String == "hello")

    await #expect(throws: (any Error).self) {
      try await database.reference().child("users/someone-else").setValue(1)
    }
  }

  @Test func signingOutRevokesAccess() async throws {
    let emulatorApp = try EmulatorApp()
    let database = try emulatorApp.database()
    let uid = try await emulatorApp.auth.signInAnonymously().user.uid
    let mine = database.reference().child("users").child(uid)
    try await eventually {
      do {
        try await mine.setValue(1)
        return true
      } catch {
        return false
      }
    }

    try emulatorApp.auth.signOut()

    // The connection unauthenticates asynchronously; then writes are rejected.
    try await eventually {
      do {
        try await mine.setValue(2)
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
