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
import Foundation
import Testing

struct MutableDataTests {
  private func data(_ value: Any?) -> MutableData {
    MutableData(node: FSnapshotUtilities.nodeFrom(value))
  }

  @Test func readsValuesAndChildren() {
    let data = data(["a": 1, "b": ["c": "deep"]])
    #expect(data.key == nil)
    #expect(data.hasChildren())
    #expect(data.childrenCount == 2)
    #expect(data.hasChild(atPath: "b/c"))
    #expect(!data.hasChild(atPath: "b/d"))
    #expect(data.childData(byAppendingPath: "b/c").value as? String == "deep")
    #expect(data.childData(byAppendingPath: "b/c").key == "c")
    #expect(data.children.map(\.key) == ["a", "b"])
  }

  @Test func settingTheValueReplacesTheData() {
    var data = data(["a": 1])
    data.value = 5
    #expect((data.value as? NSNumber)?.intValue == 5)
    #expect(!data.hasChildren())
    data.value = nil
    #expect(data.value == nil || data.value is NSNull)
  }

  @Test func childPathSubscriptWritesThrough() {
    var data = data(["a": 1])
    data[childPath: "b/c"].value = "new"
    data[childPath: "a"].value = 2
    #expect(data.childData(byAppendingPath: "b/c").value as? String == "new")
    #expect((data.childData(byAppendingPath: "a").value as? NSNumber)?.intValue == 2)
  }

  @Test func copiesAreIndependent() {
    let original = data(["a": 1])
    var child = original.childData(byAppendingPath: "a")
    child.value = 99
    var copy = original
    copy.value = "changed"
    #expect((original.childData(byAppendingPath: "a").value as? NSNumber)?.intValue == 1)
    #expect((child.value as? NSNumber)?.intValue == 99)
  }

  @Test func prioritiesAreKeptWithTheData() {
    var data = data("x")
    data.priority = 3
    #expect((data.priority as? NSNumber)?.intValue == 3)
    #expect(data.value as? String == "x")
  }
}
