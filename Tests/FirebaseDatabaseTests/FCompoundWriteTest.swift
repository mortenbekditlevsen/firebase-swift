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

// Port of upstream's FirebaseDatabase/Tests/Unit/FCompoundWriteTest.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

class FCompoundWriteTest: XCTestCase {
  let leafNode = NODE("leaf-node")
  let priorityNode = NODE("prio")
  let baseNode = NODE(["child-1": "value-1", "child-2": "value-2"])

  private func assertAppliedCompoundWrite(_ compoundWrite: FCompoundWrite,
                                          equalsNode node: FNode,
                                          withPriority priority: FNode,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
    let updatedNode = compoundWrite.applyToNode(node)
    if node.isEmpty {
      XCTAssertEqual(FNode.empty, updatedNode,
                     "Applied compound write should be empty. \(updatedNode)",
                     file: file, line: line)
    } else {
      XCTAssertEqual(node.updatePriority(priority), updatedNode,
                     "Applied compound write should equal node with priority. \(updatedNode)",
                     file: file, line: line)
    }
  }

  func testEmptyMergeIsEmpty() {
    let compoundWrite = FCompoundWrite.emptyWrite
    XCTAssertTrue(compoundWrite.isEmpty, "Empty write should be empty \(compoundWrite)")
  }

  func testCompoundWriteWithPriorityUpdateIsNotEmpty() {
    let compoundWrite = FCompoundWrite.emptyWrite.addWrite(priorityNode, atKey: ".priority")
    XCTAssertFalse(compoundWrite.isEmpty, "Priority update should not be empty \(compoundWrite)")
  }

  func testCompoundWriteWithUpdateIsNotEmpty() {
    let compoundWrite = FCompoundWrite.emptyWrite.addWrite(leafNode, atPath: PATH("foo/bar"))
    XCTAssertFalse(compoundWrite.isEmpty, "Update should not be empty \(compoundWrite)")
  }

  func testCompoundWriteWithRootUpdateIsNotEmpty() {
    let compoundWrite = FCompoundWrite.emptyWrite.addWrite(leafNode, atPath: .empty)
    XCTAssertFalse(compoundWrite.isEmpty, "Update at root should not be empty \(compoundWrite)")
  }

  func testCompoundWriteWithEmptyRootUpdateIsNotEmpty() {
    let compoundWrite = FCompoundWrite.emptyWrite.addWrite(.empty, atPath: .empty)
    XCTAssertFalse(compoundWrite.isEmpty,
                   "Empty root update should not be empty \(compoundWrite)")
  }

  func testCompoundWriteWithRootPriorityUpdateAndChildMergeIsNotEmpty() {
    var compoundWrite = FCompoundWrite.emptyWrite.addWrite(priorityNode, atKey: ".priority")
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH(".priority"))
    XCTAssertFalse(compoundWrite.isEmpty,
                   "Compound write with root priority update and child merge should not be empty.")
  }

  func testAppliesLeafOverwrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: .empty)
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, leafNode, "Should get leaf node once applied \(updatedNode)")
  }

  func testAppliesChildrenOverwrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let childNode = FNode.empty.updateImmediateChild("child", withNewChild: leafNode)
    compoundWrite = compoundWrite.addWrite(childNode, atPath: .empty)
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, childNode, "Child overwrite should work")
  }

  func testAddsChildNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let expectedNode = FNode.empty.updateImmediateChild("child", withNewChild: leafNode)
    compoundWrite = compoundWrite.addWrite(leafNode, atKey: "child")
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, expectedNode, "Adding child node should work \(updatedNode)")
  }

  func testAddsDeepChildNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let path = PATH("deep/deep/node")
    let expectedNode = FNode.empty.updateChild(path, withNewChild: leafNode)
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: path)
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, expectedNode, "Should add deep child node correctly")
  }

  func testOverwritesExistingChild() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let path = PATH("child-1")
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: path)
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = baseNode.updateImmediateChild(path.getFront()!, withNewChild: leafNode)
    XCTAssertEqual(updatedNode, expectedNode, "Overwriting existing child should work.")
  }

  func testUpdatesExistingChild() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let path = PATH("child-1/foo")
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: path)
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = baseNode.updateChild(path, withNewChild: leafNode)
    XCTAssertEqual(updatedNode, expectedNode, "Updating existing child should work")
  }

  func testDoesntUpdatePriorityOnEmptyNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atKey: ".priority")
    assertAppliedCompoundWrite(compoundWrite, equalsNode: .empty, withPriority: .empty)
  }

  func testUpdatesPriorityOnNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atKey: ".priority")
    let node = NODE("value")
    assertAppliedCompoundWrite(compoundWrite, equalsNode: node, withPriority: priorityNode)
  }

  func testUpdatesPriorityOfChild() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let path = PATH("child-1/.priority")
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: path)
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = baseNode.updateChild(path, withNewChild: priorityNode)
    XCTAssertEqual(updatedNode, expectedNode, "Updating priority of child should work.")
  }

  func testDoesntUpdatePriorityOfNonExistentChild() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let path = PATH("child-3/.priority")
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: path)
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, baseNode, "Should not update priority of nonexistent child")
  }

  func testDeepUpdateExistingUpdates() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update1 = NODE(["foo": "foo-value", "bar": "bar-value"])
    let update2 = NODE("baz-value")
    let update3 = NODE("new-foo-value")
    compoundWrite = compoundWrite.addWrite(update1, atPath: PATH("child-1"))
    compoundWrite = compoundWrite.addWrite(update2, atPath: PATH("child-1/baz"))
    compoundWrite = compoundWrite.addWrite(update3, atPath: PATH("child-1/foo"))
    let expectedChild1 = ["foo": "new-foo-value", "bar": "bar-value", "baz": "baz-value"]
    let expectedNode = baseNode.updateImmediateChild("child-1",
                                                     withNewChild: NODE(expectedChild1))
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, expectedNode, "Deep update with existing updates should work.")
  }

  func testShallowUpdateRemovesDeepUpdate() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update1 = NODE("new-foo-value")
    let update2 = NODE("baz-value")
    let update3 = NODE(["foo": "foo-value", "bar": "bar-value"])
    compoundWrite = compoundWrite.addWrite(update1, atPath: PATH("child-1/foo"))
    compoundWrite = compoundWrite.addWrite(update2, atPath: PATH("child-1/baz"))
    compoundWrite = compoundWrite.addWrite(update3, atPath: PATH("child-1"))
    let expectedChild1 = ["foo": "foo-value", "bar": "bar-value"]
    let expectedNode = baseNode.updateImmediateChild("child-1",
                                                     withNewChild: NODE(expectedChild1))
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, expectedNode, "Shallow update should remove deep updates.")
  }

  func testChildPriorityDoesntUpdateEmptyNodePriorityOnChildMerge() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH("child-1/.priority"))
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH("child-1"))
    assertAppliedCompoundWrite(compoundWrite, equalsNode: .empty, withPriority: .empty)
  }

  func testChildPriorityUpdatesPriorityOnChildMerge() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH("child-1/.priority"))
    let node = NODE("value")
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH("child-1"))
    assertAppliedCompoundWrite(compoundWrite, equalsNode: node, withPriority: priorityNode)
  }

  func testChildPriorityUpdatesEmptyPriorityOnChildMerge() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(.empty, atPath: PATH("child-1/.priority"))
    let node = FNode.leaf(.string("foo"), priority: priorityNode)
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH("child-1"))
    assertAppliedCompoundWrite(compoundWrite, equalsNode: node, withPriority: .empty)
  }

  func testDeepPrioritySetWorksOnEmptyNodeWhenOtherSetIsAvailable() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH("foo/.priority"))
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("foo/child"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    let updatedPriority = updatedNode.getChild(PATH("foo")).getPriority()
    XCTAssertEqual(updatedPriority, priorityNode, "Should get priority")
  }

  func testChildMergeLooksIntoUpdateNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update = NODE(["foo": "foo-value", "bar": "bar-value"])
    compoundWrite = compoundWrite.addWrite(update, atPath: .empty)
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH("foo"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    let expectedNode = NODE("foo-value")
    XCTAssertEqual(updatedNode, expectedNode, "Child merge should get updates.")
  }

  func testChildMergeRemovesNodeOnDeeperPaths() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update = NODE(["foo": "foo-value", "bar": "bar-value"])
    compoundWrite = compoundWrite.addWrite(update, atPath: .empty)
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH("foo/not/existing"))
    let updatedNode = compoundWrite.applyToNode(leafNode)
    let expectedNode = FNode.empty
    XCTAssertEqual(updatedNode, expectedNode, "Should not have node.")
  }

  func testChildMergeWithEmptyPathIsSameMerge() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update = NODE(["foo": "foo-value", "bar": "bar-value"])
    compoundWrite = compoundWrite.addWrite(update, atPath: .empty)
    XCTAssertEqual(compoundWrite.childCompoundWriteAtPath(.empty), compoundWrite,
                   "Child merge with empty path should be the same merge.")
  }

  func testRootUpdateRemovesRootPriority() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH(".priority"))
    let update = NODE("foo")
    compoundWrite = compoundWrite.addWrite(update, atPath: .empty)
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, update, "Root update should remove root priority")
  }

  func testDeepUpdateRemovesPriorityThere() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH("foo/.priority"))
    let update = NODE("bar")
    compoundWrite = compoundWrite.addWrite(update, atPath: PATH("foo"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    let expectedNode = NODE(["foo": "bar"])
    XCTAssertEqual(updatedNode, expectedNode, "Deep update should remove priority there")
  }

  func testAddingUpdatesAtPathWorks() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let updateDictionary: [String: Any] = ["foo": "foo-value", "bar": "bar-value"]
    let updates = FCompoundWrite.compoundWrite(valueDictionary: updateDictionary)
    compoundWrite = compoundWrite.addCompoundWrite(updates, atPath: PATH("child-1"))
    let expectedChild1 = ["foo": "foo-value", "bar": "bar-value"]
    let expectedNode = baseNode.updateImmediateChild("child-1",
                                                     withNewChild: NODE(expectedChild1))
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, expectedNode, "Adding updates at a path should work.")
  }

  func testAddingUpdatesAtRootWorks() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let updateDictionary: [String: Any] = [
      "child-1": "new-value-1", "child-2": NSNull(), "child-3": "value-3",
    ]
    let updates = FCompoundWrite.compoundWrite(valueDictionary: updateDictionary)
    compoundWrite = compoundWrite.addCompoundWrite(updates, atPath: .empty)
    let expected = ["child-1": "new-value-1", "child-3": "value-3"]
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = NODE(expected)
    XCTAssertEqual(updatedNode, expectedNode, "Adding updates at root should work.")
  }

  func testChildMergeOfRootPriorityWorks() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH(".priority"))
    compoundWrite = compoundWrite.childCompoundWriteAtPath(PATH(".priority"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, priorityNode, "Child merge of root priority should work.")
  }

  func testCompleteChildrenOnlyReturnsCompleteOverwrites() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("child-1"))
    let expectedChildren = [FNamedNode(name: "child-1", andNode: leafNode)]
    let completeChildren = compoundWrite.completeChildren
    XCTAssertEqual(completeChildren, expectedChildren,
                   "Complete children should only return on complete overwrites.")
  }

  func testCompleteChildrenOnlyReturnsEmptyOverwrites() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(.empty, atPath: PATH("child-1"))
    let expectedChildren = [FNamedNode(name: "child-1", andNode: .empty)]
    let completeChildren = compoundWrite.completeChildren
    XCTAssertEqual(completeChildren, expectedChildren,
                   "Complete children should return list with empty on empty overwrites.")
  }

  func testCompleteChildrenDoesntReturnDeepOverwrites() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("child-1/deep/path"))
    let expectedChildren: [FNamedNode] = []
    let completeChildren = compoundWrite.completeChildren
    XCTAssertEqual(completeChildren, expectedChildren,
                   "Should not get complete children on deep overwrites.")
  }

  func testCompleteChildrenReturnAllCompleteChildrenButNoIncomplete() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("child-1/deep/path"))
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("child-2"))
    compoundWrite = compoundWrite.addWrite(.empty, atPath: PATH("child-3"))
    let expected: [String: FNode] = ["child-2": leafNode, "child-3": .empty]
    var actual: [String: FNode] = [:]
    for node in compoundWrite.completeChildren {
      actual[node.name] = node.node
    }
    XCTAssertEqual(actual, expected,
                   "Complete children should get returned, but not incomplete ones.")
  }

  func testCompleteChildrenReturnAllChildrenForRootSet() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(baseNode, atPath: .empty)
    let expected: [String: FNode] = ["child-1": NODE("value-1"), "child-2": NODE("value-2")]
    var actual: [String: FNode] = [:]
    for node in compoundWrite.completeChildren {
      actual[node.name] = node.node
    }
    XCTAssertEqual(actual, expected, "Complete children should return all children on root set.")
  }

  func testEmptyMergeHasNoShadowingWrite() {
    XCTAssertFalse(FCompoundWrite.emptyWrite.hasCompleteWriteAtPath(.empty),
                   "Empty merge has no shadowing write.")
  }

  func testCompoundWriteWithEmptyRootHasShadowingWrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(.empty, atPath: .empty)
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(.empty),
                  "Empty write should have shadowing write at root.")
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(PATH("child")),
                  "Empty write should have complete write at child.")
  }

  func testCompoundWriteWithRootHasShadowingWrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: .empty)
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(.empty),
                  "Root write should have shadowing write at root.")
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(PATH("child")),
                  "Root write should have complete write at child.")
  }

  func testCompoundWriteWithDeepUpdateHasShadowingWrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: PATH("deep/update"))
    XCTAssertFalse(compoundWrite.hasCompleteWriteAtPath(.empty),
                   "Deep write should not have complete write at root.")
    XCTAssertFalse(compoundWrite.hasCompleteWriteAtPath(PATH("deep")),
                   "Deep write should not have should have complete write at child.")
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(PATH("deep/update")),
                  "Deep write should have complete write at deep child.")
  }

  func testCompoundWriteWithPriorityUpdateHasShadowingWrite() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH(".priority"))
    XCTAssertFalse(compoundWrite.hasCompleteWriteAtPath(.empty),
                   "Write with priority at root should not have complete write at root.")
    XCTAssertTrue(compoundWrite.hasCompleteWriteAtPath(PATH(".priority")),
                  "Write with priority at root should have complete priority.")
  }

  func testUpdatesCanBeRemoved() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update = NODE(["foo": "foo-value", "bar": "bar-value"])
    compoundWrite = compoundWrite.addWrite(update, atPath: PATH("child-1"))
    compoundWrite = compoundWrite.removeWriteAtPath(PATH("child-1"))
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, baseNode, "Updates should be removed.")
  }

  func testDeepRemovesHasNoEffectOnOverlayingSet() {
    // TODO I don't get this one.
    var compoundWrite = FCompoundWrite.emptyWrite
    let update1 = NODE(["foo": "foo-value", "bar": "bar-value"])
    let update2 = NODE("baz-value")
    let update3 = NODE("new-foo-value")
    compoundWrite = compoundWrite.addWrite(update1, atPath: PATH("child-1"))
    compoundWrite = compoundWrite.addWrite(update2, atPath: PATH("child-1/baz"))
    compoundWrite = compoundWrite.addWrite(update3, atPath: PATH("child-1/foo"))
    compoundWrite = compoundWrite.removeWriteAtPath(PATH("child-1/foo"))
    let expected = ["foo": "new-foo-value", "bar": "bar-value", "baz": "baz-value"]
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = baseNode.updateImmediateChild("child-1", withNewChild: NODE(expected))
    XCTAssertEqual(updatedNode, expectedNode,
                   "Deep removes should have no effect on overlaying set.")
  }

  func testRemoveAtPathWithoutSetIsWithoutEffect() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update1 = NODE(["foo": "foo-value", "bar": "bar-value"])
    let update2 = NODE("baz-value")
    let update3 = NODE("new-foo-value")
    compoundWrite = compoundWrite.addWrite(update1, atPath: PATH("child-1"))
    compoundWrite = compoundWrite.addWrite(update2, atPath: PATH("child-1/baz"))
    compoundWrite = compoundWrite.addWrite(update3, atPath: PATH("child-1/foo"))
    compoundWrite = compoundWrite.removeWriteAtPath(PATH("child-2"))
    let expected = ["foo": "new-foo-value", "bar": "bar-value", "baz": "baz-value"]
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = baseNode.updateImmediateChild("child-1", withNewChild: NODE(expected))
    XCTAssertEqual(updatedNode, expectedNode,
                   "Removing at path without a set should have no effect.")
  }

  func testCanRemovePriority() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH(".priority"))
    compoundWrite = compoundWrite.removeWriteAtPath(PATH(".priority"))
    assertAppliedCompoundWrite(compoundWrite, equalsNode: leafNode, withPriority: .empty)
  }

  func testRemovingOnlyAffectsRemovedPath() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let updateDictionary: [String: Any] = [
      "child-1": "new-value-1", "child-2": NSNull(), "child-3": "value-3",
    ]
    let updates = FCompoundWrite.compoundWrite(valueDictionary: updateDictionary)
    compoundWrite = compoundWrite.addCompoundWrite(updates, atPath: .empty)
    compoundWrite = compoundWrite.removeWriteAtPath(PATH("child-2"))
    let expected = ["child-1": "new-value-1", "child-2": "value-2", "child-3": "value-3"]
    let updatedNode = compoundWrite.applyToNode(baseNode)
    let expectedNode = NODE(expected)
    XCTAssertEqual(updatedNode, expectedNode, "Removing should only affected removed paths")
  }

  func testRemoveRemovesAllDeeperSets() {
    var compoundWrite = FCompoundWrite.emptyWrite
    let update2 = NODE("baz-value")
    let update3 = NODE("new-foo-value")
    compoundWrite = compoundWrite.addWrite(update2, atPath: PATH("child-1/baz"))
    compoundWrite = compoundWrite.addWrite(update3, atPath: PATH("child-1/foo"))
    compoundWrite = compoundWrite.removeWriteAtPath(PATH("child-1"))
    let updatedNode = compoundWrite.applyToNode(baseNode)
    XCTAssertEqual(updatedNode, baseNode, "Remove should remove deeper sets.")
  }

  func testRemoveAtRootAlsoRemovesPriority() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(.leaf(.string("foo"), priority: priorityNode),
                                           atPath: .empty)
    compoundWrite = compoundWrite.removeWriteAtPath(.empty)
    let node = NODE("value")
    assertAppliedCompoundWrite(compoundWrite, equalsNode: node, withPriority: .empty)
  }

  func testUpdatingPriorityDoesntOverwriteLeafNode() {
    // TODO I don't get this one.
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: .empty)
    compoundWrite = compoundWrite.addWrite(priorityNode, atPath: PATH("child/.priority"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, leafNode, "Updating priority should not overwrite leaf node.")
  }

  func testUpdatingEmptyChildNodeDoesntOverwriteLeafNode() {
    var compoundWrite = FCompoundWrite.emptyWrite
    compoundWrite = compoundWrite.addWrite(leafNode, atPath: .empty)
    compoundWrite = compoundWrite.addWrite(.empty, atPath: PATH("child"))
    let updatedNode = compoundWrite.applyToNode(.empty)
    XCTAssertEqual(updatedNode, leafNode, "Updating empty node should not overwrite leaf node.")
  }
}
