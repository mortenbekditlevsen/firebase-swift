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

/// Integers are kept as 64-bit integers, doubles as doubles (as upstream and
/// Android), and the two behave as one number type.
struct LeafNumberTests {
  private let big: Int64 = 9_007_199_254_740_993 // 2^53 + 1: not a double

  @Test func integersAndDoublesKeepTheirKind() {
    #expect(NODE(5).type == .leaf(.int64(5)))
    #expect(NODE(Int64.max).type == .leaf(.int64(.max)))
    #expect(NODE(2.5).type == .leaf(.double(2.5)))
    #expect(NODE(5.0) == NODE(5))
    // Beyond Int64: a double, as upstream's canBeRepresentedAsLong.
    #expect(NODE(UInt64.max).type == .leaf(.double(Double(UInt64.max))))
    #expect(NODE(true).type == .leaf(.bool(true)))
  }

  @Test func largeIntegersStayExact() {
    let node = NODE(big)
    #expect((node.val() as? NSNumber)?.int64Value == big)
    #expect(node != NODE(big - 1))
    #expect(node.compare(NODE(big - 1)) == .orderedDescending)
    // The closest double is 2^53, which is smaller.
    #expect(node.compare(NODE(Double(big))) == .orderedDescending)
    #expect(NODE(Double(big)).compare(node) == .orderedAscending)
  }

  @Test func integersAndDoublesAreOrderedTogether() {
    #expect(NODE(1).compare(NODE(1.5)) == .orderedAscending)
    #expect(NODE(2.5).compare(NODE(2)) == .orderedDescending)
    #expect(NODE(3).compare(NODE(3.0)) == .orderedSame)
    #expect(NODE(-1).compare(NODE("a")) == .orderedAscending)
    #expect(NODE(true).compare(NODE(0)) == .orderedAscending)
  }

  @Test func equalNumbersHashAlike() {
    #expect(NODE(7).hashValue == NODE(7.0).hashValue)
    #expect(Set([NODE(7), NODE(7.0)]).count == 1)
  }

  @Test func dataHashIsTheDoublesHash() {
    // The server hashes numbers as doubles, so an integer and the same double
    // must hash alike (upstream and Android do the same).
    #expect(NODE(4).dataHash() == NODE(4.0).dataHash())
    #expect(NODE(4).dataHash() == "eVih19a6ZDz3NL32uVBtg9KSgQY=")
  }

  @Test func integerIncrementsAddUpToIntegers() {
    let serverValues = ServerValues(timestamp: 0)
    func increment(_ existing: Any?, by delta: Any) -> FNode {
      FServerValues.resolveDeferredValueSnapshot(
        NODE([".sv": ["increment": delta]]),
        withExisting: NODE(existing),
        serverValues: serverValues
      )
    }

    #expect(increment(big, by: 1).type == .leaf(.int64(big + 1)))
    #expect(increment(1.5, by: 1).type == .leaf(.double(2.5)))
    #expect(increment(1, by: 0.5).type == .leaf(.double(1.5)))
    // Overflowing integers add up as doubles.
    #expect(increment(Int64.max, by: 1).type == .leaf(.double(Double(Int64.max) + 1)))
    // Incrementing a non-number sets the increment.
    #expect(increment("text", by: 3).type == .leaf(.int64(3)))
  }

  @Test func timestampsAreIntegers() {
    let serverValues = FServerValues.generateServerValues(FSystemClock.clock)
    let resolved = FServerValues.resolveDeferredValueSnapshot(
      NODE([".sv": "timestamp"]), withExisting: nil, serverValues: serverValues
    )
    #expect(resolved.type == .leaf(.int64(serverValues.timestamp)))
  }
}
