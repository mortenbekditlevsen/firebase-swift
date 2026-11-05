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

// Port of upstream's FirebaseDatabase/Tests/Unit/FNodeTests.m (13.1.1).
// Port note: the port's nodes are one value type, `FNode`; upstream's
// FEmptyNode, FLeafNode and an empty FChildrenNode are `.empty`,
// `.leaf(…)` and `.children([:])`.

@testable import FirebaseDatabase
import XCTest

class FNodeTests: XCTestCase {
  private func hash(_ node: FNode) -> Int {
    node.hashValue
  }

  func testLeafNodeEqualsHashCode() {
    let falseNode = NODE(false)
    let trueNode = NODE(true)
    let stringOneNode = NODE("one")
    let stringTwoNode = NODE("two")
    let zeroNode = NODE(0)
    let oneNode = NODE(1)
    let emptyNode1 = NODE(nil)
    let emptyNode2 = NODE(NSNull())

    XCTAssertEqual(falseNode, NODE(false))
    XCTAssertEqual(hash(falseNode), hash(NODE(false)))
    XCTAssertEqual(trueNode, NODE(true))
    XCTAssertEqual(hash(trueNode), hash(NODE(true)))
    XCTAssertNotEqual(falseNode, trueNode)
    XCTAssertNotEqual(falseNode, oneNode)
    XCTAssertNotEqual(falseNode, stringOneNode)
    XCTAssertNotEqual(falseNode, emptyNode1)

    XCTAssertEqual(stringOneNode, NODE("one"))
    XCTAssertEqual(hash(stringOneNode), hash(NODE("one")))
    XCTAssertNotEqual(stringOneNode, stringTwoNode)
    XCTAssertNotEqual(stringOneNode, emptyNode1)
    XCTAssertNotEqual(stringOneNode, oneNode)
    XCTAssertNotEqual(stringOneNode, trueNode)

    XCTAssertEqual(zeroNode, NODE(0))
    XCTAssertEqual(hash(zeroNode), hash(NODE(0)))
    XCTAssertNotEqual(zeroNode, oneNode)
    XCTAssertNotEqual(zeroNode, emptyNode1)
    XCTAssertNotEqual(zeroNode, falseNode)

    XCTAssertEqual(emptyNode1, emptyNode2)
    XCTAssertEqual(hash(emptyNode1), hash(emptyNode2))
  }

  func testLeafNodePrioritiesEqualsHashCode() {
    let oneOne = FSnapshotUtilities.nodeFrom(1, priority: 1)
    let stringOne = FSnapshotUtilities.nodeFrom("value", priority: 1)
    let oneString = FSnapshotUtilities.nodeFrom(1, priority: "value")
    let stringString = FSnapshotUtilities.nodeFrom("value", priority: "value")

    XCTAssertEqual(oneOne, FSnapshotUtilities.nodeFrom(1, priority: 1))
    XCTAssertEqual(hash(oneOne), hash(FSnapshotUtilities.nodeFrom(1, priority: 1)))
    XCTAssertNotEqual(oneOne, stringOne)
    XCTAssertNotEqual(oneOne, oneString)
    XCTAssertNotEqual(oneOne, stringString)

    XCTAssertEqual(stringOne, FSnapshotUtilities.nodeFrom("value", priority: 1))
    XCTAssertEqual(hash(stringOne), hash(FSnapshotUtilities.nodeFrom("value", priority: 1)))
    XCTAssertNotEqual(stringOne, oneOne)
    XCTAssertNotEqual(stringOne, oneString)
    XCTAssertNotEqual(stringOne, stringString)

    XCTAssertEqual(oneString, FSnapshotUtilities.nodeFrom(1, priority: "value"))
    XCTAssertEqual(hash(oneString), hash(FSnapshotUtilities.nodeFrom(1, priority: "value")))
    XCTAssertNotEqual(oneString, stringOne)
    XCTAssertNotEqual(oneString, oneOne)
    XCTAssertNotEqual(oneString, stringString)

    XCTAssertEqual(stringString, FSnapshotUtilities.nodeFrom("value", priority: "value"))
    XCTAssertEqual(hash(stringString),
                   hash(FSnapshotUtilities.nodeFrom("value", priority: "value")))
    XCTAssertNotEqual(stringString, stringOne)
    XCTAssertNotEqual(stringString, oneString)
    XCTAssertNotEqual(stringString, oneOne)
  }

  func testChildrenNodeEqualsHashCode() {
    let nodeOne = NODE(["one": 1, "two": 2, ".priority": "prio"])
    var nodeTwo = FNode.empty.updateImmediateChild("one", withNewChild: NODE(1))
    nodeTwo = nodeTwo.updateImmediateChild("two", withNewChild: NODE(2))
    nodeTwo = nodeTwo.updatePriority(NODE("prio"))

    XCTAssertEqual(nodeOne, nodeTwo)
    XCTAssertEqual(hash(nodeOne), hash(nodeTwo))
    XCTAssertNotEqual(nodeOne.updatePriority(.empty), nodeOne)
    XCTAssertNotEqual(nodeOne.updateImmediateChild("one", withNewChild: .empty), nodeOne)
    XCTAssertNotEqual(nodeOne.updateImmediateChild("one", withNewChild: NODE(2)), nodeOne)
  }

  func testLeadingZerosWorkCorrectly() {
    let data: [String: Any] = ["1": 1, "01": 2, "001": 3, "0001": 4]

    let node = NODE(data)
    XCTAssertEqual(node.getImmediateChild("1").val(), 1 as AnyHashable)
    XCTAssertEqual(node.getImmediateChild("01").val(), 2 as AnyHashable)
    XCTAssertEqual(node.getImmediateChild("001").val(), 3 as AnyHashable)
    XCTAssertEqual(node.getImmediateChild("0001").val(), 4 as AnyHashable)
  }

  func testLeadindZerosArePreservedInValue() {
    let data: [String: AnyHashable] = ["1": 1, "01": 2, "001": 3, "0001": 4]

    XCTAssertEqual(NODE(data).val(), data as AnyHashable)
  }

  func testEmptyNodeEqualsEmptyChildrenNode() {
    XCTAssertEqual(FNode.empty, FNode.children([:]))
    XCTAssertEqual(FNode.children([:]), FNode.empty)
    XCTAssertEqual(hash(FNode.children([:])), hash(FNode.empty))
  }

  func testUpdatingEmptyChildrenDoesntOverwriteLeafNode() {
    let node = NODE("value")
    XCTAssertEqual(node, node.updateChild(PATH(".priority"), withNewChild: .empty))
    XCTAssertEqual(node, node.updateChild(PATH("child"), withNewChild: .empty))
    XCTAssertEqual(node, node.updateChild(PATH("child/.priority"), withNewChild: .empty))
    XCTAssertEqual(node, node.updateImmediateChild("child", withNewChild: .empty))
    XCTAssertEqual(node, node.updateImmediateChild(".priority", withNewChild: .empty))
  }

  func testUpdatingPrioritiesOnEmptyNodesIsANoOp() {
    let priority = NODE("prio")
    XCTAssertTrue(FNode.empty.updatePriority(priority).getPriority().isEmpty)
    XCTAssertTrue(FNode.empty.updateChild(PATH(".priority"), withNewChild: priority)
      .getPriority().isEmpty)
    XCTAssertTrue(FNode.empty.updateImmediateChild(".priority", withNewChild: priority)
      .getPriority().isEmpty)

    let valueNode = NODE("value")
    let childPath = PATH("child")
    let reemptiedChildren = FNode.empty.updateChild(childPath, withNewChild: valueNode)
      .updateChild(childPath, withNewChild: .empty)
    XCTAssertTrue(reemptiedChildren.updatePriority(priority).getPriority().isEmpty)
    XCTAssertTrue(reemptiedChildren.updateChild(PATH(".priority"), withNewChild: priority)
      .getPriority().isEmpty)
    XCTAssertTrue(reemptiedChildren.updateImmediateChild(".priority", withNewChild: priority)
      .getPriority().isEmpty)
  }

  func testDeletingLastChildFromChildrenNodeRemovesPriority() {
    let priority = NODE("prio")
    let valueNode = NODE("value")
    let childPath = PATH("child")
    let withPriority = FNode.empty.updateChild(childPath, withNewChild: valueNode)
      .updatePriority(priority)
    XCTAssertEqual(priority, withPriority.getPriority())
    let deletedChild = withPriority.updateChild(childPath, withNewChild: .empty)
    XCTAssertTrue(deletedChild.getPriority().isEmpty)
  }

  func testFromNodeReturnsEmptyNodesWithoutPriority() {
    let empty1 = NODE([".priority": "prio"])
    XCTAssertTrue(empty1.getPriority().isEmpty)

    let empty2 = NODE(["dummy": NSNull(), ".priority": "prio"])
    XCTAssertTrue(empty2.getPriority().isEmpty)
  }
}
