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

// Port of upstream's FirebaseDatabase/Tests/Unit/FRangeMergeTest.m (13.1.1).

import XCTest

@testable import FirebaseDatabase

class FRangeMergeTest: XCTestCase {

  func testSmokeTest() {
    let node = NODE([
      "bar": "bar-value",
      "foo": ["a": ["deep-a-1": 1, "deep-a-2": 2] as [String: Any], "b": "b", "c": "c", "d": "d"]
        as [String: Any],
      "quu": "quu-value",
    ])

    let updates = NODE([
      "foo":
        [
          "a": ["deep-a-2": "new-a-2", "deep-a-3": 3] as [String: Any], "b-2": "new-b",
          "c": "new-c",
        ] as [String: Any]
    ])

    let merge = FRangeMerge(start: PATH("foo/a/deep-a-1"), end: PATH("foo/c"), updates: updates)

    let expected = NODE([
      "bar": "bar-value",
      "foo": [
        "a": ["deep-a-1": 1, "deep-a-2": "new-a-2", "deep-a-3": 3] as [String: Any],
        "b-2": "new-b",
        "c": "new-c",
        "d": "d",
      ] as [String: Any],
      "quu": "quu-value",
    ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testStartIsExclusive() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value", "quu": "quu-value"])

    let updates = NODE(["foo": "new-foo-value"])

    let merge = FRangeMerge(start: PATH("bar"), end: PATH("foo"), updates: updates)

    let expected =
      NODE(["bar": "bar-value", "foo": "new-foo-value", "quu": "quu-value"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testStartIsExclusiveButIncludesChildren() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value", "quu": "quu-value"])

    let updates =
      NODE(["bar": ["bar-child": "bar-child-value"] as [String: Any], "foo": "new-foo-value"])

    let merge = FRangeMerge(start: PATH("bar"), end: PATH("foo"), updates: updates)

    let expected = NODE([
      "bar": ["bar-child": "bar-child-value"] as [String: Any],
      "foo": "new-foo-value",
      "quu": "quu-value",
    ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testEndIsInclusive() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value", "quu": "quu-value"])

    let updates = NODE(["baz": "baz-value"])

    let merge = FRangeMerge(start: PATH("bar"), end: PATH("foo"), updates: updates)  // foo should be deleted

    let expected =
      NODE(["bar": "bar-value", "baz": "baz-value", "quu": "quu-value"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testEndIsInclusiveButExcludesChildren() {
    let node = NODE([
      "bar": "bar-value",
      "foo": ["foo-child": "foo-child-value"] as [String: Any],
      "quu": "quu-value",
    ])

    let updates = NODE(["baz": "baz-value"])

    let merge = FRangeMerge(start: PATH("bar"), end: PATH("foo"), updates: updates)  // foo should be deleted

    let expected = NODE([
      "bar": "bar-value",
      "baz": "baz-value",
      "foo": ["foo-child": "foo-child-value"] as [String: Any],
      "quu": "quu-value",
    ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testCanUpdateLeafNode() {
    let node = NODE("leaf-value")

    let updates = NODE(["bar": "bar-value"])

    let merge = FRangeMerge(start: nil, end: PATH("foo"), updates: updates)
    let expected = NODE(["bar": "bar-value"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testCanReplaceLeafNodeWithLeafNode() {
    let node = NODE("leaf-value")

    let updates = NODE("new-leaf-value")

    let merge = FRangeMerge(start: nil, end: PATH(""), updates: updates)
    let expected = NODE("new-leaf-value")
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testLeavesAreUpdatedWhenRangesIncludeDeeperPath() {
    let node = NODE(["foo": ["bar": "bar-value"] as [String: Any]])

    let updates = NODE(["foo": ["bar": "new-bar-value"] as [String: Any]])

    let merge = FRangeMerge(start: PATH("foo"), end: PATH("foo/bar/deep"), updates: updates)

    let expected = NODE(["foo": ["bar": "new-bar-value"] as [String: Any]])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testLeavesAreNotUpdatedWhenRangesIncludeDeeperPaths() {
    let node = NODE(["foo": ["bar": "bar-value"] as [String: Any]])

    let updates = NODE(["foo": ["bar": "new-bar-value"] as [String: Any]])

    let merge = FRangeMerge(start: PATH("foo/bar"), end: PATH("foo/bar/deep"), updates: updates)

    let expected = NODE(["foo": ["bar": "bar-value"] as [String: Any]])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingEntireRangeUpdatesEverything() {
    let node = FNode.empty

    let updates = NODE(["foo": "foo-value", "bar": ["child": "bar-child-value"] as [String: Any]])

    let merge = FRangeMerge(start: nil, end: nil, updates: updates)

    let expected = NODE(["foo": "foo-value", "bar": ["child": "bar-child-value"] as [String: Any]])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingRangeWithUnboundedLeftPostWorks() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value"])

    let updates = NODE(["bar": "new-bar"])

    let merge = FRangeMerge(start: nil, end: PATH("bar"), updates: updates)

    let expected = NODE(["bar": "new-bar", "foo": "foo-value"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingRangeWithRightPostChildOfLeftPostWorks() {
    let node =
      NODE([
        "foo": ["a": "a", "b": ["1": "1", "2": "2"] as [String: Any], "c": "c"] as [String: Any]
      ])

    let updates = NODE([
      "foo": ["a": "new-a", "b": ["1": "new-1"] as [String: Any]] as [String: Any]
    ])

    let merge = FRangeMerge(start: PATH("foo"), end: PATH("foo/b/1"), updates: updates)

    let expected =
      NODE([
        "foo": ["a": "new-a", "b": ["1": "new-1", "2": "2"] as [String: Any], "c": "c"]
          as [String: Any]
      ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingRangeWithRightPostChildOfLeftPostWorksWithIntegerKeys() {
    let node = NODE(
      ([
        "foo": ["a": "a", "b": ["1": "1", "2": "2", "10": "10"] as [String: Any], "c": "c"]
          as [String: Any]
      ]))

    let updates = NODE([
      "foo": ["a": "new-a", "b": ["1": "new-1"] as [String: Any]] as [String: Any]
    ])

    let merge = FRangeMerge(start: PATH("foo"), end: PATH("foo/b/2"), updates: updates)

    let expected =
      NODE([
        "foo": ["a": "new-a", "b": ["1": "new-1", "10": "10"] as [String: Any], "c": "c"]
          as [String: Any]
      ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingLeafIncludesPriority() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value", "quu": "quu-value"])

    let updates = NODE(["foo": [".value": "new-foo", ".priority": "prio"] as [String: Any]])

    let merge = FRangeMerge(start: PATH("bar"), end: PATH("foo"), updates: updates)

    let expected = NODE([
      "bar": "bar-value",
      "foo": [".value": "new-foo", ".priority": "prio"] as [String: Any],
      "quu": "quu-value",
    ])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingPriorityInChildrenNodeWorks() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value"])

    let updates = NODE(["bar": "new-bar", ".priority": "prio"])

    let merge = FRangeMerge(start: nil, end: PATH("bar"), updates: updates)

    let expected =
      NODE(["bar": "new-bar", "foo": "foo-value", ".priority": "prio"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  // TODO: this test should actuall;y work, but priorities on empty nodes are ignored :(
  func updatingPriorityInChildrenNodeWorksAlone() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value"])

    let updates = NODE([".priority": "prio"])

    let merge = FRangeMerge(start: nil, end: PATH(".priority"), updates: updates)

    let expected =
      NODE(["bar": "bar-value", "foo": "foo-value", ".priority": "prio"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testUpdatingPriorityOnInitiallyEmptyNodeDoesNotBreak() {
    let node = NODE([:] as [String: Any])

    let updates = NODE([".priority": "prio", "foo": "foo-value"])

    let merge = FRangeMerge(start: nil, end: PATH("foo"), updates: updates)

    let expected = NODE(["foo": "foo-value", ".priority": "prio"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testPriorityIsDeletedWhenIncludedInChildrenRange() {
    let node = NODE(["bar": "bar-value", "foo": "foo-value", ".priority": "prio"])

    let updates = NODE(["bar": "new-bar"])

    let merge = FRangeMerge(start: nil, end: PATH("bar"), updates: updates)  // deletes priority

    let expected = NODE(["bar": "new-bar", "foo": "foo-value"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testPriorityIsIncludedInOpenStart() {
    let node = NODE(["foo": ["bar": "bar-value"] as [String: Any]])

    let updates = NODE([".priority": "prio", "baz": "baz"])

    let merge = FRangeMerge(start: nil, end: PATH("foo/bar"), updates: updates)

    let expected = NODE(["baz": "baz", ".priority": "prio"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }

  func testPriorityIsIncludedInOpenEnd() {
    let node = NODE("leaf-node")

    let updates = NODE([".priority": "prio", "foo": "bar"])

    let merge = FRangeMerge(start: PATH("/"), end: nil, updates: updates)

    let expected = NODE(["foo": "bar", ".priority": "prio"])
    let actual = merge.applyToNode(node)
    XCTAssertEqual(actual, expected)
  }
}
