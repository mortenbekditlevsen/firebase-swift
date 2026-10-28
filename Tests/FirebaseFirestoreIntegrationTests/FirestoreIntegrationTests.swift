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

import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing

@Suite(.enabled(if: Emulators.available, "Needs the Firebase emulators"), .timeLimit(.minutes(1)))
struct FirestoreIntegrationTests {
  @Test func writesAndReadsADocument() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("ada")

    try await doc.setData(["name": "Ada", "born": Int64(1815), "tags": ["math", "poetry"]])
    let snapshot = try await doc.getDocument(source: .server)

    #expect(snapshot.exists)
    #expect(snapshot.get("name") as? String == "Ada")
    #expect(snapshot.get("born") as? Int64 == 1815)
    #expect(snapshot.get("tags") as? [String] == ["math", "poetry"])
  }

  @Test func updatesMergesAndDeletes() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("counter")

    try await doc.setData(["count": Int64(1), "label": "a"])
    try await doc.updateData(["count": FieldValue.increment(Int64(2))])
    try await doc.setData(["extra": true], merge: true)
    var snapshot = try await doc.getDocument(source: .server)
    #expect(snapshot.get("count") as? Int64 == 3)
    #expect(snapshot.get("label") as? String == "a")
    #expect(snapshot.get("extra") as? Bool == true)

    try await doc.updateData(["label": FieldValue.delete()])
    snapshot = try await doc.getDocument(source: .server)
    #expect(snapshot.get("label") == nil)

    try await doc.delete()
    snapshot = try await doc.getDocument(source: .server)
    #expect(!snapshot.exists)
  }

  @Test func updatingAMissingDocumentFails() async throws {
    let fixture = try EmulatorFixture()
    await #expect(throws: (any Error).self) {
      try await fixture.collection.document("missing").updateData(["x": Int64(1)])
    }
  }

  @Test func queriesFilterOrderAndLimit() async throws {
    let fixture = try EmulatorFixture()
    for n in Int64(1) ... 6 {
      try await fixture.collection.document("n\(n)").setData(["n": n, "even": n % 2 == 0])
    }

    let snapshot = try await fixture.collection
      .whereField("even", isEqualTo: true)
      .order(by: "n", descending: true)
      .limit(to: 2)
      .getDocuments(source: .server)

    #expect(snapshot.documents.map { $0.get("n") as? Int64 } == [6, 4])
  }

  @Test func batchWritesCommitTogether() async throws {
    let fixture = try EmulatorFixture()
    let keep = fixture.collection.document("keep")
    let gone = fixture.collection.document("gone")
    try await gone.setData(["x": Int64(1)])

    try await fixture.db.batch()
      .setData(["x": Int64(1)], forDocument: keep)
      .deleteDocument(gone)
      .commit()

    #expect(try await keep.getDocument(source: .server).exists)
    #expect(try await !gone.getDocument(source: .server).exists)
  }

  @Test func transactionsIncrementConsistently() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("tally")
    try await doc.setData(["count": Int64(0)])

    // Concurrent transactions on one document contend; Firestore retries them.
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 5 {
        group.addTask {
          _ = try await fixture.db.runTransaction { transaction in
            let snapshot = try transaction.getDocument(doc)
            let count = snapshot.get("count") as? Int64 ?? 0
            transaction.updateData(["count": count + 1], forDocument: doc)
            return nil
          }
        }
      }
      try await group.waitForAll()
    }

    #expect(try await doc.getDocument(source: .server).get("count") as? Int64 == 5)
  }

  @Test func transactionsAbortWhenTheBlockThrows() async throws {
    struct Abort: Error {}
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("untouched")

    await #expect(throws: Abort.self) {
      _ = try await fixture.db.runTransaction { transaction in
        transaction.setData(["x": Int64(1)], forDocument: doc)
        throw Abort()
      }
    }
    #expect(try await !doc.getDocument(source: .server).exists)
  }

  @Test func serverTimestampsResolve() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("stamped")

    try await doc.setData(["at": FieldValue.serverTimestamp()])
    let at = try await doc.getDocument(source: .server).get("at") as? Timestamp

    let seconds = try #require(at).seconds
    #expect(abs(Double(seconds) - Date().timeIntervalSince1970) < 600)
  }

  @Test func snapshotListenersSeeChanges() async throws {
    let fixture = try EmulatorFixture()
    let (counts, continuation) = AsyncStream<Int>.makeStream()
    let registration = fixture.collection.addSnapshotListener { snapshot, _ in
      if let snapshot { continuation.yield(snapshot.documents.count) }
    }
    defer { registration.remove() }

    var iterator = counts.makeAsyncIterator()
    #expect(await iterator.next() == 0)

    try await fixture.collection.document("first").setData(["x": Int64(1)])
    // Latency compensation reports the local write first; either way the
    // listener must reach one document.
    var latest = await iterator.next()
    while latest == 0 { latest = await iterator.next() }
    #expect(latest == 1)
  }
}
