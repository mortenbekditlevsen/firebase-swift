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

/// `FRepo.set` resolves server values against the existing data through
/// `LazyExistingValueProvider`, which computes that data only when needed.
@Suite struct LazyExistingValueProviderTests {
    let serverValues = ServerValues(timestamp: 1_700_000_000_000)

    static let writes: [(String, FNode)] = [
        ("an increment at the root", NODE([".sv": ["increment": 2]])),
        ("nested increments", NODE(["a": [".sv": ["increment": 1]], "b": ["c": [".sv": ["increment": 0.5]], "d": 7]])),
        ("an increment as priority", NODE(["x": 1, ".priority": [".sv": ["increment": 1]]])),
        ("an increment of a missing child", NODE(["missing": ["deeper": [".sv": ["increment": 3]]]])),
        ("an increment of a string", NODE(["s": [".sv": ["increment": 1]]])),
        ("timestamps and increments", NODE(["t": [".sv": "timestamp"], "a": [".sv": ["increment": -1]]])),
    ]

    static let existing: [(String, FNode?)] = [
        ("no data", nil),
        ("a number", NODE(40)),
        ("children", NODE(["a": 10, "b": ["c": 1.5], "s": "text", ".priority": 3])),
    ]

    @Test(arguments: writes, existing)
    func resolvesAsTheExistingSnapshot(write: (String, FNode), existing: (String, FNode?)) {
        let node = write.1
        let snapshot = existing.1
        let expected = FServerValues.resolveDeferredValueSnapshot(node, withExisting: snapshot,
                                                                  serverValues: serverValues)
        let resolved = FServerValues.resolveDeferredValueSnapshot(
            node, withValueProvider: LazyExistingValueProvider { snapshot }, serverValues: serverValues
        )
        #expect(resolved == expected, "\(write.0) on \(existing.0)")
    }

    @Test func computesTheExistingDataOnlyForIncrements() {
        var computations = 0
        func resolve(_ value: [String: Any]) {
            _ = FServerValues.resolveDeferredValueSnapshot(
                NODE(value),
                withValueProvider: LazyExistingValueProvider {
                    computations += 1
                    return NODE(["a": 1, "b": 2])
                },
                serverValues: serverValues
            )
        }

        resolve(["a": 1, "b": ["c": "text"], ".priority": 5])
        resolve(["t": [".sv": "timestamp"]])
        #expect(computations == 0)

        // Once per write, however many increments it has.
        resolve(["a": [".sv": ["increment": 1]], "b": [".sv": ["increment": 1]]])
        #expect(computations == 1)
    }
}
