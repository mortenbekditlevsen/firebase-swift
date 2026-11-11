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

import Foundation
import NIOCore

/// Malformed JSON, at a byte offset.
struct FJSONError: Error, CustomStringConvertible {
    enum Reason {
        case unexpectedEnd
        case unexpectedByte(UInt8)
        case invalidNumber
        case invalidEscape
        case tooDeep
        case invalidServerValue
        case trailingData
    }

    let reason: Reason
    let offset: Int

    var description: String { "Invalid JSON at byte \(offset): \(reason)" }
}

/// Reads JSON from UTF-8 bytes, without building Foundation objects: the
/// values go straight to what they're for (`FNode`s, see `readNode()`).
///
/// Unlike strict JSON, it accepts control characters in strings.
///
/// It borrows the bytes, so it can't outlive them; use `withScanner`.
struct FJSONScanner: ~Escapable {
    let bytes: Span<UInt8>
    private(set) var offset = 0

    @_lifetime(copy bytes)
    init(_ bytes: Span<UInt8>) {
        self.bytes = bytes
    }

    /// Runs `body` with a scanner over `buffer`'s readable bytes.
    static func withScanner<Result>(_ buffer: ByteBuffer,
                                    _ body: (inout FJSONScanner) throws -> Result) throws -> Result {
        try buffer.withUnsafeReadableBytes { raw in
            var scanner = FJSONScanner(unsafe Span(_unsafeBytes: raw))
            return try body(&scanner)
        }
    }

    /// Runs `body` with a scanner over `bytes`.
    static func withScanner<Result>(_ bytes: some ContiguousBytes,
                                    _ body: (inout FJSONScanner) throws -> Result) throws -> Result {
        try bytes.withUnsafeBytes { raw in
            var scanner = FJSONScanner(unsafe Span(_unsafeBytes: raw))
            return try body(&scanner)
        }
    }

    func error(_ reason: FJSONError.Reason) -> FJSONError {
        FJSONError(reason: reason, offset: offset)
    }

    // MARK: Bytes

    mutating func skipWhitespace() {
        while offset < bytes.count {
            switch bytes[offset] {
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                offset += 1
            default:
                return
            }
        }
    }

    /// The next byte that isn't whitespace, without consuming it.
    mutating func peek() throws -> UInt8 {
        skipWhitespace()
        guard offset < bytes.count else { throw error(.unexpectedEnd) }
        return bytes[offset]
    }

    mutating func expect(_ byte: UInt8) throws {
        let next = try peek()
        guard next == byte else { throw error(.unexpectedByte(next)) }
        offset += 1
    }

    /// Checks that only whitespace follows.
    mutating func expectEnd() throws {
        skipWhitespace()
        guard offset == bytes.count else { throw error(.trailingData) }
    }

    // MARK: Containers

    /// Starts reading an object's members.
    mutating func beginObject() throws {
        try expect(UInt8(ascii: "{"))
    }

    /// The next member's key, with the scanner at its value, or nil after the
    /// object's end. `first` is true before the first member.
    mutating func nextKey(_ first: inout Bool) throws -> String? {
        var next = try peek()
        if next == UInt8(ascii: "}") {
            offset += 1
            return nil
        }
        if !first {
            guard next == UInt8(ascii: ",") else { throw error(.unexpectedByte(next)) }
            offset += 1
            next = try peek()
        }
        first = false
        guard next == UInt8(ascii: "\"") else { throw error(.unexpectedByte(next)) }
        let key = try readString()
        try expect(UInt8(ascii: ":"))
        return key
    }

    /// Starts reading an array's elements.
    mutating func beginArray() throws {
        try expect(UInt8(ascii: "["))
    }

    /// Whether there's another element, with the scanner at it; false after
    /// the array's end. `first` is true before the first element.
    mutating func nextElement(_ first: inout Bool) throws -> Bool {
        let next = try peek()
        if next == UInt8(ascii: "]") {
            offset += 1
            return false
        }
        if !first {
            guard next == UInt8(ascii: ",") else { throw error(.unexpectedByte(next)) }
            offset += 1
        }
        first = false
        return true
    }

    // MARK: Scalars

    /// Reads `null`, returning true, or returns false if the value is something else.
    mutating func readNull() throws -> Bool {
        guard try peek() == UInt8(ascii: "n") else { return false }
        try readLiteral("null")
        return true
    }

    mutating func readBool() throws -> Bool {
        switch try peek() {
        case UInt8(ascii: "t"):
            try readLiteral("true")
            return true
        case UInt8(ascii: "f"):
            try readLiteral("false")
            return false
        case let byte:
            throw error(.unexpectedByte(byte))
        }
    }

    private mutating func readLiteral(_ literal: StaticString) throws {
        let count = literal.utf8CodeUnitCount
        guard offset + count <= bytes.count else { throw error(.unexpectedEnd) }
        for i in 0 ..< count where bytes[offset + i] != literal.utf8Start[i] {
            throw error(.unexpectedByte(bytes[offset + i]))
        }
        offset += count
    }

    /// Reads a string; the scanner must be at its opening quote.
    mutating func readString() throws -> String {
        try expect(UInt8(ascii: "\""))
        let start = offset
        // The fast path: no escapes. (memchr, as strings can be megabytes.)
        guard let end = firstIndex(of: UInt8(ascii: "\""), from: start) else { throw error(.unexpectedEnd) }
        guard let escape = firstIndex(of: UInt8(ascii: "\\"), from: start, to: end) else {
            offset = end + 1
            return string(start ..< end)
        }
        offset = escape
        var utf8: [UInt8] = []
        utf8.reserveCapacity(offset - start + 16)
        for i in start ..< offset {
            utf8.append(bytes[i])
        }
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: utf8, as: UTF8.self)
            case UInt8(ascii: "\\"):
                try readEscape(into: &utf8)
            default:
                utf8.append(byte)
            }
        }
        throw error(.unexpectedEnd)
    }

    /// The index of the first `byte` from `start` (to `end`), if any.
    private func firstIndex(of byte: UInt8, from start: Int, to end: Int? = nil) -> Int? {
        let end = end ?? bytes.count
        guard start < end else { return nil }
        return unsafe bytes.withUnsafeBufferPointer { buffer in
            let base = unsafe buffer.baseAddress!
            guard let found = unsafe memchr(base + start, Int32(byte), end - start) else { return nil }
            return unsafe found.assumingMemoryBound(to: UInt8.self) - base
        }
    }

    /// The bytes in `range` as a string (invalid UTF-8 is repaired).
    private func string(_ range: Range<Int>) -> String {
        unsafe bytes.withUnsafeBufferPointer { buffer in
            unsafe String(decoding: UnsafeBufferPointer(rebasing: buffer[range]), as: UTF8.self)
        }
    }

    private mutating func readEscape(into utf8: inout [UInt8]) throws {
        guard offset < bytes.count else { throw error(.unexpectedEnd) }
        let byte = bytes[offset]
        offset += 1
        switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): utf8.append(byte)
        case UInt8(ascii: "b"): utf8.append(0x08)
        case UInt8(ascii: "f"): utf8.append(0x0C)
        case UInt8(ascii: "n"): utf8.append(0x0A)
        case UInt8(ascii: "r"): utf8.append(0x0D)
        case UInt8(ascii: "t"): utf8.append(0x09)
        case UInt8(ascii: "u"):
            var scalar = UInt32(try readHex4())
            if (0xD800 ..< 0xDC00).contains(scalar) {
                // A high surrogate; a low one should follow.
                if offset + 6 <= bytes.count, bytes[offset] == UInt8(ascii: "\\"),
                   bytes[offset + 1] == UInt8(ascii: "u") {
                    let saved = offset
                    offset += 2
                    let low = UInt32(try readHex4())
                    if (0xDC00 ..< 0xE000).contains(low) {
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    } else {
                        offset = saved
                    }
                }
            }
            utf8.append(contentsOf: Unicode.UTF8.encode(Unicode.Scalar(scalar) ?? "\u{FFFD}")!)
        default:
            offset -= 1
            throw error(.invalidEscape)
        }
    }

    private mutating func readHex4() throws -> UInt16 {
        guard offset + 4 <= bytes.count else { throw error(.unexpectedEnd) }
        var value: UInt16 = 0
        for _ in 0 ..< 4 {
            let byte = bytes[offset]
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0") ... UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a") ... UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A") ... UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw error(.invalidEscape)
            }
            value = value << 4 | UInt16(digit)
            offset += 1
        }
        return value
    }

    /// Reads a number: `.int64` for an integer literal that fits, else `.double`
    /// (as `LeafValue.number` makes them from JSONSerialization's numbers).
    mutating func readNumber() throws -> LeafValue {
        skipWhitespace()
        let start = offset
        var negative = false
        if offset < bytes.count, bytes[offset] == UInt8(ascii: "-") {
            negative = true
            offset += 1
        }
        // The integer part, accumulated as a negative number so Int64.min fits.
        var value: Int64 = 0
        var overflow = false
        let digitsStart = offset
        while offset < bytes.count, case let byte = bytes[offset],
              byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
            let (times10, o1) = value.multipliedReportingOverflow(by: 10)
            let (next, o2) = times10.subtractingReportingOverflow(Int64(byte - UInt8(ascii: "0")))
            overflow = overflow || o1 || o2
            value = next
            offset += 1
        }
        let digits = offset - digitsStart
        guard digits > 0 else { throw error(.invalidNumber) }
        guard digits == 1 || bytes[digitsStart] != UInt8(ascii: "0") else { throw error(.invalidNumber) }
        var isInteger = true
        if offset < bytes.count, bytes[offset] == UInt8(ascii: ".") {
            isInteger = false
            offset += 1
            try skipDigits()
        }
        if offset < bytes.count, bytes[offset] | 0x20 == UInt8(ascii: "e") {
            isInteger = false
            offset += 1
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "+") || bytes[offset] == UInt8(ascii: "-") {
                offset += 1
            }
            try skipDigits()
        }
        if isInteger && !overflow {
            if negative { return .int64(value) }
            if value != .min { return .int64(-value) }
        }
        guard let double = Double(string(start ..< offset)) else { throw error(.invalidNumber) }
        return .double(double)
    }

    private mutating func skipDigits() throws {
        let start = offset
        while offset < bytes.count, bytes[offset] >= UInt8(ascii: "0"), bytes[offset] <= UInt8(ascii: "9") {
            offset += 1
        }
        guard offset > start else { throw error(.invalidNumber) }
    }

    // MARK: Skipping

    /// Skips a value, checking only its brackets and strings.
    mutating func skipValue() throws {
        var depth = 0
        repeat {
            let byte = try peek()
            switch byte {
            case UInt8(ascii: "\""):
                offset += 1
                while true {
                    guard offset < bytes.count else { throw error(.unexpectedEnd) }
                    let byte = bytes[offset]
                    offset += 1
                    if byte == UInt8(ascii: "\"") { break }
                    if byte == UInt8(ascii: "\\") { offset += 1 }
                }
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                offset += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                guard depth >= 0 else { throw error(.unexpectedByte(byte)) }
                offset += 1
            default:
                // A scalar, or a comma or colon inside a container.
                offset += 1
                while offset < bytes.count, !isDelimiter(bytes[offset]) {
                    offset += 1
                }
            }
        } while depth > 0
    }

    private func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: ","), UInt8(ascii: ":"), UInt8(ascii: "\""), UInt8(ascii: "{"), UInt8(ascii: "}"),
             UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
             UInt8(ascii: "\t"):
            true
        default:
            false
        }
    }
}
