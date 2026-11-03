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

/// The public API beyond basic reads and writes: error codes, field paths,
/// filters, cursors, value types and listener options.
@Suite(.enabled(if: Emulators.firestore != nil && Emulators.auth != nil, "Needs the Firestore and Auth emulators"), .timeLimit(.minutes(1)))
struct FirestoreAPIIntegrationTests {
  @Test func errorsCarryTheirCode() async throws {
    let fixture = try EmulatorFixture()
    do {
      try await fixture.collection.document("missing").updateData(["x": 1])
      Issue.record("The update succeeded")
    } catch FirestoreErrorCode.notFound {
      // Upstream's pattern matching works.
    }

    do {
      try await fixture.db.document("denied/doc").setData(["x": 1])
      Issue.record("The write succeeded")
    } catch {
      let nsError = error as NSError
      #expect(nsError.domain == FirestoreErrorDomain)
      #expect(nsError.code == FirestoreErrorCode.permissionDenied.rawValue)
    }
  }

  @Test func fieldPathsAddressNamesWithDots() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("dotted")

    // Map keys are field names, so "a.b" is one field here.
    try await doc.setData(["a.b": 1, "nested": ["x": 1]])
    try await doc.updateData([FieldPath(["a.b"]): 2, "nested.x": 3])

    let snapshot = try await doc.getDocument(source: .server)
    #expect(snapshot.get(FieldPath(["a.b"])) as? Int == 2)
    #expect(snapshot["nested.x"] as? Int == 3)
    #expect(snapshot.get("a") == nil)

    let matches = try await fixture.collection
      .whereField(FieldPath(["a.b"]), isEqualTo: 2)
      .getDocuments(source: .server)
    #expect(matches.documents.map(\.documentID) == ["dotted"])
  }

  @Test func mergeFieldsWriteOnlyTheNamedFields() async throws {
    let fixture = try EmulatorFixture()
    let viaDocument = fixture.collection.document("document")
    let viaBatch = fixture.collection.document("batch")
    let viaTransaction = fixture.collection.document("transaction")
    let original: [String: Any] = ["a": 0, "b": 0, "c": ["d": 0, "e": 0]]
    for doc in [viaDocument, viaBatch, viaTransaction] {
      try await doc.setData(original)
    }

    let update: [String: Any] = ["a": 1, "b": 1, "c": ["d": 1, "e": 1]]
    let fields: [Any] = ["a", FieldPath(["c", "d"])]
    try await viaDocument.setData(update, mergeFields: fields)
    try await fixture.db.batch().setData(update, forDocument: viaBatch, mergeFields: fields).commit()
    _ = try await fixture.db.runTransaction { transaction in
      transaction.setData(update, forDocument: viaTransaction, mergeFields: fields)
      return nil
    }

    for doc in [viaDocument, viaBatch, viaTransaction] {
      let data = try #require(try await doc.getDocument(source: .server).data())
      #expect(data["a"] as? Int == 1, "\(doc.documentID)")
      #expect(data["b"] as? Int == 0, "\(doc.documentID)")
      #expect(data["c"] as? [String: Int] == ["d": 1, "e": 0], "\(doc.documentID)")
    }
  }

  @Test func compositeFilters() async throws {
    let fixture = try EmulatorFixture()
    for n in 1 ... 5 {
      try await fixture.collection.document("n\(n)").setData(["n": n, "odd": n % 2 == 1])
    }

    let either = try await fixture.collection
      .whereFilter(.orFilter([.whereField("n", isEqualTo: 1), .whereField("n", isGreaterThan: 3)]))
      .order(by: "n")
      .getDocuments(source: .server)
    #expect(either.documents.map { $0.get("n") as? Int } == [1, 4, 5])

    let both = try await fixture.collection
      .whereFilter(.andFilter([.whereField("odd", isEqualTo: true),
                               .whereField("n", isGreaterOrEqualTo: 3)]))
      .order(by: "n")
      .getDocuments(source: .server)
    #expect(both.documents.map { $0.get("n") as? Int } == [3, 5])
  }

  @Test func valueCursors() async throws {
    let fixture = try EmulatorFixture()
    for n in 1 ... 5 {
      try await fixture.collection.document("n\(n)").setData(["n": n])
    }

    let byN = fixture.collection.order(by: "n")
    let range = try await byN.start(at: [2]).end(before: [4]).getDocuments(source: .server)
    #expect(range.documents.map { $0.get("n") as? Int } == [2, 3])
    let tail = try await byN.start(after: [3]).getDocuments(source: .server)
    #expect(tail.documents.map { $0.get("n") as? Int } == [4, 5])

    let byID = try await fixture.collection.order(by: FieldPath.documentID())
      .end(at: ["n2"]).getDocuments(source: .server)
    #expect(byID.documents.map(\.documentID) == ["n1", "n2"])
  }

  @Test func valuesRoundTripAsUpstream() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("values")
    let date = Date(timeIntervalSince1970: 1_700_000_000.25)
    let missing: String? = nil

    try await doc.setData(["int": 3, "double": 2.5, "date": date, "missing": missing as Any,
                           "ref": fixture.collection.document("other")])
    let snapshot = try await doc.getDocument(source: .server)

    // Numbers come back as NSNumbers, which cast to any numeric type.
    #expect(snapshot.get("int") as? Int == 3)
    #expect(snapshot.get("int") as? Int64 == 3)
    #expect(snapshot.get("double") as? Double == 2.5)
    #expect((snapshot.get("date") as? Timestamp)?.dateValue() == date)
    #expect(snapshot.get("missing") is NSNull)
    #expect(snapshot.get("ref") as? DocumentReference == fixture.collection.document("other"))
  }

  @Test func numericTransforms() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("bounds")
    try await doc.setData(["low": 5, "high": 5])

    try await doc.updateData(["low": FieldValue.minimum(Int64(3)),
                              "high": FieldValue.maximum(Int64(10))])
    try await doc.updateData(["low": FieldValue.minimum(Int64(4)),
                              "high": FieldValue.maximum(Int64(7))])

    let snapshot = try await doc.getDocument(source: .server)
    #expect(snapshot.get("low") as? Int == 3)
    #expect(snapshot.get("high") as? Int == 10)
  }

  @Test func referencesKnowTheirPlace() throws {
    let fixture = try EmulatorFixture()
    let root = fixture.db.collection("public")
    #expect(root.parent == nil)

    let nested = root.document("a").collection("b")
    #expect(nested.path == "public/a/b")
    #expect(nested.parent == root.document("a"))
    #expect(nested.document("c").firestore === fixture.db)
    #expect(nested.whereField("x", isEqualTo: 1) == nested.whereField("x", isEqualTo: 1))
    #expect(nested.whereField("x", isEqualTo: 1) != nested.whereField("x", isEqualTo: 2))
  }

  @Test func listenersOutliveTheirRegistration() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("watched")
    let (values, continuation) = AsyncStream<Int?>.makeStream()

    // As upstream, dropping the registration doesn't stop the listener.
    _ = doc.addSnapshotListener { snapshot, _ in
      continuation.yield(snapshot?.get("n") as? Int)
    }
    var iterator = values.makeAsyncIterator()
    #expect(await iterator.next() == .some(nil))

    try await doc.setData(["n": 1])
    #expect(await iterator.next() == 1)
  }

  @Test func listenersCanUseOnlyTheCache() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("cached")
    try await doc.setData(["n": 1])

    let (snapshots, continuation) = AsyncStream<DocumentSnapshot>.makeStream()
    let registration = doc.addSnapshotListener(
      options: SnapshotListenOptions().withSource(.cache)
    ) { snapshot, _ in
      if let snapshot { continuation.yield(snapshot) }
    }
    defer { registration.remove() }

    var iterator = snapshots.makeAsyncIterator()
    let snapshot = try #require(await iterator.next())
    #expect(snapshot.get("n") as? Int == 1)
    #expect(snapshot.metadata.isFromCache)
  }

  @Test func snapshotsInSyncListenersFire() async throws {
    let fixture = try EmulatorFixture()
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let registration = fixture.db.addSnapshotsInSyncListener { continuation.yield() }
    defer { registration.remove() }

    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() != nil)
  }

  @Test func transactionsTakeOptions() async throws {
    let fixture = try EmulatorFixture()
    let doc = fixture.collection.document("counted")
    try await doc.setData(["n": 1])

    let options = TransactionOptions()
    options.maxAttempts = 1
    let result = try await fixture.db.runTransaction(with: options) { transaction in
      let n = try transaction.getDocument(doc).get("n") as? Int ?? 0
      transaction.updateData(["n": n + 1], forDocument: doc)
      return n
    }
    #expect(result as? Int == 1)
    #expect(try await doc.getDocument(source: .server).get("n") as? Int == 2)
  }

  @Test func settingsAreCopies() throws {
    let fixture = try EmulatorFixture()
    let settings = fixture.db.settings
    #expect(settings.cacheSettings as? MemoryCacheSettings == MemoryCacheSettings())
    #expect(settings == fixture.db.settings)

    settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
    settings.host = "elsewhere"
    #expect(settings != fixture.db.settings)
    #expect(fixture.db.settings.cacheSettings is MemoryCacheSettings)
    #expect(MemoryCacheSettings(garbageCollectorSettings: MemoryLRUGCSettings(sizeBytes: 5))
      != MemoryCacheSettings(garbageCollectorSettings: MemoryEagerGCSetting()))
  }

  @Test func persistentCacheOutlivesTheInstance() async throws {
    let name = "persistent-\(UUID().uuidString)"
    let first = try EmulatorApp(name: name).firestore(
      cacheSettings: PersistentCacheSettings(sizeBytes: NSNumber(value: 10 * 1024 * 1024))
    )
    let doc = first.collection("public").document(UUID().uuidString)
      .collection("items").document("kept")
    try await doc.setData(["n": 1])
    try await first.terminate()

    // The same app name finds the same cache on disk.
    let second = try EmulatorApp(name: name).firestore(cacheSettings: PersistentCacheSettings())
    #expect(second !== first)
    let cached = try await second.document(doc.path).getDocument(source: .cache)
    #expect(cached.get("n") as? Int == 1)

    try await second.terminate()
    try await second.clearPersistence()
  }

  @Test func memoryCacheDoesNotOutliveTheInstance() async throws {
    let name = "memory-\(UUID().uuidString)"
    let first = try EmulatorApp(name: name).firestore(
      cacheSettings: MemoryCacheSettings(garbageCollectorSettings: MemoryEagerGCSetting())
    )
    let doc = first.collection("public").document(UUID().uuidString)
      .collection("items").document("gone")
    try await doc.setData(["n": 1])
    try await first.terminate()

    let second = try EmulatorApp(name: name).firestore()
    do {
      _ = try await second.document(doc.path).getDocument(source: .cache)
      Issue.record("The document was in the cache")
    } catch FirestoreErrorCode.unavailable {}
    try await second.terminate()
  }

  @Test func aggregationsRunOnTheServer() async throws {
    let fixture = try EmulatorFixture()
    for (n, price) in [(1, 1.5), (2, 2.5), (3, 5)] {
      try await fixture.collection.document("n\(n)").setData(["n": n, "item": ["price": price]])
    }

    let count = try await fixture.collection.count.getAggregation(source: .server)
    #expect(count.count == 3)

    let query = fixture.collection.whereField("n", isGreaterThan: 1)
    let aggregate = query.aggregate([.count(), .sum("n"), .average(FieldPath(["item", "price"]))])
    #expect(aggregate == query.aggregate([.count(), .sum("n"), .average("item.price")]))
    #expect(aggregate != query.count)

    let snapshot = try await aggregate.getAggregation(source: .server)
    #expect(snapshot.query == aggregate)
    #expect(snapshot.count == 2)
    #expect(snapshot.get(.sum("n")) as? Int == 5)
    #expect(snapshot.get(.average("item.price")) as? Double == 3.75)

    // As documented for the backend, several aggregations only see the
    // documents that have all of their fields.
    let missing = try await query.aggregate([.count(), .average("missing")])
      .getAggregation(source: .server)
    #expect(missing.count == 0)
    #expect(missing.get(.average("missing")) is NSNull)
  }

  @Test func aggregationsReportErrors() async throws {
    let fixture = try EmulatorFixture()
    do {
      _ = try await fixture.db.collection("denied").count.getAggregation(source: .server)
      Issue.record("The aggregation succeeded")
    } catch FirestoreErrorCode.permissionDenied {}
  }

  @Test func bundlesLoadDocumentsAndNamedQueries() async throws {
    let fixture = try EmulatorFixture()
    let progress = try await fixture.db.loadBundle(testBundle(projectID: Emulators.projectID))
    #expect(progress.state == .success)
    #expect(progress.documentsLoaded == 2)
    #expect(progress.totalDocuments == 2)
    #expect(progress.bytesLoaded == progress.totalBytes)

    let all = try await fixture.db.collection("coll-1").getDocuments(source: .cache)
    #expect(all.documents.map { $0.get("k") as? String } == ["a", "b"])

    let limit = try #require(await fixture.db.getQuery(named: "limit"))
    let first = try await limit.getDocuments(source: .cache)
    #expect(first.documents.map(\.documentID) == ["b"])
    let limitToLast = try #require(await fixture.db.getQuery(named: "limit-to-last"))
    let last = try await limitToLast.getDocuments(source: .cache)
    #expect(last.documents.map(\.documentID) == ["a"])
    #expect(await fixture.db.getQuery(named: "missing") == nil)
  }

  @Test func bundlesLoadFromStreams() async throws {
    let fixture = try EmulatorFixture()
    let stream = InputStream(data: testBundle(projectID: Emulators.projectID))
    let progress = try await fixture.db.loadBundle(stream)
    #expect(progress.state == .success)
    #expect(progress.documentsLoaded == 2)
  }

  @Test func invalidBundlesFail() async throws {
    let fixture = try EmulatorFixture()
    // Upstream reports every failure as `.unknown` (its error check is
    // inverted); the port passes the core's code on.
    do {
      _ = try await fixture.db.loadBundle(Data())
      Issue.record("Loading succeeded")
    } catch FirestoreErrorCode.dataLoss {}

    do {
      _ = try await fixture.db.loadBundle(testBundle(projectID: "other-project"))
      Issue.record("Loading succeeded")
    } catch FirestoreErrorCode.dataLoss {}
  }
}

/// A bundle like upstream's `testutil::CreateBundle`: documents `coll-1/a`
/// and `coll-1/b`, and the named queries "limit" and "limit-to-last".
private func testBundle(projectID: String) -> Data {
  let documents = "projects/\(projectID)/databases/(default)/documents"
  let readTime = #"{"seconds":1000,"nanos":9999}"#
  let updateTime = #"{"seconds":1,"nanos":9}"#
  func namedQuery(_ name: String, limitType: String) -> String {
    #"{"namedQuery":{"name":"\#(name)","readTime":\#(readTime),"bundledQuery":{"#
      + #""parent":"\#(documents)","structuredQuery":{"from":[{"collectionId":"coll-1"}],"#
      + #""orderBy":[{"field":{"fieldPath":"bar"},"direction":"DESCENDING"},"#
      + #"{"field":{"fieldPath":"__name__"},"direction":"DESCENDING"}],"limit":{"value":1}},"#
      + #""limitType":"\#(limitType)"}}}"#
  }
  func document(_ id: String, bar: Int) -> [String] {
    [
      #"{"documentMetadata":{"name":"\#(documents)/coll-1/\#(id)","readTime":\#(readTime),"exists":true}}"#,
      #"{"document":{"name":"\#(documents)/coll-1/\#(id)","createTime":\#(updateTime),"#
        + #""updateTime":\#(updateTime),"fields":{"k":{"stringValue":"\#(id)"},"#
        + #""bar":{"integerValue":\#(bar)}}}}"#,
    ]
  }
  let elements = [namedQuery("limit", limitType: "FIRST"),
                  namedQuery("limit-to-last", limitType: "LAST")]
    + document("a", bar: 1) + document("b", bar: 2)
  let body = elements.map { "\($0.utf8.count)\($0)" }.joined()
  let metadata = #"{"metadata":{"id":"test-bundle","createTime":{"seconds":1001,"nanos":9999},"#
    + #""version":1,"totalDocuments":2,"totalBytes":\#(body.utf8.count)}}"#
  return Data("\(metadata.utf8.count)\(metadata)\(body)".utf8)
}
