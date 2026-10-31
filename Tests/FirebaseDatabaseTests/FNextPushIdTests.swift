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

// Ported from upstream's FirebaseDatabase/Tests/Unit/FNextPushIdTest.m.

private let minChar = " "
private let maxChar = "\u{FFFF}"

/// `prefix` padded with `maxChar` to the maximum key length (in UTF-16).
private func padded(_ prefix: String) -> String {
  prefix + String(repeating: maxChar, count: MAX_KEY_LEN - prefix.utf16.count)
}

/// Every BMP character that isn't a surrogate, and every 256th code point
/// above it, which encodes as a surrogate pair. (Upstream tests every one;
/// that's slow in a debug build.)
private let keyCharacters: [String] = {
  // Built in parts: as one expression it's too much for Swift 6.2's type checker.
  func strings(_ codePoints: some Sequence<UInt32>) -> [String] {
    codePoints.compactMap { Unicode.Scalar($0).map(String.init) }
  }
  var result = strings(UInt32(0x20) ..< 0xD800)
  result += strings(UInt32(0xE000) ... 0xFFFF)
  result += strings(stride(from: UInt32(0x10000), through: 0x10FFFF, by: 0x100))
  return result
}()

struct FNextPushIdTests {
  @Test func successorSpecialValues() {
    #expect(FNextPushId.successor("\(Int32.max)") == minChar)
    #expect(FNextPushId.successor(String(repeating: maxChar, count: MAX_KEY_LEN))
      == FUtilities.maxName)
  }

  @Test func successorBasic() {
    #expect(FNextPushId.successor("abc") == "abc" + minChar)
    #expect(FNextPushId.successor(padded("abc")) == "abd")
    #expect(FNextPushId.successor("abc" + minChar) == "abc" + minChar + minChar)
  }

  @Test func predecessorSpecialValues() {
    #expect(FNextPushId.predecessor(minChar) == "\(Int32.max)")
    #expect(FNextPushId.predecessor("\(Int32.min)") == FUtilities.minName)
  }

  @Test func predecessorBasic() {
    #expect(FNextPushId.predecessor("abc") == padded("abb"))
    #expect(FNextPushId.predecessor("abc" + minChar) == "abc")
  }

  @Test func predecessorUnicode() {
    #expect(FNextPushId.predecessor("\u{E000}") == padded("\u{10FFFF}"))
    #expect(FNextPushId.predecessor("\u{10000}") == padded("\u{D7FF}"))
    #expect(FNextPushId.predecessor("\u{80}") == padded("\u{7E}"))
  }

  @Test func predecessorsSortBefore() {
    for key in keyCharacters where FValidation.isValidKey(key) {
      #expect(FUtilities.compareKey(key, FNextPushId.predecessor(key)) == .orderedDescending,
              "predecessor of \(key.unicodeScalars.first!.value)")
    }
  }

  @Test func successorsSortAfter() {
    for key in keyCharacters where FValidation.isValidKey(key) {
      #expect(FUtilities.compareKey(key, FNextPushId.successor(key)) == .orderedAscending,
              "successor of \(key.unicodeScalars.first!.value)")
    }
  }

  @Test func predecessorOfASurrogatePairAfterAPrefix() {
    // Upstream fixed the range rewriting the high surrogate here (#16415).
    for codePoint in stride(from: 0x10000, through: 0x10FFFF, by: 0x100) {
      let key = "abc" + String(Unicode.Scalar(codePoint)!)
      #expect(FUtilities.compareKey(key, FNextPushId.predecessor(key)) == .orderedDescending)
    }
  }

  @Test func successorOfASurrogatePairAfterAPrefix() {
    // U+107FF is D801 DFFF: the low half overflows into the high half.
    let pair = "\u{107FF}"
    let key = String(repeating: "a", count: MAX_KEY_LEN - pair.utf16.count) + pair
    let successor = FNextPushId.successor(key)
    #expect(FUtilities.compareKey(key, successor) == .orderedAscending)
    #expect(successor.hasSuffix("\u{10800}"))
  }

  @Test func successorEnteringTheSurrogateRangeKeepsThePrefix() {
    // Upstream's switch falls through here and also changes the "a".
    let key = padded("a\u{D7FF}")
    #expect(FNextPushId.successor(key) == "a\u{10000}")
  }

  @Test func concurrentPushIdsAreUniqueForTheSameTimestamp() async {
    let all = await withTaskGroup(of: String.self) { group in
      for _ in 0 ..< 1000 {
        group.addTask { FNextPushId.get(12345.0) }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    #expect(all.count == 1000)
    #expect(Set(all).count == 1000)
  }
}
