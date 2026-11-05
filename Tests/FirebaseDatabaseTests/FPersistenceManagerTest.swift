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

// Port of upstream's FirebaseDatabase/Tests/Unit/FPersistenceManagerTest.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

class FPersistenceManagerTest: XCTestCase {
  private func newTestPersistenceManager() -> FPersistenceManager {
    let engine = FMockStorageEngine()
    return FPersistenceManager(storageEngine: engine, cachePolicy: FNoCachePolicy.noCachePolicy)
  }

  func testServerCacheFiltersResults1() {
    let manager = newTestPersistenceManager()

    manager.updateServerCache(node: NODE("1"),
                              forQuery: FQuerySpec.defaultQueryAtPath(PATH("foo/bar")))
    manager.updateServerCache(node: NODE("2"),
                              forQuery: FQuerySpec.defaultQueryAtPath(PATH("foo/baz")))
    manager.updateServerCache(node: NODE("3"),
                              forQuery: FQuerySpec.defaultQueryAtPath(PATH("foo/quu/1")))
    manager.updateServerCache(node: NODE("4"),
                              forQuery: FQuerySpec.defaultQueryAtPath(PATH("foo/quu/2")))

    let cache = manager.serverCacheForQuery(FQuerySpec.defaultQueryAtPath(PATH("foo")))
    XCTAssertFalse(cache.isFullyInitialized)
    XCTAssertEqual(cache.node, FNode.empty)
  }

  func testServerCacheFiltersResults2() {
    let manager = newTestPersistenceManager()

    let limit2FooQuery = FQuerySpec(path: PATH("foo"),
                                    params: FQueryParams.defaultInstance.limitToFirst(2))
    let limit3FooQuery = FQuerySpec(path: PATH("foo"),
                                    params: FQueryParams.defaultInstance.limitToFirst(3))

    manager.setQueryActive(limit2FooQuery)
    manager.updateServerCache(node: NODE(["a": 1, "b": 2, "c": 3, "d": 4]),
                              forQuery: limit2FooQuery)
    manager.setTrackedQueryKeys(["a", "b"], forQuery: limit2FooQuery)

    let cache = manager.serverCacheForQuery(limit3FooQuery)
    XCTAssertFalse(cache.isFullyInitialized)
    XCTAssertEqual(cache.node, NODE(["a": 1, "b": 2]))
  }

  func testNoLimitNonDefaultQueryIsTreatedAsDefaultQuery() {
    let manager = newTestPersistenceManager()

    let defaultQuery = FQuerySpec.defaultQueryAtPath(PATH("foo"))
    let index = FIndex.path(PATH("index-key"))
    let orderByQuery = FQuerySpec(path: PATH("foo"),
                                  params: FQueryParams.defaultInstance.orderBy(index))
    manager.setQueryActive(defaultQuery)
    manager.updateServerCache(node: NODE(["foo": 1, "bar": 2]), forQuery: defaultQuery)
    manager.setQueryComplete(defaultQuery)

    let node = manager.serverCacheForQuery(orderByQuery)

    XCTAssertEqual(node.node, NODE(["foo": 1, "bar": 2]))
    XCTAssertTrue(node.isFullyInitialized)
    XCTAssertFalse(node.isFiltered)
    XCTAssertTrue(node.indexedNode.hasIndex(orderByQuery.index))
  }

  func testApplyUserMergeUsesRelativePath() {
    let engine = FMockStorageEngine()

    let initialData = NODE(["foo": ["bar": "bar-value", "baz": "baz-value"]])
    engine.updateServerCache(initialData, atPath: PATH(""), merge: false)

    let manager = FPersistenceManager(storageEngine: engine,
                                      cachePolicy: FNoCachePolicy.noCachePolicy)

    let update = FCompoundWrite.compoundWrite(valueDictionary: ["baz": "new-baz", "qux": "qux"])
    manager.applyUserMerge(update, toServerCacheAtPath: PATH("foo"))

    let expected = NODE(["foo": ["bar": "bar-value", "baz": "new-baz", "qux": "qux"]])
    let actual = engine.serverCache(atPath: PATH(""))
    XCTAssertEqual(actual, expected)
  }
}
