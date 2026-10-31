// Copyright 2017 Google LLC
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

import Foundation
import Synchronization

let PUSH_CHARS =
    "-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"

/// The smallest and largest UTF-16 code units a key can contain.
private let MIN_KEY_CHAR: UInt16 = 0x20 // " "
private let MAX_KEY_CHAR: UInt16 = 0xFFFF

/// The longest key, in UTF-16 code units.
let MAX_KEY_LEN = 786

private let LOW_SURROGATE_PAIR_START: UInt16 = 0xDC00
private let LOW_SURROGATE_PAIR_END: UInt16 = 0xDFFF
private let HIGH_SURROGATE_PAIR_START: UInt16 = 0xD800
private let HIGH_SURROGATE_PAIR_END: UInt16 = 0xDBFF

struct FNextPushId {
    private struct State {
        var lastPushTime: Int64 = 0
        var lastRandChars = [UInt8](repeating: 0, count: 12)
    }

    /// Serializes generation: concurrent calls with the same timestamp must
    /// each increment the random part, or they'd return the same ID.
    private static let state = Mutex(State())

    static func get(_ currentTime: TimeInterval) -> String {
        state.withLock { state in
            var now = Int64(currentTime * 1000)
            let duplicateTime = now == state.lastPushTime
            state.lastPushTime = now

            var timeStampChars: String = ""
            for _ in 0 ..< 8 {
                let offset = Int(now % 64)
                let index = PUSH_CHARS.index(PUSH_CHARS.startIndex, offsetBy: offset)
                timeStampChars.append(PUSH_CHARS[index])
                now = now / 64
            }

            var id: String = String(timeStampChars.reversed())
            if !duplicateTime {
                for i in (0 ..< 12).reversed() {
                    state.lastRandChars[i] = UInt8.random(in: 0 ..< 64)
                }
            } else {
                var j = 0
                for i in (0 ..< 12).reversed() {
                    j = i
                    guard state.lastRandChars[i] == 63 else { break }
                    state.lastRandChars[i] = 0
                }
                state.lastRandChars[j] += 1
            }
            for i in 0 ..< 12 {
                let offset = Int(state.lastRandChars[i])
                let index = PUSH_CHARS.index(PUSH_CHARS.startIndex, offsetBy: offset)
                id.append(PUSH_CHARS[index])
            }
            return id
        }
    }

    /// The smallest key that sorts after `key`. Works on UTF-16 code units, as
    /// keys are compared, and skips characters that aren't valid in keys.
    static func successor(_ key: String) -> String {
        var keyAsInt: Int = 0
        if tryParseStringToInt(key, integer: &keyAsInt) {
            if keyAsInt == Int(Int32.max) {
                return String(decoding: [MIN_KEY_CHAR], as: UTF16.self)
            }
            return "\(keyAsInt + 1)"
        }
        let next = Array(key.utf16)
        if next.count < MAX_KEY_LEN {
            return key + String(decoding: [MIN_KEY_CHAR], as: UTF16.self)
        }

        guard let i = next.lastIndex(where: { $0 != MAX_KEY_CHAR }) else {
            // `successor` was called on the largest possible key, so return the
            // maxName, which sorts larger than all keys.
            return FUtilities.maxName
        }
        var plusOne = next[i] + 1
        switch plusOne {
        case 0x23, 0x24: plusOne = 0x25 // '#', '$'
        case 0x2E, 0x2F: plusOne = 0x30 // '.', '/'
        case 0x5B: plusOne = 0x5C // '['
        case 0x5D: plusOne = 0x5E // ']'
        case 0x7F: plusOne = 0x80 // del
        default: break
        }

        // Everything after `i` is MAX_KEY_CHAR and is dropped.
        var start = i
        let replacement: [UInt16]
        if plusOne == HIGH_SURROGATE_PAIR_START {
            // 0xD7FF + 1 enters the surrogate range; the next code point is
            // the lowest surrogate pair. (Upstream falls through into the
            // case below here, which also changes the preceding character.)
            replacement = [HIGH_SURROGATE_PAIR_START, LOW_SURROGATE_PAIR_START]
        } else if plusOne == LOW_SURROGATE_PAIR_END + 1, i > 0 {
            // The low half of a pair overflowed: carry into the high half, or
            // replace the highest pair with the single unit 0xE000.
            let high = next[i - 1]
            start = i - 1
            replacement = high == HIGH_SURROGATE_PAIR_END
                ? [plusOne]
                : [high + 1, LOW_SURROGATE_PAIR_START]
        } else {
            replacement = [plusOne]
        }
        return String(decoding: next[..<start] + replacement, as: UTF16.self)
    }

    /// The largest key that sorts before `key`, padded with MAX_KEY_CHAR to
    /// the maximum key length.
    static func predecessor(_ key: String) -> String {
        var keyAsInt: Int = 0
        if tryParseStringToInt(key, integer: &keyAsInt) {
            if keyAsInt == Int(Int32.min) {
                return FUtilities.minName
            }
            return "\(keyAsInt - 1)"
        }
        let next = Array(key.utf16)
        guard let last = next.last else {
            return "\(Int32.max)"
        }
        if last == MIN_KEY_CHAR {
            if next.count == 1 {
                return "\(Int32.max)"
            }
            // If the last character is the smallest possible character, then the
            // next smallest string is the prefix of `key` without it.
            return String(decoding: next.dropLast(), as: UTF16.self)
        }

        // Replace the last character with its immediate predecessor, and fill the
        // suffix of the key with MAX_KEY_CHAR. This is the lexicographically
        // largest possible key smaller than `key`.
        let i = next.count - 1
        var minusOne = last - 1
        switch minusOne {
        case 0x23, 0x24: minusOne = 0x22 // '#', '$'
        case 0x2E, 0x2F: minusOne = 0x2D // '.', '/'
        case 0x5B: minusOne = 0x5A // '['
        case 0x5D: minusOne = 0x5C // ']'
        case 0x7F: minusOne = 0x7E // del
        default: break
        }

        var start = i
        let replacement: [UInt16]
        if minusOne == LOW_SURROGATE_PAIR_END {
            // 0xE000 - 1 is the highest surrogate pair.
            replacement = [HIGH_SURROGATE_PAIR_END, LOW_SURROGATE_PAIR_END]
        } else if minusOne == HIGH_SURROGATE_PAIR_END, i > 0 {
            // The low half of a pair underflowed: borrow from the high half,
            // or replace the lowest pair with the single unit 0xD7FF.
            let high = next[i - 1]
            start = i - 1
            replacement = high == HIGH_SURROGATE_PAIR_START
                ? [HIGH_SURROGATE_PAIR_START - 1]
                : [high - 1, LOW_SURROGATE_PAIR_END]
        } else {
            replacement = [minusOne]
        }
        var result = next[..<start] + replacement
        if result.count < MAX_KEY_LEN {
            result += [UInt16](repeating: MAX_KEY_CHAR, count: MAX_KEY_LEN - result.count)
        }
        return String(decoding: result, as: UTF16.self)
    }
}
