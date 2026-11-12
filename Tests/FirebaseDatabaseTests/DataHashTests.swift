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

/// The pieces of data hashes, which the server must compute identically.
struct DataHashTests {
  /// How numbers were formatted before (and upstream's `ieee754StringForNumber:`):
  /// the double's bytes, most significant first, as hex.
  private static func referenceIEEE754String(_ double: Double) -> String {
    withUnsafeBytes(of: double) { bytes in
      bytes.reversed().map { String(format: "%02x", $0) }.joined()
    }
  }

  @Test(arguments: [
    0.0, -0.0, 1, -1.5, .pi, 1e300, -2e-308, Double(Int64.max), Double(Int64.min),
    .greatestFiniteMagnitude, .leastNonzeroMagnitude, .infinity, 0.1, 42,
  ])
  func numbersAreFormattedAsTheirIEEE754Bits(_ double: Double) {
    #expect(FUtilities.ieee754String(for: double) == Self.referenceIEEE754String(double))
  }

  @Test func oneIsFormattedAsUpstreamFormatsIt() {
    #expect(FUtilities.ieee754String(for: 1) == "3ff0000000000000")
  }

  @Test func sha1MatchesKnownDigests() {
    #expect(FStringUtilities.base64EncodedSha1("") == "2jmj7l5rSw0yVb/vlWAYkK/YBwk=")
    #expect(FStringUtilities.base64EncodedSha1("abc") == "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=")
  }

  @Test(arguments: ["plain", "", "a\"b", "back\\slash", "\\\"", "æøå \"quoted\""])
  func stringsAreEscapedForTheCompoundHash(_ string: String) {
    var output = ""
    FSnapshotUtilities.appendHashV2Representation(for: string, to: &output)
    let escaped = string.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    #expect(output == "\"\(escaped)\"")
  }

  @Test func childHashesCombineAsUpstreamDoes() {
    let node = NODE(["a": 1, "b": "x"])
    let expected = FStringUtilities.base64EncodedSha1(
      ":a:\(NODE(1).dataHash()):b:\(NODE("x").dataHash())"
    )
    #expect(node.dataHash() == expected)
    #expect(NODE(1).dataHash() == FStringUtilities.base64EncodedSha1("number:3ff0000000000000"))
  }

  @Test func digestsAreEncodedAsFoundationEncodesBase64() {
    for input in (0 ..< 200).map({ "input \($0) " + String(repeating: "æ", count: $0 % 7) }) {
      var bytes = Array(input.utf8)
      let digest = FStringUtilities.sha1(bytes)
      bytes = withUnsafeBytes(of: digest) { Array($0.prefix(20)) }
      #expect(digest.base64 == Data(bytes).base64EncodedString())
    }
  }

  @Test func cachedHashesFollowChanges() {
    let node = NODE(["a": ["x": 1], "b": ["y": 2]])
    let hash = node.dataHash()
    #expect(node.dataHash() == hash)
    let changed = node.updateChild(PATH("a/x"), withNewChild: NODE(3))
    #expect(changed.dataHash() != hash)
    #expect(changed.dataHash() == NODE(["a": ["x": 3], "b": ["y": 2]]).dataHash())
    // The unchanged node keeps its hash.
    #expect(node.dataHash() == hash)
    // A priority is part of the hash.
    #expect(node.updatePriority(NODE("p")).dataHash() != hash)
  }
}
