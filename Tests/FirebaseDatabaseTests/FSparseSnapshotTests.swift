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

// Port of upstream's FirebaseDatabase/Tests/Unit/FSparseSnapshotTests.m (13.1.1).
// Port note: FSparseSnapshotTree is a value type, so the tree is a `var`.

@testable import FirebaseDatabase
import XCTest

class FSparseSnapshotTests: XCTestCase {
  func testBasicRememberAndFind() {
    var st = FSparseSnapshotTree()
    let path = PATH("a/b")
    let node = NODE("sdfsd")
    st.rememberData(node, onPath: path)
    var found = st.findPath(path)
    XCTAssertFalse(found?.isEmpty ?? true, "Should find node")
    found = st.findPath(path.parent()!)
    XCTAssertNil(found, "Should not find a node")
  }

  func testFindInsideAnExistingSnapshot() {
    var st = FSparseSnapshotTree()
    let path = PATH("t/tt")
    var node = NODE(["a": "sdfsd", "x": 5, "999i": true])
    let update = NODE(["goats": 88])
    node = node.updateImmediateChild("apples", withNewChild: update)
    st.rememberData(node, onPath: path)

    var found = st.findPath(path)
    XCTAssertFalse(found?.isEmpty ?? true, "Should find the node we set")
    found = st.findPath(path.child(fromString: "a"))
    XCTAssertEqual(found?.val(), "sdfsd", "Find works inside data snapshot")
    found = st.findPath(path.child(fromString: "999i"))
    // Port note: through `as? Bool`, as on Linux a Boolean NSNumber doesn't
    // equal a Bool as AnyHashable.
    XCTAssertEqual(found?.val() as? Bool, true, "Find works inside data snapshot")
    found = st.findPath(path.child(fromString: "apples"))
    XCTAssertFalse(found?.isEmpty ?? true, "Should find the node we set")
    found = st.findPath(path.child(fromString: "apples/goats"))
    XCTAssertEqual(found?.val(), 88, "Find works inside data snapshot")
  }

  func testWriteASnapshotInsideASnapshot() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(["a": ["b": "v"]]), onPath: PATH("t"))
    st.rememberData(NODE(19), onPath: PATH("t/a/rr"))
    var found = st.findPath(PATH("t/a/b"))
    XCTAssertEqual(found?.val(), "v", "Find inside snap")
    found = st.findPath(PATH("t/a/rr"))
    XCTAssertEqual(found?.val(), 19, "Find inside snap")
  }

  func testWriteANullValueAndConfirmItIsRemembered() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(NSNull()), onPath: PATH("awq/fff"))
    var found = st.findPath(PATH("awq/fff"))
    XCTAssertTrue(found?.isEmpty ?? false, "Empty node")
    found = st.findPath(PATH("awq/sdf"))
    XCTAssertNil(found, "No node here")
    found = st.findPath(PATH("awq/fff/jjj"))
    XCTAssertTrue(found?.isEmpty ?? false, "Empty node")
    found = st.findPath(PATH("awq/sdf/sdj/q"))
    XCTAssertNil(found, "No node here")
  }

  func testOverwriteWithNullAndConfirmItIsRemembered() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(["a": ["b": "v"]]), onPath: PATH("t"))
    var found = st.findPath(PATH("t"))
    XCTAssertFalse(found?.isEmpty ?? true, "non-empty node")
    st.rememberData(NODE(NSNull()), onPath: PATH("t"))
    found = st.findPath(PATH("t"))
    XCTAssertTrue(found?.isEmpty ?? false, "Empty node")
  }

  func testSimpleRememberAndForget() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(["a": ["b": "v"]]), onPath: PATH("t"))
    var found = st.findPath(PATH("t"))
    XCTAssertFalse(found?.isEmpty ?? true, "non-empty node")
    _ = st.forgetPath(PATH("t"))
    found = st.findPath(PATH("t"))
    XCTAssertNil(found, "node is gone")
  }

  func testForgetTheRoot() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(["a": ["b": "v"]]), onPath: PATH("t"))
    var found = st.findPath(PATH("t"))
    XCTAssertFalse(found?.isEmpty ?? true, "non-empty node")
    found = st.findPath(PATH(""))
    XCTAssertNil(found, "node is gone")
  }

  func testForgetSnapshotInsideSnapshot() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(["a": ["b": "v", "c": 9, "art": false] as [String: Any]]),
                    onPath: PATH("t"))
    var found = st.findPath(PATH("t/a/c"))
    XCTAssertFalse(found?.isEmpty ?? true, "non-empty node")
    found = st.findPath(PATH("t"))
    XCTAssertFalse(found?.isEmpty ?? true, "non-empty node")

    _ = st.forgetPath(PATH("t/a/c"))
    XCTAssertNil(st.findPath(PATH("t")), "no more node here")
    XCTAssertNil(st.findPath(PATH("t/a")), "no more node here")
    XCTAssertEqual(st.findPath(PATH("t/a/b"))?.val(), "v", "child still exists")
    XCTAssertNil(st.findPath(PATH("t/a/c")), "no more node here")
    XCTAssertEqual(st.findPath(PATH("t/a/art"))?.val() as? Bool, false, "child still exists")
  }

  func testPathShallowerThanSnapshots() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE(false), onPath: PATH("t/x1"))
    st.rememberData(NODE(true), onPath: PATH("t/x2"))
    _ = st.forgetPath(PATH("t"))
    XCTAssertNil(st.findPath(PATH("t")), "No more node here")
  }

  func testIterateChildren() {
    var st = FSparseSnapshotTree()
    let node = NODE(["b": "v", "c": 9, "art": false])
    st.rememberData(node, onPath: PATH("t"))
    st.rememberData(.empty, onPath: PATH("q"))

    var num = 0
    var gotT = false
    var gotQ = false
    st.forEachChild { key, _ in
      num += 1
      if key == "t" {
        gotT = true
      } else if key == "q" {
        gotQ = true
      } else {
        XCTFail("Unknown child")
      }
    }

    XCTAssertTrue(gotT, "Saw t")
    XCTAssertTrue(gotQ, "Saw q")
    XCTAssertEqual(num, 2, "Saw two children")
  }

  func testIterateTrees() {
    var st = FSparseSnapshotTree()
    var count = 0
    st.forEachTreeAtPath(PATH("")) { _, _ in
      count += 1
    }
    XCTAssertEqual(count, 0, "No trees to iterate through")

    st.rememberData(NODE(1), onPath: PATH("t"))
    st.rememberData(NODE(2), onPath: PATH("a/b"))
    st.rememberData(NODE(3), onPath: PATH("a/x/g"))
    st.rememberData(NODE(NSNull()), onPath: PATH("a/x/null"))

    var num = 0
    var got1 = false
    var got2 = false
    var got3 = false
    var gotNull = false
    st.forEachTreeAtPath(PATH("q")) { path, data in
      num += 1
      let pathString = path.description
      if pathString == "/q/t" {
        got1 = true
        XCTAssertEqual(data.val(), 1, "got 1")
      } else if pathString == "/q/a/b" {
        got2 = true
        XCTAssertEqual(data.val(), 2, "got 2")
      } else if pathString == "/q/a/x/g" {
        got3 = true
        XCTAssertEqual(data.val(), 3, "got 3")
      } else if pathString == "/q/a/x/null" {
        gotNull = true
        XCTAssertEqual(data.val(), NSNull() as AnyHashable, "got null")
      } else {
        XCTFail("unknown tree")
      }
    }

    XCTAssertTrue(got1 && got2 && got3 && gotNull, "saw all the children")
    XCTAssertEqual(num, 4, "Saw the right number of children")
  }

  func testSetLeafAndForgetDeeperPath() {
    var st = FSparseSnapshotTree()
    st.rememberData(NODE("bar"), onPath: PATH("foo"))
    let safeToRemove = st.forgetPath(PATH("foo/baz"))
    XCTAssertFalse(safeToRemove, "Should not have deleted anything, nothing to remove")
  }
}
