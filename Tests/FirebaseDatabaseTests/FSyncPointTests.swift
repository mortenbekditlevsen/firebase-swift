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

// Port of upstream's FirebaseDatabase/Tests/Unit/FSyncPointTests.m (13.1.1), which
// runs Resources/syncPointSpec.json (copied unchanged) through the sync tree.
// Port notes: registrations are matched through `FEventRegistrationMatcher`, so
// an unlisten's `callbackId` becomes a `.handle`; snapshots need a reference,
// which comes from a repo for a dummy host (upstream passes a nil repo).

@testable import FirebaseDatabase
import XCTest

private let dummyRepo = FRepoManager.getRepo(
  FRepoInfo(host: "example.com", isSecure: false, withNamespace: "default"),
  config: FTestHelpers.defaultConfig()
)

private final class FTestEventRegistration: FEventRegistration {
  let spec: [String: Any]
  let query: FQuerySpec

  init(spec: [String: Any], query: FQuerySpec) {
    self.spec = spec
    self.query = query
  }

  func responseTo(_ eventType: DataEventType) -> Bool {
    true
  }

  func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent {
    let ref = DatabaseReference(repo: dummyRepo, path: query.path)
    let snap: DataSnapshot
    if change.type == .value {
      snap = DataSnapshot(ref: ref, indexedNode: change.indexedNode)
    } else {
      snap = DataSnapshot(ref: ref.child(change.childKey!), indexedNode: change.indexedNode)
    }
    return FDataEvent(eventType: change.type, eventRegistration: self, dataSnapshot: snap,
                      prevName: change.prevKey)
  }

  func matches(_ other: FEventRegistrationMatcher) -> Bool {
    if case let .handle(handle) = other, let callbackId = spec["callbackId"] as? Int {
      return callbackId == handle
    } else {
      return false
    }
  }

  func fireEvent(_ event: FEvent) {
    fatalError("Method not implemented.")
  }

  func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent? {
    fatalError("Method not implemented.")
  }
}

private nonisolated(unsafe) var loadedSpecs: [[String: Any]]?

class FSyncPointTests: XCTestCase {
  /// For failure messages.
  private var currentSpecName = ""
  private func queryKey(for query: FQuerySpec, tagId: Int?) -> String {
    "\(query.path)|\(query.params)|\(tagId.map(String.init) ?? "nil")"
  }

  private func actualEvent(_ actual: FDataEvent, equalsExpected expected: [String: Any]) {
    XCTAssertEqual(actual.eventType, stringToEventType(expected["type"] as? String),
                   "Event type should be equal")
    if actual.eventType != .value {
      let childName = actual.snapshot.key
      XCTAssertEqual(childName, expected["name"] as? String, "Snapshot name should be equal")
      if expected["prevName"] is NSNull {
        XCTAssertNil(actual.prevName, "prevName should be nil")
      } else {
        XCTAssertEqual(actual.prevName, expected["prevName"] as? String,
                       "prevName should be equal")
      }
    }
    let actualHash = actual.snapshot.node.node.dataHash()
    let expectedHash = NODE(expected["data"]).dataHash()
    XCTAssertEqual(actualHash, expectedHash, "Data hash should be equal")
  }

  /// `actual` holds FDataEvents; `expected` holds dictionaries.
  private func actualEvents(_ actual: [FEvent], exactMatchesExpected expected: [[String: Any]]) {
    if expected.count < actual.count {
      XCTFail("Got extra events: \(describe(actual))")
    } else if expected.count > actual.count {
      XCTFail("Missing events: \(describe(actual))")
    } else {
      for i in 0 ..< expected.count {
        actualEvent(actual[i] as! FDataEvent, equalsExpected: expected[i])
      }
    }
  }

  private func describe(_ events: [FEvent]) -> String {
    events.map { event in
      guard let event = event as? FDataEvent else { return event.description }
      return "\(event.eventType) \(event.snapshot.key ?? "-") prev=\(event.prevName ?? "nil") "
        + "\(event.snapshot.value ?? "nil")"
    }.joined(separator: "; ")
  }

  private func assertOrderedFirstEvent(_ e1: DataEventType, secondEvent e2: DataEventType) {
    let eventOrdering: [DataEventType] = [
      .childRemoved, .childAdded, .childMoved, .childChanged, .value,
    ]
    let idx1 = eventOrdering.firstIndex(of: e1)!
    let idx2 = eventOrdering.firstIndex(of: e2)!
    if idx1 > idx2 {
      XCTFail("Received \(e2) after \(e1)")
    }
  }

  private func stringToEventType(_ stringType: String?) -> DataEventType {
    switch stringType {
    case "child_added": return .childAdded
    case "child_removed": return .childRemoved
    case "child_changed": return .childChanged
    case "child_moved": return .childMoved
    case "value": return .value
    default:
      XCTFail("Unknown event type \(stringType ?? "nil")")
      return .value
    }
  }

  private func actualEventSet(_ actual: [FEvent], matchesExpected expected: [[String: Any]],
                              atBasePath basePathStr: String?) {
    // don't worry about order for now
    XCTAssertEqual(expected.count, actual.count,
                   "Mismatched lengths in \(currentSpecName).\nExpected: \(expected)\nActual: \(describe(actual))")
    guard expected.count == actual.count else { return }

    var currentExpected = expected
    var currentActual = actual.map { $0 as! FDataEvent }
    let basePath = basePathStr.map { FPath(with: $0) } ?? .empty
    while !currentExpected.isEmpty {
      // Step 1: find location range in expected
      // we expect all events for a particular path to be in a group
      let currentPath = basePath.child(fromString: currentExpected[0]["path"] as! String)
      var i = 1
      while i < currentExpected.count {
        let otherPath = basePath.child(fromString: currentExpected[i]["path"] as! String)
        if currentPath == otherPath {
          i += 1
        } else {
          break
        }
      }

      // Step 2: foreach in actual, asserting location
      for j in 0 ..< i {
        let eventRegistration = currentActual[j].eventRegistration as! FTestEventRegistration
        let actualPath = basePath.child(fromString: eventRegistration.spec["path"] as! String)
        if currentPath != actualPath {
          XCTFail("Expected path \(actualPath) to equal \(currentPath)")
        }
      }

      // Step 3: slice each array
      var expectedSlice = Array(currentExpected[0 ..< i])
      let actualSlice = currentActual[0 ..< i]

      // foreach in actual, stack up to enforce ordering, find in expected
      var actualMap: [String: [FDataEvent]] = [:]
      for actualEvent in actualSlice {
        let eventRegistration = actualEvent.eventRegistration as! FTestEventRegistration
        let query = eventRegistration.query
        let spec = eventRegistration.spec
        let listenId = "\(basePath.child(fromString: spec["path"] as! String))|\(query)"
        if var eventStack = actualMap[listenId] {
          // stack this event up, and make sure it obeys ordering constraints
          let prevEvent = eventStack[eventStack.count - 1]
          assertOrderedFirstEvent(prevEvent.eventType, secondEvent: actualEvent.eventType)
          eventStack.append(actualEvent)
          actualMap[listenId] = eventStack
        } else {
          // this is the first event for this listen, just initialize it
          actualMap[listenId] = [actualEvent]
        }
        // Ordering has been enforced, make sure we can find this in the expected events
        let indexToRemove = expectedSlice.firstIndex { expectedEvent in
          let expectedType = stringToEventType(expectedEvent["type"] as? String)
          guard expectedType == actualEvent.eventType else { return false }
          if expectedType != .value {
            if expectedEvent["name"] as? String != actualEvent.snapshot.key {
              return false // short circuit, not a match
            }
            if expectedType != .childRemoved &&
              !(expectedEvent["prevName"] is NSNull && actualEvent.prevName == nil) &&
              !(!(expectedEvent["prevName"] is NSNull) &&
                expectedEvent["prevName"] as? String == actualEvent.prevName) {
              return false // short circuit, not a match
            }
          }
          // make sure the snapshots match
          let snapHash = actualEvent.snapshot.node.node.dataHash()
          let expectedHash = NODE(expectedEvent["data"]).dataHash()
          return snapHash == expectedHash
        }
        XCTAssertNotNil(indexToRemove,
                        "Could not find matching expected event for \(actualEvent.description)")
        if let indexToRemove {
          expectedSlice.remove(at: indexToRemove)
        }
      }
      currentExpected = Array(currentExpected[i...])
      currentActual = Array(currentActual[i...])
    }
  }

  private func parseParams(_ specParams: [String: Any]?, forPath path: FPath) -> FQuerySpec {
    var query = FQueryParams.defaultInstance
    var params: [String: Any]
    if let specParams {
      params = specParams
      if params["tag"] == nil {
        XCTFail("Error: Non-default queries must have tag")
      }
    } else {
      params = [:]
    }

    if let orderBy = params["orderBy"] as? String {
      query = query.orderBy(.path(FPath(with: orderBy)))
      params.removeValue(forKey: "orderBy")
    }
    if params["orderByKey"] != nil {
      query = query.orderBy(.key)
      params.removeValue(forKey: "orderByKey")
    }
    if params["orderByPriority"] != nil {
      query = query.orderBy(.priority)
      params.removeValue(forKey: "orderByPriority")
    }
    if let startAt = params["startAt"] as? [String: Any] {
      let node = NODE(startAt["index"])
      if let name = startAt["name"] as? String {
        query = query.startAt(node, childKey: name)
      } else {
        query = query.startAt(node)
      }
      params.removeValue(forKey: "startAt")
    }
    if let endAt = params["endAt"] as? [String: Any] {
      let node = NODE(endAt["index"])
      if let name = endAt["name"] as? String {
        query = query.endAt(node, childKey: name)
      } else {
        query = query.endAt(node)
      }
      params.removeValue(forKey: "endAt")
    }
    if let equalTo = params["equalTo"] as? [String: Any] {
      let node = NODE(equalTo["index"])
      if let name = equalTo["name"] as? String {
        query = query.startAt(node, childKey: name).endAt(node, childKey: name)
      } else {
        query = query.startAt(node).endAt(node)
      }
      params.removeValue(forKey: "equalTo")
    }
    if let limitToFirst = params["limitToFirst"] as? Int {
      query = query.limitToFirst(limitToFirst)
      params.removeValue(forKey: "limitToFirst")
    }
    if let limitToLast = params["limitToLast"] as? Int {
      query = query.limitToLast(limitToLast)
      params.removeValue(forKey: "limitToLast")
    }

    params.removeValue(forKey: "tag")
    if !params.isEmpty {
      XCTFail("Unsupported query parameter: \(params)")
    }
    return FQuerySpec(path: path, params: query)
  }

  private func runTest(_ testSpec: [String: Any], atBasePath basePath: String?) {
    final class Listens: @unchecked Sendable {
      var keys: Set<String> = []
    }
    let listens = Listens()
    let listenProvider = FListenProvider(
      startListening: { [unowned self] query, tagId, _, _ in
        let key = self.queryKey(for: query, tagId: tagId)
        precondition(!listens.keys.contains(key), "Duplicate listen")
        listens.keys.insert(key)
        return []
      },
      stopListening: { [unowned self] query, tagId in
        let key = self.queryKey(for: query, tagId: tagId)
        XCTAssertTrue(listens.keys.contains(key),
                      "Missing record of query that we're removing")
        listens.keys.remove(key)
      }
    )

    let syncTree = FSyncTree(listenProvider: listenProvider)
    currentSpecName = "\(testSpec["name"] ?? "?") at \(basePath ?? "/")"

    var currentWriteId = 0
    for spec in testSpec["steps"] as! [[String: Any]] {
      // Almost everything has a path...
      var path = FPath.empty
      if let basePath {
        path = path.child(fromString: basePath)
      }
      if let specPath = spec["path"] as? String {
        path = path.child(fromString: specPath)
      }

      let expected = spec["events"] as? [[String: Any]] ?? []
      let tag = spec["tag"] as? Int
      switch spec["type"] as? String {
      case "listen":
        let query = parseParams(spec["params"] as? [String: Any], forPath: path)
        let eventRegistration = FTestEventRegistration(spec: spec, query: query)
        let events = syncTree.addEventRegistration(eventRegistration, forQuery: query)
        actualEvents(events, exactMatchesExpected: expected)

      case "unlisten":
        let query = parseParams(spec["params"] as? [String: Any], forPath: path)
        // Upstream's registration without a callbackId matches nothing.
        let matcher = FEventRegistrationMatcher.handle(spec["callbackId"] as? Int ?? .min)
        let events = syncTree.removeEventRegistration(matcher, forQuery: query, cancelError: nil)
        actualEvents(events, exactMatchesExpected: expected)

      case "serverUpdate":
        let update = NODE(spec["data"])
        let events = if let tag {
          syncTree.applyTaggedQueryOverwriteAtPath(path, newData: update, tagId: tag)
        } else {
          syncTree.applyServerOverwriteAtPath(path, newData: update)
        }
        actualEventSet(events, matchesExpected: expected, atBasePath: basePath)

      case "serverMerge":
        let compoundWrite = FCompoundWrite.compoundWrite(
          valueDictionary: spec["data"] as! [String: Any]
        )
        let events = if let tag {
          syncTree.applyTaggedQueryMergeAtPath(path, changedChildren: compoundWrite, tagId: tag)
        } else {
          syncTree.applyServerMergeAtPath(path, changedChildren: compoundWrite)
        }
        actualEventSet(events, matchesExpected: expected, atBasePath: basePath)

      case "set":
        let toSet = NODE(spec["data"])
        let visible = spec["visible"] as? Bool ?? true
        let events = syncTree.applyUserOverwriteAtPath(path, newData: toSet,
                                                       writeId: currentWriteId,
                                                       isVisible: visible)
        currentWriteId += 1
        actualEventSet(events, matchesExpected: expected, atBasePath: basePath)

      case "update":
        let compoundWrite = FCompoundWrite.compoundWrite(
          valueDictionary: spec["data"] as! [String: Any]
        )
        let events = syncTree.applyUserMergeAtPath(path, changedChildren: compoundWrite,
                                                   writeId: currentWriteId)
        currentWriteId += 1
        actualEventSet(events, matchesExpected: expected, atBasePath: basePath)

      case "ackUserWrite":
        let writeId = spec["writeId"] as! Int
        let revert = spec["revert"] as? Bool ?? false
        let events = syncTree.ackUserWriteWithWriteId(writeId, revert: revert, persist: true,
                                                      clock: FTestClock())
        actualEventSet(events, matchesExpected: expected, atBasePath: basePath)

      case "suppressWarning":
        // Do nothing. This is a hack so JS's Jasmine tests don't throw warnings for "expect no
        // errors" tests.
        break

      default:
        XCTFail("Unknown step: \(spec["type"] ?? "nil")")
      }
    }
  }

  private func loadSpecs() -> [[String: Any]] {
    if let loadedSpecs { return loadedSpecs }
    let url = Bundle.module.url(forResource: "syncPointSpec", withExtension: "json")!
    let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url))
    loadedSpecs = json as? [[String: Any]]
    return loadedSpecs!
  }

  private func specsForName(_ name: String) -> [String: Any]? {
    let spec = loadSpecs().first { $0["name"] as? String == name }
    if spec == nil {
      XCTFail("No such test: \(name)")
    }
    return spec
  }

  private func runTestForName(_ name: String) {
    guard let spec = specsForName(name) else { return }
    runTest(spec, atBasePath: nil)
    // run again at a deeper location
    runTest(spec, atBasePath: "/foo/bar/baz")
  }

  func testAll() {
    let specs = loadSpecs()
    for spec in specs {
      runTest(spec, atBasePath: nil)
      // run again at a deeper location
      runTest(spec, atBasePath: "/foo/bar/baz")
    }
  }

  // purgeOutstandingWrites removes all writes from the sync tree. The connection can still
  // deliver acks for them afterwards: it defers acks that arrive while listens are outstanding,
  // and delivers them when the writes are purged.
  // https://github.com/firebase/firebase-ios-sdk/issues/5161
  func testAckForWriteRemovedByRemoveAllWritesIsIgnored() {
    let listenProvider = FListenProvider(startListening: { _, _, _, _ in [] },
                                         stopListening: { _, _ in })
    let syncTree = FSyncTree(listenProvider: listenProvider)
    let path = FPath(with: "a")
    _ = syncTree.applyUserOverwriteAtPath(path, newData: NODE("purged"), writeId: 0,
                                          isVisible: true)
    _ = syncTree.removeAllWrites()
    _ = syncTree.applyUserOverwriteAtPath(path, newData: NODE("pending"), writeId: 1,
                                          isVisible: true)

    let events = syncTree.ackUserWriteWithWriteId(0, revert: false, persist: true,
                                                  clock: FTestClock())
    XCTAssertEqual(events.count, 0)
    XCTAssertEqual(syncTree.calcCompleteEventCacheAtPath(path, excludeWriteIds: []),
                   NODE("pending"))

    // The write that is still pending is acked as usual.
    _ = syncTree.ackUserWriteWithWriteId(1, revert: true, persist: true, clock: FTestClock())
    XCTAssertEqual(syncTree.calcCompleteEventCacheAtPath(path, excludeWriteIds: []), FNode.empty)
  }

  func testDefaultListenHandlesParentSet() {
    runTestForName("Default listen handles a parent set")
  }

  func testDefaultListenHandlesASetAtTheSameLevel() {
    runTestForName("Default listen handles a set at the same level")
  }

  func testAQueryCanGetACompleteCacheThenAMerge() {
    runTestForName("A query can get a complete cache then a merge")
  }

  func testServerMergeOnListenerWithCompleteChildren() {
    runTestForName("Server merge on listener with complete children")
  }

  func testDeepMergeOnListenerWithCompleteChildren() {
    runTestForName("Deep merge on listener with complete children")
  }

  func testUpdateChildListenerTwice() {
    runTestForName("Update child listener twice")
  }

  func testChildOfDefaultListenThatAlreadyHasACompleteCache() {
    runTestForName("Update child of default listen that already has a complete cache")
  }

  func testUpdateChildOfDefaultListenThatHasNoCache() {
    runTestForName("Update child of default listen that has no cache")
  }

  // failing
  func testUpdateTheChildOfACoLocatedDefaultListenerAndQuery() {
    runTestForName("Update (via set) the child of a co-located default listener and query")
  }

  func testUpdateTheChildOfAQueryWithAFullCache() {
    runTestForName("Update (via set) the child of a query with a full cache")
  }

  func testUpdateAChildBelowAnEmptyQuery() {
    runTestForName("Update (via set) a child below an empty query")
  }

  func testUpdateDescendantOfDefaultListenerWithFullCache() {
    runTestForName("Update descendant of default listener with full cache")
  }

  func testDescendantSetBelowAnEmptyDefaultListenerIsIgnored() {
    runTestForName("Descendant set below an empty default listener is ignored")
  }

  func testUpdateOfAChild() {
    runTestForName("Update of a child. This can happen if a child listener is added and removed")
  }

  func testRevertSetWithOnlyChildCaches() {
    runTestForName("Revert set with only child caches")
  }

  func testCanRevertADuplicateChildSet() {
    runTestForName("Can revert a duplicate child set")
  }

  func testCanRevertAChildSetAndSeeTheUnderlyingData() {
    runTestForName("Can revert a child set and see the underlying data")
  }

  func testRevertChildSetWithNoServerData() {
    runTestForName("Revert child set with no server data")
  }

  func testRevertDeepSetWithNoServerData() {
    runTestForName("Revert deep set with no server data")
  }

  func testRevertSetCoveredByNonvisibleTransaction() {
    runTestForName("Revert set covered by non-visible transaction")
  }

  func testClearParentShadowingServerValuesSetWithServerChildren() {
    runTestForName("Clear parent shadowing server values set with server children")
  }

  func testClearChildShadowingServerValuesSetWithServerChildren() {
    runTestForName("Clear child shadowing server values set with server children")
  }

  func testUnrelatedMergeDoesntShadowServerUpdates() {
    runTestForName("Unrelated merge doesn't shadow server updates")
  }

  func testCanSetAlongsideARemoteMerge() {
    runTestForName("Can set alongside a remote merge")
  }

  func testSetPriorityOnALocationWithNoCache() {
    runTestForName("setPriority on a location with no cache")
  }

  func testDeepUpdateDeletesChildFromLimitWindowAndPullsInNewChild() {
    runTestForName("deep update deletes child from limit window and pulls in new child")
  }

  func testDeepSetDeletesChildFromLimitWindowAndPullsInNewChild() {
    runTestForName("deep set deletes child from limit window and pulls in new child")
  }

  func testEdgeCaseInNewChildForChange() {
    runTestForName("Edge case in newChildForChange_")
  }

  func testRevertSetInQueryWindow() {
    runTestForName("Revert set in query window")
  }

  func testHandlesAServerValueMovingAChildOutOfAQueryWindow() {
    runTestForName("Handles a server value moving a child out of a query window")
  }

  func testUpdateOfIndexedChildWorks() {
    runTestForName("Update of indexed child works")
  }

  func testMergeAppliedToEmptyLimit() {
    runTestForName("Merge applied to empty limit")
  }

  func testLimitIsRefilledFromServerDataAfterMerge() {
    runTestForName("Limit is refilled from server data after merge")
  }

  func testHandleRepeatedListenWithMergeAsFirstUpdate() {
    runTestForName("Handle repeated listen with merge as first update")
  }

  func testLimitIsRefilledFromServerDataAfterSet() {
    runTestForName("Limit is refilled from server data after set")
  }

  func testQueryOnWeirdPath() {
    runTestForName("query on weird path.")
  }

  func testRunsRound2() {
    runTestForName("runs, round2")
  }

  func testHandlesNestedListens() {
    runTestForName("handles nested listens")
  }

  func testHandlesASetBelowAListen() {
    runTestForName("Handles a set below a listen")
  }

  func testDoesNonDefaultQueries() {
    runTestForName("does non-default queries")
  }

  func testHandlesCoLocatedDefaultListenerAndQuery() {
    runTestForName("handles a co-located default listener and query")
  }

  func testDefaultAndNonDefaultListenerAtSameLocationWithServerUpdate() {
    runTestForName("Default and non-default listener at same location with server update")
  }

  func testAddAParentListenerToACompleteChildListenerExpectChildEvent() {
    runTestForName("Add a parent listener to a complete child listener, expect child event")
  }

  func testAddListensToASetExpectCorrectEventsIncludingAChildEvent() {
    runTestForName("Add listens to a set, expect correct events, including a child event")
  }

  func testServerUpdateToAChildListenerRaisesChildEventsAtParent() {
    runTestForName("ServerUpdate to a child listener raises child events at parent")
  }

  func testServerUpdateToAChildListenerRaisesChildEventsAtParentQuery() {
    runTestForName("ServerUpdate to a child listener raises child events at parent query")
  }

  func testMultipleCompleteChildrenAreHandleProperly() {
    runTestForName("Multiple complete children are handled properly")
  }

  func testWriteLeafNodeOverwriteAtParentNode() {
    runTestForName("Write leaf node, overwrite at parent node")
  }

  func testConfirmCompleteChildrenFromTheServer() {
    runTestForName("Confirm complete children from the server")
  }

  func testWriteLeafOverwriteFromParent() {
    runTestForName("Write leaf, overwrite from parent")
  }

  func testBasicUpdateTest() {
    runTestForName("Basic update test")
  }

  func testNoDoubleValueEventsForUserAck() {
    runTestForName("No double value events for user ack")
  }

  func testBasicKeyIndexSanityCheck() {
    runTestForName("Basic key index sanity check")
  }

  func testCollectCorrectSubviewsToListenOn() {
    runTestForName("Collect correct subviews to listen on")
  }

  func testLimitToFirstOneOnOrderedQuery() {
    runTestForName("Limit to first one on ordered query")
  }

  func testLimitToLastOneOnOrderedQuery() {
    runTestForName("Limit to last one on ordered query")
  }

  func testUpdateIndexedValueOnExistingChildFromLimitedQuery() {
    runTestForName("Update indexed value on existing child from limited query")
  }

  func testCanCreateStartAtEndAtEqualToQueriesWithBool() {
    runTestForName("Can create startAt, endAt, equalTo queries with bool")
  }

  func testQueryWithExistingServerSnap() {
    runTestForName("Query with existing server snap")
  }

  func testServerDataIsNotPurgedForNonServerIndexedQueries() {
    runTestForName("Server data is not purged for non-server-indexed queries")
  }

  func testStartAtEndAtDominatesLimit() {
    runTestForName("startAt/endAt dominates limit")
  }

  func testUpdateToSingleChildThatMovesOutOfWindow() {
    runTestForName("Update to single child that moves out of window")
  }

  func testLimitedQueryDoesntPullInOutOfRangeChild() {
    runTestForName("Limited query doesn't pull in out of range child")
  }

  func testWithCustomOrderByIsRefilledWithCorrectItem() {
    runTestForName("Limit with custom orderBy is refilled with correct item")
  }

  func testMergeForLocationWithDefaultAndLimitedListener() {
    runTestForName("Merge for location with default and limited listener")
  }

  func testUserMergePullsInCorrectValues() {
    runTestForName("User merge pulls in correct values")
  }

  func testUserDeepSetPullsInCorrectValues() {
    runTestForName("User deep set pulls in correct values")
  }

  func testQueriesWithEqualToNullWork() {
    runTestForName("Queries with equalTo(null) work")
  }

  func testRevertedWritesUpdateQuery() {
    runTestForName("Reverted writes update query")
  }

  func testDeepSetForNonLocalDataDoesntRaiseEvents() {
    runTestForName("Deep set for non-local data doesn't raise events")
  }

  func testUserUpdateWithNewChildrenTriggersEvents() {
    runTestForName("User update with new children triggers events")
  }

  func testUserWriteWithDeepOverwrite() {
    runTestForName("User write with deep user overwrite")
  }

  func testServerUpdatesPriority() {
    runTestForName("Server updates priority")
  }

  func testRevertFullUnderlyingWrite() {
    runTestForName("Revert underlying full overwrite")
  }

  func testUserChildOverwriteForNonexistentServerNode() {
    runTestForName("User child overwrite for non-existent server node")
  }

  func testRevertUserOverwriteOfChildOnLeafNode() {
    runTestForName("Revert user overwrite of child on leaf node")
  }

  func testServerOverwriteWithDeepUserDelete() {
    runTestForName("Server overwrite with deep user delete")
  }

  func testUserOverwritesLeafNodeWithPriority() {
    runTestForName("User overwrites leaf node with priority")
  }

  func testUserOverwritesInheritPriorityValuesFromLeafNodes() {
    runTestForName("User overwrites inherit priority values from leaf nodes")
  }

  func testUserUpdateOnUserSetLeafNodeWithPriorityAfterServerUpdate() {
    runTestForName("User update on user set leaf node with priority after server update")
  }

  func testServerDeepDeleteOnLeafNode() {
    runTestForName("Server deep delete on leaf node")
  }

  func testUserSetsRootPriority() {
    runTestForName("User sets root priority")
  }

  func testUserUpdatesPriorityOnEmptyRoot() {
    runTestForName("User updates priority on empty root")
  }

  func testRevertSetAtRootWithPriority() {
    runTestForName("Revert set at root with priority")
  }

  func testServerUpdatesPriorityAfterUserSetsPriority() {
    runTestForName("Server updates priority after user sets priority")
  }

  func testEmptySetDoesntPreventServerUpdates() {
    runTestForName("Empty set doesn't prevent server updates")
  }

  func testUserUpdatesPriorityTwiceFirstIsReverted() {
    runTestForName("User updates priority twice, first is reverted")
  }

  func testServerAcksRootPrioritySetAfterUserDeletesRootNode() {
    runTestForName("Server acks root priority set after user deletes root node")
  }

  func testADeleteInAMergeDoesntPushOutNodes() {
    runTestForName("A delete in a merge doesn't push out nodes")
  }

  func testATaggedQueryFiresEventsEventually() {
    runTestForName("A tagged query fires events eventually")
  }

  func testUserWriteOutsideOfLimitIsIgnoredForTaggedQueries() {
    runTestForName("User write outside of limit is ignored for tagged queries")
  }

  func testAckForMergeDoesntRaiseValueEventForLaterListen() {
    runTestForName("Ack for merge doesn't raise value event for later listen")
  }

  func testClearParentShadowingServerValuesMergeWithServerChildren() {
    runTestForName("Clear parent shadowing server values merge with server children")
  }

  func testPrioritiesDontMakeMeSick() {
    runTestForName("Priorities don't make me sick")
  }

  func testMergeThatMovesChildFromWindowToBoundaryDoesNotCauseChildToBeReadded() {
    runTestForName("Merge that moves child from window to boundary does not cause child to be readded")
  }

  func testDeepMergeAckIsHandledCorrectly() {
    runTestForName("Deep merge ack is handled correctly.")
  }

  func testDeepMergeAckOnIncompleteDataAndWithServerValues() {
    runTestForName("Deep merge ack (on incomplete data, and with server values)")
  }

  func testLimitQueryHandlesDeepServerMergeForOutOfViewItem() {
    runTestForName("Limit query handles deep server merge for out-of-view item.")
  }

  func testLimitQueryHandlesDeepUserMergeForOutOfViewItem() {
    runTestForName("Limit query handles deep user merge for out-of-view item.")
  }

  func testLimitQueryHandlesDeepUserMergeForOutOfViewItemFollowedByServerUpdate() {
    runTestForName("Limit query handles deep user merge for out-of-view item followed by server update.")
  }

  func testUnrelatedUntaggedUpdateIsNotCachedInTaggedListen() {
    runTestForName("Unrelated, untagged update is not cached in tagged listen")
  }

  func testUnrelatedAckedSetIsNotCachedInTaggedListen() {
    runTestForName("Unrelated, acked set is not cached in tagged listen")
  }

  func testUnrelatedAckedUpdateIsNotCachedInTaggedListen() {
    runTestForName("Unrelated, acked update is not cached in tagged listen")
  }

  func testdeepUpdateRaisesImmediateEventsOnlyIfHasCompleteData() {
    runTestForName("Deep update raises immediate events only if has complete data")
  }

  func testdeepUpdateReturnsMinimumDataRequired() {
    runTestForName("Deep update returns minimum data required")
  }

  func testdeepUpdateRaisesAllEvents() {
    runTestForName("Deep update raises all events")
  }

}
