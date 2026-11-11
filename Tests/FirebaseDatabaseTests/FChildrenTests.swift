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

/// FChildren against a dictionary sorted on demand, across the switch
/// between its array and its tree.
struct FChildrenTests {
    private func leaf(_ value: Int) -> FNode { .leaf(.int64(Int64(value))) }

    private func expectMatches(_ children: FChildren, _ reference: [String: Int],
                               sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = reference.map { (KeyIndex(key: $0.key), $0.value) }.sorted { $0.0 < $1.0 }
        #expect(children.count == expected.count, sourceLocation: sourceLocation)
        #expect(children.map(\.key) == expected.map(\.0), sourceLocation: sourceLocation)
        #expect(children.map(\.value) == expected.map { leaf($0.1) }, sourceLocation: sourceLocation)
        for (offset, (key, _)) in expected.enumerated() {
            #expect(children.index(forKey: key) == offset, sourceLocation: sourceLocation)
            #expect(children[offset].key == key, sourceLocation: sourceLocation)
        }
        #expect(Array(children.reversed().map(\.key)) == expected.reversed().map(\.0), sourceLocation: sourceLocation)
    }

    @Test func randomChangesAcrossTheArrayLimit() {
        var random = SeededRandom(seed: 0xC41D)
        var children = FChildren()
        var reference: [String: Int] = [:]
        let keys = (0 ..< 80).map { $0.isMultiple(of: 3) ? "\($0)" : "k\($0)" }
        for step in 0 ..< 3000 {
            let key = keys.randomElement(using: &random)!
            // Mostly adds early on, mostly removals later, so the size goes
            // over the limit and back.
            let add = Int.random(in: 0 ..< 100, using: &random) < (step < 1500 ? 70 : 30)
            if add {
                children[KeyIndex(key: key)] = leaf(step)
                reference[key] = step
            } else {
                #expect(children.removeValue(forKey: KeyIndex(key: key)).map { $0 == leaf(reference[key]!) }
                    ?? (reference[key] == nil))
                reference[key] = nil
            }
            if step.isMultiple(of: 50) {
                expectMatches(children, reference)
            }
        }
        expectMatches(children, reference)
    }

    @Test func equalityAndHashingDontDependOnTheStorage() {
        let elements = (0 ..< 40).map { (key: KeyIndex(key: "k\($0)"), value: leaf($0)) }.sorted { $0.key < $1.key }
        let tree = FChildren(sortedKeysWithValues: elements)
        var shrunk = tree
        var array = FChildren(sortedKeysWithValues: Array(elements.prefix(10)))
        for element in elements.dropFirst(10) {
            shrunk.removeValue(forKey: element.key)
        }
        // `shrunk` went back to an array, from a tree.
        #expect(shrunk == array)
        #expect(shrunk.hashValue == array.hashValue)
        for element in elements.dropFirst(10) {
            array[element.key] = element.value
        }
        #expect(array == tree)
        #expect(array.hashValue == tree.hashValue)
    }

    @Test func copiesDontShareChanges() {
        var original: FChildren = [KeyIndex(key: "a"): leaf(1)]
        let copy = original
        original[KeyIndex(key: "b")] = leaf(2)
        #expect(copy.count == 1)
        #expect(original.count == 2)
    }
}
