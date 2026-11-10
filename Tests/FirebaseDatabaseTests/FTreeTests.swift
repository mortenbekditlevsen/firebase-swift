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

@testable import FirebaseDatabase
import Testing

/// FTree's nodes are values, so every change must reach the root.
@DatabaseActor
struct FTreeTests {
  @Test func replacingAnExistingValueReachesTheRoot() {
    let tree = FTree<[Int]>()
    tree.subTree(FPath(with: "a/b/c")).setValue([1])
    tree.subTree(FPath(with: "a/b/c")).setValue([1, 2])
    #expect(tree.subTree(FPath(with: "a/b/c")).getValue() == [1, 2])
  }

  @Test func changesBelowExistingNodesReachTheRoot() {
    let tree = FTree<Int>()
    tree.subTree(FPath(with: "a/b")).setValue(1)
    tree.subTree(FPath(with: "a/c/d")).setValue(2)
    #expect(tree.subTree(FPath(with: "a/b")).getValue() == 1)
    #expect(tree.subTree(FPath(with: "a/c/d")).getValue() == 2)
    var children: [String] = []
    tree.subTree(FPath(with: "a")).forEachChild { children.append($0.name) }
    #expect(children.sorted() == ["b", "c"])
  }

  @Test func clearingRemovesEmptyNodes() {
    let tree = FTree<Int>()
    tree.subTree(FPath(with: "a/b")).setValue(1)
    tree.subTree(FPath(with: "a/c")).setValue(2)
    tree.subTree(FPath(with: "a/b")).setValue(nil)
    #expect(tree.subTree(FPath(with: "a/b")).getValue() == nil)
    #expect(tree.subTree(FPath(with: "a/c")).getValue() == 2)
    tree.subTree(FPath(with: "a/c")).setValue(nil)
    #expect(tree.isEmpty)
  }
}
