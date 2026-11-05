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

// Port of upstream's FirebaseDatabase/Tests/Unit/FIRDataSnapshotTests.m (13.1.1).
// Port notes: nodes are the `FNode` value type, whose children are a
// SortedDictionary (upstream's tests build FImmutableSortedDictionaries with a
// comparator); the indexes are cases of `FIndex`; `FUtilities.compareKey` is
// upstream's `keyComparator`.

@testable import FirebaseDatabase
import XCTest

class FIRDataSnapshotTests: XCTestCase {
  private func snapshotFor(_ json: Any?) -> DataSnapshot {
    let config = FTestHelpers.defaultConfig()
    let repoInfo = FRepoInfo(host: "example.com", isSecure: false, withNamespace: "default")
    let dummyRef = DatabaseReference(repo: FRepoManager.getRepo(repoInfo, config: config),
                                     path: .empty)
    let indexed = FIndexedNode(node: NODE(json))
    return DataSnapshot(ref: dummyRef, indexedNode: indexed)
  }

  private func value(_ snapshot: DataSnapshot) -> AnyHashable? {
    snapshot.value as? AnyHashable
  }

  func testCreationLeafNodesVariousTypes() {
    let fortyTwo = NODE(42)
    var x = FSnapshotUtilities.nodeFrom(5, priority: 42)
    XCTAssertEqual(x.val(), 5, "Values are the same")
    XCTAssertEqual(x.getPriority(), fortyTwo, "Priority is the same")
    XCTAssertTrue(x.isLeafNode(), "Node is a leaf")

    x = NODE("test")
    XCTAssertEqual(x.val(), "test", "Check if leaf node is holding onto a string value")

    // Port note: through `as? Bool`, as on Linux a Boolean NSNumber doesn't
    // equal a Bool as AnyHashable.
    x = NODE(true)
    XCTAssertEqual(x.val() as? Bool, true, "Check if leaf node is holding onto a YES boolean")

    x = NODE(false)
    XCTAssertEqual(x.val() as? Bool, false, "Check if leaf node is holding onto a NO boolean")
  }

  func testUpdatingPriorityWithoutChangingOld() {
    let x = FSnapshotUtilities.nodeFrom("test", priority: 42)
    let y = x.updatePriority(NODE(187))

    // old node is the same
    XCTAssertEqual(x.val(), "test", "Values of old node are the same")
    XCTAssertEqual(x.getPriority(), NODE(42), "Priority of old node is the same.")

    // new node has the new priority but the old value
    XCTAssertEqual(y.val(), "test", "Values of old node are the same")
    XCTAssertEqual(y.getPriority(), NODE(187), "Priority of new node is update")
  }

  func testUpdateImmediateChildReturnsANewChildrenNode() {
    let x = FSnapshotUtilities.nodeFrom("test", priority: 42)
    let y = x.updateImmediateChild("test", withNewChild: NODE("foo"))

    XCTAssertFalse(y.isLeafNode(), "New node is no longer a leaf")
    XCTAssertEqual(y.getPriority(), NODE(42), "Priority of new node is update")
    XCTAssertEqual(y.getImmediateChild("test").val(), "foo", "Child node has the correct value")
  }

  func testGetImmediateChildOnLeafNode() {
    let x = NODE("test")
    XCTAssertEqual(x.getImmediateChild("foo"), FNode.empty,
                   "Get immediate child on leaf node returns empty node")
  }

  func testGetChildReturnsEmptyNode() {
    let x = NODE("test")
    XCTAssertEqual(x.getChild(PATH("foo/bar")), FNode.empty,
                   "Get child returns an empty node.")
  }

  func testUpdateImmediateChildWithNewNode() {
    let x = FNode.children([:])
    let newValue = NODE("new value")
    let y = x.updateImmediateChild("test", withNewChild: newValue)

    XCTAssertEqual(x.children, [:], "Original object stays the same")
    XCTAssertEqual(y.children[KeyIndex(key: "test")], newValue,
                   "New internal node with the proper new value")
    XCTAssertEqual(y.children[KeyIndex(key: "test")]?.val(), "new value", "Check the payload")
  }

  func testUpdatechildWithNewNode() {
    let x = FNode.children([:])
    let newValue = NODE("new value")
    let y = x.updateChild(PATH("test/foo"), withNewChild: newValue)
    XCTAssertEqual(x.children, [:], "Original object stays the same")
    XCTAssertEqual(y.getChild(PATH("test/foo")), newValue, "Check if the updateChild held")
    XCTAssertEqual(y.getChild(PATH("test/foo")).val(), "new value", "Check the payload")
  }

  func testObjectTypes() {
    XCTAssertEqual("string", FUtilities.getJavascriptType("").rawValue, "Check string type")
    XCTAssertEqual("string", FUtilities.getJavascriptType("moo").rawValue, "Check string type")
    XCTAssertEqual("boolean", FUtilities.getJavascriptType(true).rawValue, "Check boolean type")
    XCTAssertEqual("boolean", FUtilities.getJavascriptType(false).rawValue, "Check boolean type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(5).rawValue, "Check number type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(5.5).rawValue, "Check number type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(0).rawValue, "Check number type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(8_273_482_734).rawValue,
                   "Check number type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(-2).rawValue, "Check number type")
    XCTAssertEqual("number", FUtilities.getJavascriptType(-2.11).rawValue, "Check number type")
  }

  func testNodeHashWorksCorrectly() {
    let node = NODE([
      "intNode": 4,
      "doubleNode": 4.5623,
      "stringNode": "hey guys",
      "boolNode": true,
    ])

    XCTAssertEqual("eVih19a6ZDz3NL32uVBtg9KSgQY=", node.getImmediateChild("intNode").dataHash(),
                   "Check integer node")
    XCTAssertEqual("vf1CL0tIRwXXunHcG/irRECk3lY=",
                   node.getImmediateChild("doubleNode").dataHash(), "Check double node")
    XCTAssertEqual("CUNLXWpCVoJE6z7z1vE57lGaKAU=",
                   node.getImmediateChild("stringNode").dataHash(), "Check string node")
    XCTAssertEqual("E5z61QM0lN/U2WsOnusszCTkR8M=", node.getImmediateChild("boolNode").dataHash(),
                   "Check boolean node")
    XCTAssertEqual("6Mc4jFmNdrLVIlJJjz2/MakTK9I=", node.dataHash(), "Check compound node")
  }

  func testNodeHashWorksCorrectlyWithPriorities() {
    let node = NODE([
      "root": [
        "c": [".value": 99, ".priority": "abc"] as [String: Any],
        ".priority": "def",
      ] as [String: Any],
    ])
    XCTAssertEqual("Fm6tzN4CVEu5WxFDZUdTtqbTVaA=", node.dataHash(), "Check compound node")
  }

  func testChildrenNodeHashUsesPriorityOrderWhenEveryChildHasPriority() {
    let node = NODE([
      "a": [".value": "value-a", ".priority": 2] as [String: Any],
      "z": [".value": "value-z", ".priority": 1] as [String: Any],
    ])
    let expectedHashRepresentation =
      ":z:\(node.getImmediateChild("z").dataHash()):a:\(node.getImmediateChild("a").dataHash())"
    let expectedHash = FStringUtilities.base64EncodedSha1(expectedHashRepresentation)
    XCTAssertEqual(expectedHash, node.dataHash())
    // Literal computed with the JS SDK's hash algorithm, independently of iOS child hashes.
    XCTAssertEqual("ioxrlJO1lx052It4dFes/dAFe9Y=", node.dataHash())
  }

  func testGetPredecessorChild() {
    let node = NODE(["d": true, "a": true, "g": true, "c": true, "e": true])
    XCTAssertNil(node.predecessorChildKey("a"), "Check the first one sorted properly")
    XCTAssertEqual(node.predecessorChildKey("c"), "a", "Check a comes before c")
    XCTAssertEqual(node.predecessorChildKey("d"), "c", "Check c comes before d")
    XCTAssertEqual(node.predecessorChildKey("e"), "d", "Check d comes before e")
    XCTAssertEqual(node.predecessorChildKey("g"), "e", "Check e comes before g")
  }

  func testSortedChildrenGetPredecessorChildWorksCorrectly() {
    // XXX impl SortedChildren
  }

  func testSortedChildrenUpdateImmediateChildrenWorksCorrectly() {
    // XXX imple SortedChildren
  }

  func testDataSnapshotHasChildrenWorks() {
    var snap = snapshotFor([String: Any]())
    XCTAssertFalse(snap.hasChildren(), "Empty dict has no children")

    snap = snapshotFor(5)
    XCTAssertFalse(snap.hasChildren(), "Leaf node has no children")

    snap = snapshotFor(["x": 5])
    XCTAssertTrue(snap.hasChildren(), "Properly has children")
  }

  func testDataSnapshotValWorks() {
    var snap = snapshotFor(5)
    XCTAssertEqual(value(snap), 5, "Leaf node values are correct")

    snap = snapshotFor([String: Any]())
    XCTAssertEqual(value(snap), NSNull(), "Snapshot value is properly null")

    let dict: [String: AnyHashable] = [
      "x": 5, "y": ["ya": 1, "yb": 2, "yc": ["yca": 3] as [String: AnyHashable]] as [String: AnyHashable],
    ]
    snap = snapshotFor(dict)
    XCTAssertEqual(value(snap), dict, "Check if the dictionaries are the same")
  }

  func testDataSnapshotChildWorks() {
    let snap = snapshotFor(["x": 5, "y": ["yy": 3, "yz": 4]] as [String: Any])
    XCTAssertEqual(value(snap.childSnapshot(forPath: "x")), 5, "Check x")
    let dict: [String: AnyHashable] = ["yy": 3, "yz": 4]
    XCTAssertEqual(value(snap.childSnapshot(forPath: "y")), dict, "Check y")

    XCTAssertEqual(value(snap.childSnapshot(forPath: "y").childSnapshot(forPath: "yy")), 3,
                   "Check y/yy")
    XCTAssertEqual(value(snap.childSnapshot(forPath: "y/yz")), 4, "Check y/yz")
    XCTAssertEqual(value(snap.childSnapshot(forPath: "z")), NSNull(), "Check nonexistent z")
    XCTAssertEqual(value(snap.childSnapshot(forPath: "x/y")), NSNull(),
                   "Check value of existent internal node")
    XCTAssertEqual(value(snap.childSnapshot(forPath: "x").childSnapshot(forPath: "y")), NSNull(),
                   "Check value of existent internal node")
  }

  func testDataSnapshotHasChildWorks() {
    let snap = snapshotFor(["x": 5, "y": ["yy": 3, "yz": 4]] as [String: Any])
    XCTAssertTrue(snap.hasChild("x"), "Has child")
    XCTAssertTrue(snap.hasChild("y/yy"), "Has child")
    XCTAssertFalse(snap.hasChild("dinosaur dinosaucer"), "No child")
    XCTAssertFalse(snap.childSnapshot(forPath: "x").hasChild("anything"), "No child")
    XCTAssertFalse(snap.hasChild("x/anything/at/all"), "No child")
  }

  func testDataSnapshotNameWorks() {
    let snap = snapshotFor(["a": ["b": ["c": 5]]])
    XCTAssertEqual(snap.childSnapshot(forPath: "a").key, "a", "Check child key")
    XCTAssertEqual(snap.childSnapshot(forPath: "a/b/c").key, "c", "Check child key")
    XCTAssertEqual(snap.childSnapshot(forPath: "/a/b/c").key, "c", "Check child key")
    XCTAssertEqual(snap.childSnapshot(forPath: "/a/b/c/").key, "c", "Check child key")
    XCTAssertEqual(snap.childSnapshot(forPath: "////a///b////c///").key, "c", "Check child key")
    XCTAssertEqual(snap.childSnapshot(forPath: "////").key, snap.key, "Check root key")
    XCTAssertEqual(snap.childSnapshot(forPath: "/z/q/r/v////m").key, "m",
                   "Should also work for nonexistent paths")
  }

  private func keysAndValues(_ snap: DataSnapshot) -> String {
    var out = ""
    for child in snap.children {
      // Port note: whole numbers without a fraction, as Darwin's NSNumber
      // prints them (Linux prints 1 as "1.0").
      let value = (child.value as? NSNumber).map { "\(Int($0.doubleValue))" } ?? "\(child.value!)"
      out += "\(child.key!):\(value):"
    }
    return out
  }

  func testDataSnapshotForEachWithNoPriorities() {
    let snap = snapshotFor([
      "a": 1,
      "z": 26,
      "m": 13,
      "n": 14,
      "c": 3,
      "b": 2,
      "e": 5,
    ])

    XCTAssertEqual(keysAndValues(snap), "a:1:b:2:c:3:e:5:m:13:n:14:z:26:", "Proper order")
  }

  func testDataSnapshotForEachWorksWithNumericPriorities() {
    let snap = snapshotFor([
      "a": [".value": 1, ".priority": 26],
      "z": [".value": 26, ".priority": 1],
      "m": [".value": 13, ".priority": 14],
      "n": [".value": 14, ".priority": 12],
      "c": [".value": 3, ".priority": 24],
      "b": [".value": 2, ".priority": 25],
      "e": [".value": 5, ".priority": 22],
    ])

    XCTAssertEqual(keysAndValues(snap), "z:26:n:14:m:13:e:5:c:3:b:2:a:1:", "Proper order")
  }

  func testDataSnapshotForEachWorksWithNumericPrioritiesAsStrings() {
    let snap = snapshotFor([
      "a": [".value": 1, ".priority": "26"] as [String: Any],
      "z": [".value": 26, ".priority": "1"] as [String: Any],
      "m": [".value": 13, ".priority": "14"] as [String: Any],
      "n": [".value": 14, ".priority": "12"] as [String: Any],
      "c": [".value": 3, ".priority": "24"] as [String: Any],
      "b": [".value": 2, ".priority": "25"] as [String: Any],
      "e": [".value": 5, ".priority": "22"] as [String: Any],
    ])

    XCTAssertEqual(keysAndValues(snap), "z:26:n:14:m:13:e:5:c:3:b:2:a:1:", "Proper order")
  }

  func testDataSnapshotForEachWorksAlphaPriorities() {
    let snap = snapshotFor([
      "a": [".value": 1, ".priority": "first"] as [String: Any],
      "z": [".value": 26, ".priority": "second"] as [String: Any],
      "m": [".value": 13, ".priority": "third"] as [String: Any],
      "n": [".value": 14, ".priority": "fourth"] as [String: Any],
      "c": [".value": 3, ".priority": "fifth"] as [String: Any],
      "b": [".value": 2, ".priority": "sixth"] as [String: Any],
      "e": [".value": 5, ".priority": "seventh"] as [String: Any],
    ])

    var priorities: [AnyHashable] = []
    for child in snap.children {
      priorities.append(child.priority as! AnyHashable)
    }
    XCTAssertEqual(keysAndValues(snap), "c:3:a:1:n:14:z:26:e:5:b:2:m:13:", "Proper order")
    let expected: [AnyHashable] = ["fifth", "first", "fourth", "second", "seventh", "sixth",
                                   "third"]
    XCTAssertEqual(priorities, expected, "Correct priorities")
    XCTAssertEqual(snap.childrenCount, 7, "Got correct children count")
  }

  func testDataSnapshotForEachWorksWithMixedPriorities() {
    let snap = snapshotFor([
      "alpha42": [".value": 1, ".priority": "zed"] as [String: Any],
      "noPriorityC": [".value": 1, ".priority": NSNull()] as [String: Any],
      "alpha14": [".value": 1, ".priority": "500"] as [String: Any],
      "noPriorityB": [".value": 1, ".priority": NSNull()] as [String: Any],
      "num80": [".value": 1, ".priority": 4000.1] as [String: Any],
      "alpha13": [".value": 1, ".priority": "4000"] as [String: Any],
      "alpha11": [".value": 1, ".priority": "24"] as [String: Any],
      "alpha41": [".value": 1, ".priority": "zed"] as [String: Any],
      "alpha20": [".value": 1, ".priority": "horse"] as [String: Any],
      "num20": [".value": 1, ".priority": 123] as [String: Any],
      "num70": [".value": 1, ".priority": 4000.01] as [String: Any],
      "noPriorityA": [".value": 1, ".priority": NSNull()] as [String: Any],
      "alpha30": [".value": 1, ".priority": "tree"] as [String: Any],
      "alpha12": [".value": 1, ".priority": "300"] as [String: Any],
      "num60": [".value": 1, ".priority": 4000.001] as [String: Any],
      "alpha10": [".value": 1, ".priority": "0horse"] as [String: Any],
      "num42": [".value": 1, ".priority": 500] as [String: Any],
      "alpha40": [".value": 1, ".priority": "zed"] as [String: Any],
      "num40": [".value": 1, ".priority": 500] as [String: Any],
    ])

    var out = ""
    for child in snap.children {
      out += "\(child.key!), "
    }

    let expected =
      "noPriorityA, noPriorityB, noPriorityC, num20, num40, num42, num60, num70, num80, alpha10, "
        + "alpha11, alpha12, alpha13, alpha14, alpha20, alpha30, alpha40, alpha41, alpha42, "
    XCTAssertEqual(expected, out, "Proper ordering seen")
  }

  func testIgnoresNullValues() {
    let snap = snapshotFor(["a": 1, "b": NSNull()] as [String: Any])
    XCTAssertFalse(snap.hasChild("b"), "Should not have b, it was null")
  }

  func testNameComparator() {
    let keyComparator = FUtilities.compareKey
    XCTAssertEqual(keyComparator("1234", "1234"), .orderedSame, "NameComparator compares ints")
    XCTAssertEqual(keyComparator("1234", "12345"), .orderedAscending,
                   "NameComparator compares ints")
    XCTAssertEqual(keyComparator("4321", "1234"), .orderedDescending,
                   "NameComparator compares ints")
    XCTAssertEqual(keyComparator("1234", "zzzz"), .orderedAscending,
                   "NameComparator priorities ints")
    XCTAssertEqual(keyComparator("4321", "12a"), .orderedAscending,
                   "NameComparator priorities ints")
    XCTAssertEqual(keyComparator("abc", "abcd"), .orderedAscending,
                   "NameComparator uses lexiographical sorting for strings.")
    XCTAssertEqual(keyComparator("zzzz", "aaaa"), .orderedDescending,
                   "NameComparator compares strings")
    XCTAssertEqual(keyComparator("-1234", "0"), .orderedAscending,
                   "NameComparator compares negative values")
    XCTAssertEqual(keyComparator("-1234", "-1234"), .orderedSame,
                   "NameComparator compares negative values")
    XCTAssertEqual(keyComparator("-1234", "-4321"), .orderedDescending,
                   "NameComparator compares negative values")
    XCTAssertEqual(keyComparator("-1234", "-"), .orderedAscending,
                   "NameComparator does not parse - as integer")
    XCTAssertEqual(keyComparator("-", "1234"), .orderedDescending,
                   "NameComparator does not parse - as integer")
  }

  func testExistsWorks() {
    var snap = snapshotFor([String: Any]())
    XCTAssertFalse(snap.exists(), "Should not exist")
    snap = snapshotFor([".priority": "1"])
    XCTAssertFalse(snap.exists(), "Should not exist")
    snap = snapshotFor(NSNull())
    XCTAssertFalse(snap.exists(), "Should not exist")
    snap = snapshotFor(true)
    XCTAssertTrue(snap.exists(), "Should exist")
    snap = snapshotFor(5)
    XCTAssertTrue(snap.exists(), "Should exist")
    snap = snapshotFor(["x": 5])
    XCTAssertTrue(snap.exists(), "Should exist")
  }

  func testUpdatingEmptyChildDoesntOverwriteLeafNode() {
    let node = NODE("value")
    XCTAssertEqual(node, node.updateChild(PATH(".priority"), withNewChild: .empty),
                   "Update should not affect node.")
    XCTAssertEqual(node, node.updateChild(PATH("child"), withNewChild: .empty),
                   "Update should not affect node.")
    XCTAssertEqual(node, node.updateChild(PATH("child/.priority"), withNewChild: .empty),
                   "Update should not affect node.")
    XCTAssertEqual(node, node.updateImmediateChild("child", withNewChild: .empty),
                   "Update should not affect node.")
    XCTAssertEqual(node, node.updateImmediateChild(".priority", withNewChild: .empty),
                   "Update should not affect node.")
  }

  /* This was reported by a customer, which broke because 유주연 > 윤규완오빠 but also 윤규완오빠 >
   * 유주연  with the default string comparison... */
  func testUnicodeEquality() {
    let node1 = FNamedNode(name: "a", andNode: NODE("유주연"))
    let node2 = FNamedNode(name: "a", andNode: NODE("윤규완오빠"))
    let index = FIndex.value
    // x < y should imply y > x
    XCTAssertEqual(index.compareNamedNode(lhs: node1, rhs: node2).rawValue,
                   -index.compareNamedNode(lhs: node2, rhs: node1).rawValue)
  }
}
