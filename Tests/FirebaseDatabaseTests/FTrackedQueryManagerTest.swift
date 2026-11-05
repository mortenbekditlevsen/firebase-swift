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

// Port of upstream's FirebaseDatabase/Tests/Unit/FTrackedQueryManagerTest.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

// Upstream's SAMPLE_PARAMS, SAMPLE_QUERY, DEFAULT_FOO_QUERY and
// DEFAULT_BAR_QUERY macros.
let SAMPLE_PARAMS = FQueryParams.defaultInstance.orderBy(.path(PATH("child")))
  .startAt(NODE("startVal"), childKey: "startKey")
  .endAt(NODE("endVal"), childKey: "endKey")
  .limitToLast(5)
let SAMPLE_QUERY = FQuerySpec(path: PATH("foo"), params: SAMPLE_PARAMS)
let DEFAULT_FOO_QUERY = FQuerySpec(path: PATH("foo"), params: .defaultInstance)
let DEFAULT_BAR_QUERY = FQuerySpec(path: PATH("bar"), params: .defaultInstance)

class FTrackedQueryManagerTest: XCTestCase {
  private func newManager() -> FTrackedQueryManager {
    newManager(clock: FSystemClock.clock)
  }

  private func newManager(clock: FClock) -> FTrackedQueryManager {
    FTrackedQueryManager(storageEngine: FMockStorageEngine(), clock: clock)
  }

  private func newManager(storageEngine: FStorageEngine) -> FTrackedQueryManager {
    FTrackedQueryManager(storageEngine: storageEngine, clock: FSystemClock.clock)
  }

  private func defaultQuery(_ path: String) -> FQuerySpec {
    FQuerySpec.defaultQueryAtPath(PATH(path))
  }

  private func sampleQuery(_ path: String) -> FQuerySpec {
    FQuerySpec(path: PATH(path), params: SAMPLE_PARAMS)
  }

  func testFindTrackedQuery() {
    let manager = newManager()
    XCTAssertNil(manager.findTrackedQuery(SAMPLE_QUERY))
    manager.setQueryActive(SAMPLE_QUERY)
    XCTAssertNotNil(manager.findTrackedQuery(SAMPLE_QUERY))
  }

  func testRemoveTrackedQuery() {
    let manager = newManager()
    manager.setQueryActive(SAMPLE_QUERY)
    XCTAssertNotNil(manager.findTrackedQuery(SAMPLE_QUERY))
    manager.removeTrackedQuery(SAMPLE_QUERY)
    XCTAssertNil(manager.findTrackedQuery(SAMPLE_QUERY))
    manager.verifyCache()
  }

  func testSetQueryActiveAndInactive() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.setQueryActive(SAMPLE_QUERY)
    var q = manager.findTrackedQuery(SAMPLE_QUERY)
    XCTAssertTrue(q?.isActive ?? false)
    XCTAssertEqual(q?.lastUse, clock.currentTime)
    manager.verifyCache()

    clock.tick()
    manager.setQueryInactive(SAMPLE_QUERY)
    q = manager.findTrackedQuery(SAMPLE_QUERY)
    XCTAssertFalse(q?.isActive ?? true)
    XCTAssertEqual(q?.lastUse, clock.currentTime)
    manager.verifyCache()
  }

  func testSetQueryComplete() {
    let manager = newManager()
    manager.setQueryActive(SAMPLE_QUERY)
    manager.setQueryComplete(SAMPLE_QUERY)
    XCTAssertTrue(manager.findTrackedQuery(SAMPLE_QUERY)?.isComplete ?? false)
    manager.verifyCache()
  }

  func testSetQueriesComplete() {
    let manager = newManager()
    manager.setQueryActive(defaultQuery("foo"))
    manager.setQueryActive(defaultQuery("foo/bar"))
    manager.setQueryActive(defaultQuery("elsewhere"))
    manager.setQueryActive(sampleQuery("foo"))
    manager.setQueryActive(sampleQuery("foo/baz"))
    manager.setQueryActive(sampleQuery("elsewhere"))

    manager.setQueriesCompleteAtPath(PATH("foo"))

    XCTAssertTrue(manager.findTrackedQuery(defaultQuery("foo"))?.isComplete ?? false)
    XCTAssertTrue(manager.findTrackedQuery(defaultQuery("foo/bar"))?.isComplete ?? false)
    XCTAssertTrue(manager.findTrackedQuery(sampleQuery("foo"))?.isComplete ?? false)
    XCTAssertTrue(manager.findTrackedQuery(sampleQuery("foo/baz"))?.isComplete ?? false)
    XCTAssertFalse(manager.findTrackedQuery(defaultQuery("elsewhere"))?.isComplete ?? true)
    XCTAssertFalse(manager.findTrackedQuery(sampleQuery("elsewhere"))?.isComplete ?? true)
    manager.verifyCache()
  }

  func testIsQueryComplete() {
    let manager = newManager()

    manager.setQueryActive(SAMPLE_QUERY)
    manager.setQueryComplete(SAMPLE_QUERY)

    manager.setQueryActive(DEFAULT_BAR_QUERY)

    manager.setQueryActive(defaultQuery("baz"))
    manager.setQueryComplete(defaultQuery("baz"))

    XCTAssertTrue(manager.isQueryComplete(SAMPLE_QUERY))
    XCTAssertFalse(manager.isQueryComplete(DEFAULT_BAR_QUERY))

    XCTAssertFalse(manager.isQueryComplete(defaultQuery("")))
    XCTAssertTrue(manager.isQueryComplete(defaultQuery("baz")))
    XCTAssertTrue(manager.isQueryComplete(defaultQuery("baz/quu")))
  }

  func testPruneOldQueries() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.setQueryActive(defaultQuery("active1"))
    manager.setQueryActive(defaultQuery("active2"))
    manager.setQueryActive(defaultQuery("pinned1"))
    manager.setQueryActive(defaultQuery("pinned2"))
    manager.setQueryActive(defaultQuery("inactive1"))
    manager.setQueryInactive(defaultQuery("inactive1"))
    clock.tick()
    manager.setQueryActive(defaultQuery("inactive2"))
    manager.setQueryInactive(defaultQuery("inactive2"))
    clock.tick()
    manager.setQueryActive(defaultQuery("inactive3"))
    manager.setQueryInactive(defaultQuery("inactive3"))
    clock.tick()
    manager.setQueryActive(defaultQuery("inactive4"))
    manager.setQueryInactive(defaultQuery("inactive4"))
    clock.tick()

    // Should remove the first two inactive queries
    var forest = manager.pruneOldQueries(FTestCachePolicy(percent: 0.5, maxQueries: Int.max))
    checkPruneForest(forest,
                     pathsToKeep: ["active1", "active2", "pinned1", "pinned2", "inactive3",
                                   "inactive4"],
                     pathsToPrune: ["inactive1", "inactive2"])

    // Should remove the other two inactive queries
    forest = manager.pruneOldQueries(FTestCachePolicy(percent: 1, maxQueries: Int.max))
    checkPruneForest(forest,
                     pathsToKeep: ["active1", "active2", "pinned1", "pinned2"],
                     pathsToPrune: ["inactive3", "inactive4"])

    // Nothing left to prune
    forest = manager.pruneOldQueries(FTestCachePolicy(percent: 1, maxQueries: Int.max))
    XCTAssertFalse(forest.prunesAnything())

    manager.verifyCache()
  }

  func testPruneQueriesOverMaxSize() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    for i in 0 ..< 10 {
      manager.setQueryActive(defaultQuery("\(i)"))
      manager.setQueryInactive(defaultQuery("\(i)"))
      clock.tick()
    }

    let forest = manager.pruneOldQueries(FTestCachePolicy(percent: 0.2, maxQueries: 6))
    checkPruneForest(forest, pathsToKeep: ["4", "5", "6", "7", "8", "9"],
                     pathsToPrune: ["0", "1", "2", "3"])
  }

  func testPruneDefaultWithDeeperQueries() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.setQueryActive(defaultQuery("foo"))
    manager.setQueryActive(sampleQuery("foo/a"))
    manager.setQueryActive(sampleQuery("foo/b"))
    manager.setQueryInactive(defaultQuery("foo"))

    let forest = manager.pruneOldQueries(FTestCachePolicy(percent: 1.0, maxQueries: Int.max))
    checkPruneForest(forest, pathsToKeep: ["foo/a", "foo/b"], pathsToPrune: ["foo"])
    manager.verifyCache()
  }

  func testPruneQueriesWithDefaultQueryOnParent() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.setQueryActive(defaultQuery("foo"))
    manager.setQueryActive(sampleQuery("foo/a"))
    manager.setQueryActive(sampleQuery("foo/b"))
    manager.setQueryInactive(sampleQuery("foo/a"))
    manager.setQueryInactive(sampleQuery("foo/b"))

    let forest = manager.pruneOldQueries(FTestCachePolicy(percent: 1.0, maxQueries: Int.max))
    checkPruneForest(forest, pathsToKeep: ["foo"], pathsToPrune: [])
    manager.verifyCache()
  }

  func testPruneQueriesOverMaxSizeUsingPercent() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    for i in 0 ..< 10 {
      manager.setQueryActive(defaultQuery("\(i)"))
      manager.setQueryInactive(defaultQuery("\(i)"))
      clock.tick()
    }

    let forest = manager.pruneOldQueries(FTestCachePolicy(percent: 0.6, maxQueries: 6))
    checkPruneForest(forest, pathsToKeep: ["6", "7", "8", "9"],
                     pathsToPrune: ["0", "1", "2", "3", "4", "5"])
  }

  private func checkPruneForest(_ pruneForest: FPruneForest, pathsToKeep toKeep: [String],
                                pathsToPrune toPrune: [String],
                                file: StaticString = #filePath, line: UInt = #line) {
    var checkForest = FPruneForest.empty()
    for path in toPrune {
      checkForest = checkForest.prunePath(PATH(path))
    }
    for path in toKeep {
      checkForest = checkForest.keepPath(PATH(path))
    }
    XCTAssertEqual(pruneForest.pruneForest, checkForest.pruneForest, file: file, line: line)
  }

  func testKnownCompleteChildren() {
    let engine = FMockStorageEngine()
    let manager = newManager(storageEngine: engine)

    XCTAssertEqual(manager.knownCompleteChildrenAtPath(PATH("foo")), [])

    manager.setQueryActive(defaultQuery("foo/a"))
    manager.setQueryComplete(defaultQuery("foo/a"))
    manager.setQueryActive(defaultQuery("foo/not-included"))
    manager.setQueryActive(defaultQuery("foo/deep/not-included"))

    manager.setQueryActive(SAMPLE_QUERY)
    let query = manager.findTrackedQuery(SAMPLE_QUERY)!
    engine.setTrackedQueryKeys(["d", "e"], forQueryId: query.queryId)

    XCTAssertEqual(manager.knownCompleteChildrenAtPath(PATH("foo")), ["a", "d", "e"])
    XCTAssertEqual(manager.knownCompleteChildrenAtPath(PATH("")), [])
    XCTAssertEqual(manager.knownCompleteChildrenAtPath(PATH("foo/baz")), [])
  }

  func testEnsureTrackedQueryForNewQuery() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.ensureCompleteTrackedQueryAtPath(PATH("foo"))
    let query = manager.findTrackedQuery(DEFAULT_FOO_QUERY)
    XCTAssertTrue(query?.isComplete ?? false)
    XCTAssertEqual(query?.lastUse, clock.currentTime)
  }

  func testEnsureTrackedQueryForAlreadyTrackedQuery() {
    let clock = FTestClock()
    let manager = newManager(clock: clock)

    manager.setQueryActive(DEFAULT_FOO_QUERY)

    let lastTick = clock.currentTime
    clock.tick()

    manager.ensureCompleteTrackedQueryAtPath(PATH("foo"))
    XCTAssertEqual(manager.findTrackedQuery(DEFAULT_FOO_QUERY)?.lastUse, lastTick)
  }

  func testHasActiveDefaultQuery() {
    let manager = newManager()

    manager.setQueryActive(SAMPLE_QUERY)
    manager.setQueryActive(DEFAULT_BAR_QUERY)
    XCTAssertFalse(manager.hasActiveDefaultQueryAtPath(PATH("foo")))
    XCTAssertFalse(manager.hasActiveDefaultQueryAtPath(PATH("")))
    XCTAssertTrue(manager.hasActiveDefaultQueryAtPath(PATH("bar")))
    XCTAssertTrue(manager.hasActiveDefaultQueryAtPath(PATH("bar/baz")))
  }

  func testCacheSanity() {
    let engine = FMockStorageEngine()
    let manager = newManager(storageEngine: engine)

    manager.setQueryActive(SAMPLE_QUERY)
    manager.setQueryActive(DEFAULT_FOO_QUERY)
    manager.verifyCache()

    manager.setQueryComplete(SAMPLE_QUERY)
    manager.verifyCache()

    manager.setQueryInactive(DEFAULT_FOO_QUERY)
    manager.verifyCache()

    let manager2 = newManager(storageEngine: engine)
    XCTAssertNotNil(manager2.findTrackedQuery(SAMPLE_QUERY))
    XCTAssertNotNil(manager2.findTrackedQuery(DEFAULT_FOO_QUERY))
    manager2.verifyCache()
  }
}
