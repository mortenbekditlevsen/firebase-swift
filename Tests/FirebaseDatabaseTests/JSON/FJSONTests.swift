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
import NIOCore
import Testing

/// The node `json` reads as.
private func node(_ json: String) throws -> FNode {
    try RawJSON(json).node()
}

/// The node JSONSerialization and `nodeFrom` make of `json` (the path before
/// FJSONScanner).
private func referenceNode(_ json: String) throws -> FNode {
    let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    return FSnapshotUtilities.nodeFrom(correctlyRounded(value))
}

/// swift-corelibs-foundation's JSONSerialization reads long
/// decimals as NSDecimalNumbers, whose `doubleValue` can be a unit in the last
/// place off (-337033.0501634184 becomes -337033.05016341835). Darwin's, and
/// FJSONScanner, round correctly, so the reference does too.
private func correctlyRounded(_ value: Any) -> Any {
    #if canImport(Darwin)
    return value
    #else
    switch value {
    case let decimal as NSDecimalNumber:
        return NSNumber(value: Double(decimal.stringValue) ?? decimal.doubleValue)
    case let dictionary as [String: Any]:
        return dictionary.mapValues(correctlyRounded)
    case let array as [Any]:
        return array.map(correctlyRounded)
    default:
        return value
    }
    #endif
}

private func json(_ node: FNode) throws -> String {
    var writer = FJSONWriter()
    try writer.write(node)
    return String(buffer: writer.buffer)
}

struct FJSONScannerTests {
    @Test(arguments: [
        "0", "-0", "1", "-1", "42", "9007199254740993", "9223372036854775807", "-9223372036854775808",
        "9223372036854775808", "18446744073709551615", "1.5", "-2.25", "0.1", "1e3", "1E-7", "2.5e+10",
        "1.7976931348623157e308", "5e-324", "123456.789", "3.0",
    ])
    func numbersReadAsJSONSerializationsDo(_ literal: String) throws {
        let leaf = try node(literal)
        #expect(leaf == (try referenceNode(literal)))
    }

    @Test func integersAreInt64sAndTheRestDoubles() throws {
        #expect(try node("9223372036854775807").type == .leaf(.int64(.max)))
        #expect(try node("-9223372036854775808").type == .leaf(.int64(.min)))
        guard case .leaf(.double(let big)) = try node("9223372036854775808").type else {
            Issue.record("not a double")
            return
        }
        #expect(big == 9_223_372_036_854_775_808)
        guard case .leaf(.double) = try node("3.0").type else {
            Issue.record("not a double")
            return
        }
    }

    @Test(arguments: ["01", "-", "1.", ".5", "1e", "+1", "--1", "0x10", "1.5.5", "nul", "tru", "[1,]", "{\"a\":}",
                      "{\"a\" 1}", "\"\\x\"", "\"unterminated", "[1 2]", "{1: 2}", "1 2"])
    func malformedJSONThrows(_ json: String) {
        #expect(throws: FJSONError.self) { try node(json) }
    }

    @Test func stringsUnescape() throws {
        let cases: [(String, String)] = [
            (#""plain""#, "plain"),
            (#""a\"b\\c\/d""#, "a\"b\\c/d"),
            (#""\b\f\n\r\t""#, "\u{8}\u{C}\n\r\t"),
            (#""\u00e6\u00F8\u00e5""#, "æøå"),
            (#""\ud83d\ude00""#, "😀"),
            (#""\ud83d""#, "\u{FFFD}"),
            ("\"æøå 😀\"", "æøå 😀"),
        ]
        for (json, expected) in cases {
            #expect(try node(json).type == .leaf(.string(expected)), "\(json)")
        }
    }

    @Test func treeRulesMatchNodeFrom() throws {
        let cases = [
            #"null"#,
            #"{}"#,
            #"{"a": null, "b": {}}"#,
            #"{"a": 1, "b": {"c": null}}"#,
            #"[1, null, 3]"#,
            #"[]"#,
            #"{"b": 2, "a": 1, "10": 3, "9": 4, "-1": 5, "01": 6}"#,
            #"{"a": 1, ".priority": 5}"#,
            #"{".value": "x", ".priority": "p"}"#,
            #"{".priority": 5}"#,
            #"{"a": {".value": true, ".priority": 1.5}}"#,
            #"{"t": {".sv": "timestamp"}, "i": {".sv": {"increment": 2}}}"#,
            #"{"a": [[1, 2], {"x": [null]}]}"#,
            #"{"nested": {"deep": {"deeper": {"deepest": "yes"}}}}"#,
        ]
        for json in cases {
            #expect(try node(json) == (try referenceNode(json)), "\(json)")
        }
    }

    @Test func duplicateKeysKeepTheLastValue() throws {
        let read = try node(#"{"b": 1, "a": 2, "b": 3}"#)
        #expect(read.getImmediateChild("b").type == .leaf(.int64(3)))
        #expect(read.numChildren() == 2)
    }

    @Test func mergesKeepNulls() throws {
        let merge = try RawJSON(#"{"a": null, "b/c": 1}"#).merge()
        #expect(merge["a"] == .empty)
        #expect(merge["b/c"]?.type == .leaf(.int64(1)))
    }

    @Test func randomJSONReadsAsJSONSerializationAndNodeFromDo() throws {
        var random = SeededRandom(seed: 0xF1DE)
        for _ in 0 ..< 300 {
            let value = randomJSON(depth: 0, using: &random)
            let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
            let text = String(decoding: data, as: UTF8.self)
            #expect(try node(text) == (try referenceNode(text)), "\(text)")
        }
    }

    @Test func theEnvelopeKeepsTheDataUnparsed() throws {
        let message = ByteBuffer(string: #"{"t":"d","d":{"r":3,"b":{"s":"ok","d":{"x":[1,{"y":"z"}]}}}}"#)
        let envelope = try FJSONScanner.withScanner(message) { scanner in
            try scanner.readFoundationValue(rawAt: ["d", "b", "d"], in: message)
        } as? [String: Any]
        let data = envelope?["d"] as? [String: Any]
        let body = data?["b"] as? [String: Any]
        #expect((data?["r"] as? NSNumber)?.intValue == 3)
        #expect(body?["s"] as? String == "ok")
        let raw = try #require(body?["d"] as? RawJSON)
        #expect(raw.description == #"{"x":[1,{"y":"z"}]}"#)
        #expect(try raw.node() == (try referenceNode(raw.description)))
    }

    @Test func skippingValues() throws {
        let json = #"{"skip": {"a": [1, "]}\"", {"b": null}], "c": true}, "keep": -1.5e3}"#
        let value = try FJSONScanner.withScanner(ByteBuffer(string: json)) { scanner -> Any? in
            try scanner.beginObject()
            var first = true
            var kept: Any?
            while let key = try scanner.nextKey(&first) {
                if key == "keep" {
                    kept = try scanner.readNumber()
                } else {
                    try scanner.skipValue()
                }
            }
            try scanner.expectEnd()
            return kept
        }
        #expect(value as? LeafValue == .double(-1500))
    }
}

struct FJSONWriterTests {
    @Test func nodesWriteInExportForm() throws {
        let cases = [
            #"{"a":1,"b":"two","c":true,"d":1.5}"#,
            #"{".value":"x",".priority":"p"}"#,
            #"{"a":{"b":1},".priority":2}"#,
            #"{"t":{".sv":"timestamp"},"i":{".sv":{"increment":-1}}}"#,
        ]
        for text in cases {
            let read = try node(text)
            let written = try json(read)
            #expect(try node(written) == read, "\(written)")
            #expect(try referenceNode(written) == read, "\(written)")
        }
    }

    @Test func stringsAreEscaped() throws {
        let text = "q\"b\\n\n\r\t\u{1}æ😀"
        let written = try json(.leaf(.string(text)))
        #expect(try JSONSerialization.jsonObject(with: Data(written.utf8), options: .fragmentsAllowed) as? String == text)
        #expect(try node(written).type == .leaf(.string(text)))
    }

    @Test func doublesRoundTrip() throws {
        for double in [0.1, -2.5, 1e-7, 1e300, 5e-324, .pi, 3.0, -0.0, 9_007_199_254_740_993.0] {
            let written = try json(.leaf(.double(double)))
            #expect(try node(written) == .leaf(.double(double)), "\(written)")
        }
        #expect(throws: FJSONWriterError.self) { try json(.leaf(.double(.nan))) }
    }

    @Test func randomNodesRoundTrip() throws {
        var random = SeededRandom(seed: 0xBEEF)
        for _ in 0 ..< 300 {
            let value = randomJSON(depth: 0, using: &random)
            let node = FSnapshotUtilities.nodeFrom(value)
            let written = try json(node)
            #expect(try FirebaseDatabaseTests.node(written) == node, "\(written)")
        }
    }

    @Test func foundationValuesWithNodes() throws {
        let message: [String: Any] = [
            "r": 1, "ok": true, "n": NSNumber(value: 2.5), "list": ["a", NSNull()],
            "d": FNode.leaf(.string("node")),
        ]
        let bytes = try FJSONWriter.bytes(message)
        let read = try JSONSerialization.jsonObject(with: Data(bytes.readableBytesView)) as? [String: Any]
        #expect((read?["r"] as? NSNumber)?.intValue == 1)
        #expect(read?["ok"] as? Bool == true)
        #expect((read?["n"] as? NSNumber)?.doubleValue == 2.5)
        #expect((read?["list"] as? [Any])?.count == 2)
        #expect(read?["d"] as? String == "node")
    }
}

struct FrameAssemblerTests {
    @Test func longMessagesSplitAtCharacterBoundariesAndReassemble() throws {
        // Multibyte characters straddling every frame boundary.
        let text = "{\"d\":\"" + String(repeating: "aæ😀", count: 12_000) + "\"}"
        let frames = FrameAssembler.frames(for: ByteBuffer(string: text))
        #expect(frames.count > 2)
        #expect(frames[0].string == "\(frames.count - 1)")
        for frame in frames.dropFirst() {
            #expect(frame.count <= kWebsocketMaxFrameSize)
            #expect(frame.withUnsafeBytes { String(validating: $0, as: UTF8.self) } != nil)
        }
        var assembler = FrameAssembler()
        var message: ByteBuffer?
        for frame in frames {
            #expect(message == nil)
            message = assembler.receive(frame)
        }
        #expect(message.map { String(buffer: $0) } == text)
    }

    @Test func shortMessagesAreOneFrame() {
        let frames = FrameAssembler.frames(for: ByteBuffer(string: "{}"))
        #expect(frames.map(\.string) == ["{}"])
    }
}

struct KeyIndexTests {
    @Test func ordersAsUpstream() {
        let ordered = [
            FUtilities.minName, "-2147483648", "-1", "0", "00", "1", "01", "2", "10", "2147483647",
            "2147483648", "A", "a", "aa", "b", "\u{FFFD}", "😀", "\u{E000}", FUtilities.maxName,
        ]
        // UTF-16 code units: U+1F600's surrogates (D83D DE00) sort before U+E000
        // and U+FFFD, unlike in UTF-8.
        let expected = [
            FUtilities.minName, "-2147483648", "-1", "0", "00", "1", "01", "2", "10", "2147483647",
            "2147483648", "A", "a", "aa", "b", "😀", "\u{E000}", "\u{FFFD}", FUtilities.maxName,
        ]
        let sorted = ordered.shuffled().sorted { KeyIndex(key: $0) < KeyIndex(key: $1) }
        #expect(sorted == expected)
        // The strings version agrees.
        #expect(ordered.shuffled().sorted { FUtilities.compareKey($0, $1) == .orderedAscending } == expected)
    }
}

// MARK: - Random JSON

/// SplitMix64, for repeatable random values.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random JSON value as Foundation objects, with the cases the tree rules
/// treat specially: nulls, empty containers, arrays, priorities, numeric and
/// unsorted keys, escapes and multibyte strings.
func randomJSON(depth: Int, using random: inout SeededRandom) -> Any {
    let keys = ["a", "b", "z", "0", "1", "2", "10", "-3", "01", "key with space", "æ", "😀", "\u{E000}",
                "-KfdA2x", ".priority"]
    let strings = ["", "x", "quote\"", "back\\slash", "new\nline", "tab\t", "æøå", "😀", "\u{1}"]
    let kind = depth >= 4 ? Int.random(in: 0 ..< 5, using: &random) : Int.random(in: 0 ..< 8, using: &random)
    switch kind {
    case 0: return NSNull()
    case 1: return Bool.random(using: &random)
    case 2: return Int.random(in: -1_000_000 ... 1_000_000, using: &random)
    case 3: return Double.random(in: -1e6 ... 1e6, using: &random)
    case 4: return strings.randomElement(using: &random)!
    case 5:
        return (0 ..< Int.random(in: 0 ..< 5, using: &random)).map { _ in
            randomJSON(depth: depth + 1, using: &random)
        }
    default:
        var object: [String: Any] = [:]
        for _ in 0 ..< Int.random(in: 0 ..< 6, using: &random) {
            let key = keys.randomElement(using: &random)!
            object[key] = key == ".priority"
                ? (Bool.random(using: &random) ? "p" as Any : 3 as Any)
                : randomJSON(depth: depth + 1, using: &random)
        }
        return object
    }
}
