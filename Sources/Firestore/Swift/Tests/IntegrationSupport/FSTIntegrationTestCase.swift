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

// A Swift port of upstream's FSTIntegrationTestCase and FSTEventAccumulator
// (Example/Tests/Util/*.mm), which upstream's Swift integration tests in
// `Integration/` build on. It runs them against the Firestore emulator, from
// FIRESTORE_EMULATOR_HOST as `firebase emulators:exec` sets it, and skips them
// without it.

import FirebaseCore
import FirebaseFirestore
import Foundation
// Upstream's tests get XCTest through their Objective-C bridging header.
@_exported import XCTest

enum FSTBackendEdition {
  case standard
  case enterprise
}

enum FSTTargetBackend {
  case prod
  case nightly
  case emulator
  case qa
}

private let expectationWaitSeconds: TimeInterval = 25

/// Matches `firebase.json`'s emulator project, so its rules apply.
private let emulatorProjectID = "demo-firebase-swift"

class FSTIntegrationTestCase: XCTestCase {
  var db: Firestore!
  var eventAccumulator: FSTEventAccumulator<any FSTSnapshot>!
  private var firestores: [Firestore] = []

  /// The emulator's address, or nil to skip the tests.
  private static var emulatorHost: String? {
    ProcessInfo.processInfo.environment["FIRESTORE_EMULATOR_HOST"]
  }

  class func projectID() -> String { emulatorProjectID }

  class func databaseID() -> String {
    ProcessInfo.processInfo.environment["TARGET_DATABASE_ID"] ?? "(default)"
  }

  class func backendEdition() -> FSTBackendEdition {
    ProcessInfo.processInfo.environment["BACKEND_EDITION"] == "enterprise" ? .enterprise : .standard
  }

  class func targetBackend() -> FSTTargetBackend { .emulator }

  class func isRunningAgainstEmulator() -> Bool { true }

  class func settings() -> FirestoreSettings {
    let settings = FirestoreSettings()
    if let host = emulatorHost {
      settings.host = host
    }
    settings.isSSLEnabled = false
    return settings
  }

  override func setUpWithError() throws {
    try super.setUpWithError()
    guard Self.emulatorHost != nil else {
      throw XCTSkip("Needs the Firestore emulator (FIRESTORE_EMULATOR_HOST)")
    }
    // Some tests use the default app, as upstream's test host configures one.
    if !FirebaseApp.isDefaultAppConfigured {
      FirebaseApp.configure(options: Self.appOptions(projectID: Self.projectID()))
    }
    firestores = []
    db = firestore()
    eventAccumulator = FSTEventAccumulator(forTest: self)
  }

  override func tearDown() {
    for firestore in firestores {
      terminateFirestore(firestore)
      // Each instance has its own app, so its cache is never used again.
      run("clearPersistence") { try await firestore.clearPersistence() }
    }
    firestores = []
    super.tearDown()
  }

  private static func appOptions(projectID: String) -> FirebaseOptions {
    var options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
    options.projectID = projectID
    options.apiKey = "fake-api-key"
    return options
  }

  /// A new instance with its own app, so it has its own cache (upstream gives
  /// each one its own persistence key).
  func firestore() -> Firestore {
    firestore(withProjectID: Self.projectID())
  }

  func firestore(withProjectID projectID: String) -> Firestore {
    let app = FirebaseApp(options: Self.appOptions(projectID: projectID),
                          name: "integration-\(UUID().uuidString)")
    return firestore(with: app)
  }

  func firestore(with app: FirebaseApp) -> Firestore {
    let firestore = Firestore.firestore(app: app, database: Self.databaseID())
    firestore.settings = Self.settings()
    firestores.append(firestore)
    return firestore
  }

  func terminateFirestore(_ firestore: Firestore) {
    run("terminate") { try await firestore.terminate() }
  }

  func documentPath() -> String {
    "test-collection/\(autoID())"
  }

  func documentRef() -> DocumentReference {
    db.document(documentPath())
  }

  func collectionRef() -> CollectionReference {
    db.collection("test-collection-\(autoID())")
  }

  func collectionRef(withDocuments documents: [String: [String: Any]]) -> CollectionReference {
    let collection = collectionRef()
    // Use a different instance to write the documents.
    writeAllDocuments(documents, toCollection: firestore().collection(collection.path))
    return collection
  }

  func writeAllDocuments(_ documents: [String: [String: Any]],
                         toCollection collection: CollectionReference) {
    var commits: [XCTestExpectation] = []
    var batch: WriteBatch?
    var batchSize = 0
    func commit() {
      guard let current = batch else { return }
      let committed = expectation(description: "WriteBatch commit")
      current.commit { error in
        XCTAssertNil(error, "WriteBatch commit failed: \(String(describing: error))")
        committed.fulfill()
      }
      commits.append(committed)
      batch = nil
      batchSize = 0
    }
    for (key, value) in documents {
      if batch == nil {
        batch = collection.firestore.batch()
      }
      batch?.setData(value, forDocument: collection.document(key))
      batchSize += 1
      // Write batches are capped at 500 writes. Use 400 just to be safe.
      if batchSize == 400 {
        commit()
      }
    }
    commit()
    wait(for: commits, timeout: expectationWaitSeconds)
  }

  func readerAndWriterOnDocumentRef(_ action: (DocumentReference, DocumentReference) -> Void) {
    let path = documentPath()
    action(db.document(path), firestore().document(path))
  }

  func readDocument(forRef ref: DocumentReference,
                    source: FirestoreSource = .default) -> DocumentSnapshot {
    var result: DocumentSnapshot?
    let read = expectation(description: "getData")
    ref.getDocument(source: source) { snapshot, error in
      XCTAssertNil(error)
      result = snapshot
      read.fulfill()
    }
    awaitExpectation(read)
    return result!
  }

  func readDocumentSet(forRef query: Query, source: FirestoreSource = .default) -> QuerySnapshot {
    var result: QuerySnapshot?
    let read = expectation(description: "getData")
    query.getDocuments(source: source) { snapshot, error in
      XCTAssertNil(error)
      result = snapshot
      read.fulfill()
    }
    awaitExpectation(read)
    return result!
  }

  func readSnapshot(forRef ref: DocumentReference, requireOnline: Bool) -> DocumentSnapshot {
    var result: DocumentSnapshot?
    let received = expectation(description: "listener")
    let listener = ref.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
      XCTAssertNil(error)
      if let snapshot, result == nil, !requireOnline || !snapshot.metadata.isFromCache {
        result = snapshot
        received.fulfill()
      }
    }
    awaitExpectation(received)
    listener.remove()
    return result!
  }

  func readSnapshot(forAggregate query: AggregateQuery) -> AggregateQuerySnapshot {
    var result: AggregateQuerySnapshot?
    run("aggregate result") { result = try await query.getAggregation(source: .server) }
    return result!
  }

  func writeDocumentRef(_ ref: DocumentReference, data: [String: Any]) {
    let written = expectation(description: "setData")
    ref.setData(data, completion: completionForExpectation(written))
    awaitExpectation(written)
  }

  func updateDocumentRef(_ ref: DocumentReference, data: [AnyHashable: Any]) {
    let updated = expectation(description: "updateData")
    ref.updateData(data, completion: completionForExpectation(updated))
    awaitExpectation(updated)
  }

  func deleteDocumentRef(_ ref: DocumentReference) {
    let deleted = expectation(description: "deleteDocument")
    ref.delete(completion: completionForExpectation(deleted))
    awaitExpectation(deleted)
  }

  func addDocumentRef(_ ref: CollectionReference, data: [String: Any]) -> DocumentReference {
    let added = expectation(description: "addDocument")
    let document = ref.addDocument(data: data, completion: completionForExpectation(added))
    awaitExpectation(added)
    return document
  }

  func mergeDocumentRef(_ ref: DocumentReference, data: [String: Any]) {
    let merged = expectation(description: "setDataWithMerge")
    ref.setData(data, merge: true, completion: completionForExpectation(merged))
    awaitExpectation(merged)
  }

  func mergeDocumentRef(_ ref: DocumentReference, data: [String: Any], fields: [Any]) {
    let merged = expectation(description: "setDataWithMerge")
    ref.setData(data, mergeFields: fields, completion: completionForExpectation(merged))
    awaitExpectation(merged)
  }

  func commitWriteBatch(_ batch: WriteBatch) {
    let committed = expectation(description: "WriteBatch commit")
    batch.commit { error in
      XCTAssertNil(error, "WriteBatch commit should have succeeded: \(String(describing: error))")
      committed.fulfill()
    }
    awaitExpectation(committed)
  }

  /// Runs a transaction and waits for it. The block's error pointer is
  /// `NSErrorPointer` on Apple platforms; Linux has none.
  func runTransaction(_ db: Firestore,
                      block: @escaping (Transaction, FSTErrorPointer) -> Any?,
                      completion: ((Any?, Error?) -> Void)? = nil) {
    let done = expectation(description: "runTransaction")
    db.runTransaction(with: nil, block: { transaction in
      var error: NSError?
      let result = withUnsafeMutablePointer(to: &error) { pointer in
        #if canImport(Darwin)
          block(transaction, AutoreleasingUnsafeMutablePointer(pointer))
        #else
          block(transaction, pointer)
        #endif
      }
      if let error { throw error }
      return result
    }, completion: { result, error in
      completion?(result, error)
      done.fulfill()
    })
    awaitExpectation(done)
  }

  func disableNetwork() {
    run("disableNetwork") { try await self.db.disableNetwork() }
  }

  func enableNetwork() {
    run("enableNetwork") { try await self.db.enableNetwork() }
  }

  /// Checks that `query` gives the same documents from the server as from
  /// the cache, both by a full collection scan and by remote keys, and that
  /// they're `expectedDocs`.
  func checkOnlineAndOfflineCollection(_ collection: Query, query: Query,
                                       matchesResult expectedDocs: [String]) {
    // Order matters: the first read fills the cache with the whole collection.
    _ = readDocumentSet(forRef: collection, source: .server)
    let fromCacheFullScan = readDocumentSet(forRef: query, source: .cache)
    let fromServer = readDocumentSet(forRef: query, source: .server)
    let fromCacheRemoteKeys = readDocumentSet(forRef: query, source: .cache)
    XCTAssertEqual(FIRQuerySnapshotGetIDs(fromServer), FIRQuerySnapshotGetIDs(fromCacheFullScan))
    XCTAssertEqual(FIRQuerySnapshotGetIDs(fromServer), FIRQuerySnapshotGetIDs(fromCacheRemoteKeys))
    XCTAssertEqual(FIRQuerySnapshotGetIDs(fromServer), expectedDocs)
  }

  func waitUntil(_ predicate: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: expectationWaitSeconds)
    while !predicate(), Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    if !predicate() {
      XCTFail("Timeout")
    }
  }

  func awaitExpectation(_ expectation: XCTestExpectation) {
    wait(for: [expectation], timeout: expectationWaitSeconds)
  }

  func awaitExpectations() {
    waitForExpectations(timeout: expectationWaitSeconds)
  }

  func defaultExpectationWaitSeconds() -> TimeInterval { expectationWaitSeconds }

  func completionForExpectation(withName name: String) -> (Error?) -> Void {
    completionForExpectation(expectation(description: name))
  }

  func completionForExpectation(_ expectation: XCTestExpectation) -> (Error?) -> Void {
    { error in
      XCTAssertNil(error)
      expectation.fulfill()
    }
  }

  /// Runs an async operation and waits for it, failing the test on an error.
  private func run(_ description: String, _ operation: @escaping () async throws -> Void) {
    let done = expectation(description: description)
    Task {
      do {
        try await operation()
      } catch {
        XCTFail("\(description) failed: \(error)")
      }
      done.fulfill()
    }
    awaitExpectation(done)
  }

  private func autoID() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    return String((0 ..< 20).map { _ in alphabet.randomElement()! })
  }
}

#if canImport(Darwin)
  typealias FSTErrorPointer = NSErrorPointer
#else
  typealias FSTErrorPointer = UnsafeMutablePointer<NSError?>?
#endif

/// A document or query snapshot, which upstream's tests read as `AnyObject`.
protocol FSTSnapshot {
  var metadata: SnapshotMetadata { get }
}

extension DocumentSnapshot: FSTSnapshot {}
extension QuerySnapshot: FSTSnapshot {}

/// Collects snapshot events, so tests can wait for them one by one.
final class FSTEventAccumulator<EventType>: @unchecked Sendable {
  private unowned let testCase: XCTestCase
  private let lock = NSLock()
  // Upstream records an error (a nil snapshot) as NSNull.
  private var events: [EventType?] = []
  private var maxEvents = 0
  private var expectation: XCTestExpectation?
  private var rejectAdditionalEvents = false

  init(forTest testCase: XCTestCase) {
    self.testCase = testCase
  }

  static func accumulator(forTest testCase: XCTestCase) -> FSTEventAccumulator {
    FSTEventAccumulator(forTest: testCase)
  }

  func awaitEvents(_ count: Int, name: String) -> [EventType] {
    let pending: XCTestExpectation = lock.withLock {
      precondition(expectation == nil, "Existing expectation still pending?")
      let pending = testCase.expectation(description: name)
      expectation = pending
      maxEvents += count
      checkFulfilled()
      return pending
    }
    // Don't wait while holding the lock, to avoid deadlocking.
    testCase.wait(for: [pending], timeout: expectationWaitSeconds)
    return lock.withLock {
      events[(maxEvents - count) ..< min(maxEvents, events.count)].map { event in
        guard let event else { preconditionFailure("The listener reported an error") }
        return event
      }
    }
  }

  func awaitEvent(withName name: String) -> EventType {
    let events = awaitEvents(1, name: name)
    guard let event = events.first else { preconditionFailure("No event: \(name)") }
    return event
  }

  func awaitLocalEvent() -> EventType {
    var event: EventType
    repeat {
      event = awaitEvent(withName: "Local Event")
    } while !hasPendingWrites(event)
    return event
  }

  func awaitRemoteEvent() -> EventType {
    var event: EventType
    repeat {
      event = awaitEvent(withName: "Remote Event")
    } while hasPendingWrites(event)
    return event
  }

  func assertNoAdditionalEvents() {
    lock.withLock { rejectAdditionalEvents = true }
  }

  /// A listener for documents or queries.
  var valueEventHandler: (Any?, Error?) -> Void {
    { [self] value, _ in
      lock.withLock {
        precondition(!rejectAdditionalEvents, "Unexpected event: \(String(describing: value))")
        events.append(value.map { $0 as! EventType })
        checkFulfilled()
      }
    }
  }

  private func hasPendingWrites(_ event: EventType) -> Bool {
    guard let snapshot = event as? any FSTSnapshot else {
      preconditionFailure("Unexpected event: \(event)")
    }
    return snapshot.metadata.hasPendingWrites
  }

  /// Called with the lock held.
  private func checkFulfilled() {
    if events.count >= maxEvents {
      expectation?.fulfill()
      expectation = nil
    }
  }
}

/// The BSON types, which upstream's tests compare with values from
/// heterogeneous dictionary literals: `NSObject` there, `Any` here.
protocol FSTBSONValue: Equatable {}

extension MinKey: FSTBSONValue {}
extension MaxKey: FSTBSONValue {}
extension RegexValue: FSTBSONValue {}
extension Int32Value: FSTBSONValue {}
extension Decimal128Value: FSTBSONValue {}
extension BSONObjectId: FSTBSONValue {}
extension BSONTimestamp: FSTBSONValue {}
extension Blob: FSTBSONValue {}

func XCTAssertEqual<T: FSTBSONValue>(_ expression1: @autoclosure () throws -> T,
                                  _ expression2: @autoclosure () throws -> Any?,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
  do {
    let lhs = try expression1()
    let rhs = try expression2()
    // Compared here: calling XCTAssertEqual would pick this overload again.
    if (rhs as? T) != lhs {
      XCTFail("XCTAssertEqual failed: (\(lhs)) is not equal to (\(String(describing: rhs))) \(message())",
              file: file, line: line)
    }
  } catch {
    XCTFail("XCTAssertEqual threw \(error) \(message())", file: file, line: line)
  }
}

func FIRQuerySnapshotGetData(_ snapshot: QuerySnapshot) -> [[String: Any]] {
  snapshot.documents.map { $0.data() }
}

func FIRQuerySnapshotGetIDs(_ snapshot: QuerySnapshot) -> [String] {
  snapshot.documents.map(\.documentID)
}

func FIRDocumentReferenceArrayFromQuerySnapshot(_ snapshot: QuerySnapshot) -> [DocumentReference] {
  snapshot.documents.map(\.reference)
}

/// Upstream catches Objective-C exceptions here. The port stops the process
/// where upstream raises one, so this only runs `block`; tests that expect an
/// exception are skipped with a port note.
enum FSTExceptionCatcher {
  static func catchException(_ block: () -> Void) throws {
    block()
  }
}

enum FSTNSExceptionUtil {
  static func testForException(_ block: () -> Any?, reasonContains reason: String) -> Bool {
    preconditionFailure("The port can't catch exceptions; skip the test instead.")
  }
}
