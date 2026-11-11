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
import FirebaseShared
import Foundation
import Testing

/// FNodeEncoder against FirebaseDataEncoder and `nodeFrom` (the path before it).
struct FNodeEncoderTests {
    private func encodeBothWays<T: Encodable>(_ value: T, _ encoder: FirebaseDataEncoder = .init()) throws
        -> (new: FNode, old: FNode) {
        (try FNodeEncoder(encoder).encode(value), FSnapshotUtilities.nodeFrom(try encoder.encode(value)))
    }

    @Test func randomModelsEncodeAsBefore() throws {
        var random = SeededRandom(seed: 0xE4C0)
        for _ in 0 ..< 200 {
            let model = EncodedModel.random(using: &random)
            let (new, old) = try encodeBothWays(model)
            #expect(new == old, "\(old.val())")
            #expect(try FNodeDecoder(.init()).decode(EncodedModel.self, from: new) == model)
        }
    }

    @Test func randomTreesEncodeAsBefore() throws {
        var random = SeededRandom(seed: 0x7EE5)
        for _ in 0 ..< 300 {
            let node = FSnapshotUtilities.nodeFrom(randomJSON(depth: 0, using: &random))
            guard !node.isEmpty else { continue }
            // Through a Codable value: any JSON, decoded and encoded again.
            let json = try FNodeDecoder(.init()).decode(JSONValue.self, from: node)
            let (new, old) = try encodeBothWays(json)
            #expect(new == old, "\(node.val())")
        }
    }

    @Test func strategies() throws {
        struct Dated: Encodable {
            var createdAt: Date
            var blob: Data
            var ratio: Double
        }
        let value = Dated(createdAt: Date(timeIntervalSince1970: 1_700_000_000), blob: Data("x".utf8), ratio: .infinity)
        let encoder = FirebaseDataEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                      nan: "nan")
        for strategy: FirebaseDataEncoder.DateEncodingStrategy in [.deferredToDate, .secondsSince1970,
                                                                   .millisecondsSince1970, .iso8601] {
            encoder.dateEncodingStrategy = strategy
            let (new, old) = try encodeBothWays(value, encoder)
            #expect(new == old)
            #expect(new.hasChild("created_at"))
        }
        encoder.nonConformingFloatEncodingStrategy = .throw
        #expect(throws: EncodingError.self) { try FNodeEncoder(encoder).encode(value) }
    }

    @Test func serverTimestampsAreServerValues() throws {
        struct Stamped: Encodable {
            @ServerTimestamp var at: Date?
        }
        let node = try FNodeEncoder(.init()).encode(Stamped(at: nil))
        #expect(node.getImmediateChild("at").type == .leaf(.deferredValue(.timestamp)))
        let set = try FNodeEncoder(.init()).encode(Stamped(at: Date(timeIntervalSince1970: 1)))
        #expect(set.getImmediateChild("at").type == .leaf(.int64(1000)))
    }

    @Test func priorityAndValueKeys() throws {
        let (new, old) = try encodeBothWays([
            "a": ["x": JSONValue.int(1), ".priority": .int(2)],
            "b": [".value": JSONValue.string("v"), ".priority": .string("p")],
        ])
        #expect(new == old)
        #expect(new.getImmediateChild("a").getPriority().type == .leaf(.int64(2)))
    }

    @Test func nullsAndEmptiesAreDropped() throws {
        struct Sparse: Encodable {
            var a: Int? = nil
            var b: [String] = []
            var c: [String: Int] = [:]
            var d = 1

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeNil(forKey: .a)
                try container.encode(b, forKey: .b)
                try container.encode(c, forKey: .c)
                try container.encode(d, forKey: .d)
            }

            enum CodingKeys: CodingKey { case a, b, c, d }
        }
        let (new, old) = try encodeBothWays(Sparse())
        #expect(new == old)
        #expect(new.numChildren() == 1)
        #expect(try FNodeEncoder(.init()).encode([String: Int]()) == .empty)
    }

    @Test func invalidDataThrows() {
        let encoder = FNodeEncoder(.init())
        #expect(throws: EncodingError.self) { try encoder.encode(["a.b": 1]) }
        #expect(throws: EncodingError.self) { try encoder.encode(["": 1]) }
        #expect(throws: EncodingError.self) { try encoder.encode(["x": Double.nan]) }
        #expect(throws: EncodingError.self) { try encoder.encode(["x": [".sv": "timestamp", "y": "z"]]) }
        let blob = FirebaseDataEncoder()
        blob.dataEncodingStrategy = .blob
        #expect(throws: EncodingError.self) { try FNodeEncoder(blob).encode(Data()) }
    }

    @Test func superEncodersAndBigIntegers() throws {
        class Base: Encodable {
            var base = "b"
        }
        final class Derived: Base {
            var derived = UInt64.max

            override func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(derived, forKey: .derived)
                try super.encode(to: container.superEncoder())
            }

            enum CodingKeys: CodingKey { case derived }
        }
        let (new, old) = try encodeBothWays(Derived())
        #expect(new == old)
        #expect(new.getChild(FPath(with: "super/base")).type == .leaf(.string("b")))
        #expect(new.getImmediateChild("derived").type == .leaf(.double(Double(UInt64.max))))
    }
}

// MARK: - Models

/// Any JSON, as a Codable value.
private enum JSONValue: Codable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue?])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue?].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

private struct EncodedModel: Codable, Equatable {
    struct Nested: Codable, Equatable {
        var level: Int16
        var at: Date
    }

    var name: String
    var count: Int
    var ratio: Float
    var flag: Bool
    var tags: [String]?
    var nested: [Nested]
    var scores: [String: UInt8]
    var url: URL?

    static func random(using random: inout SeededRandom) -> EncodedModel {
        EncodedModel(
            name: ["", "x", "æ😀", "back\\slash"].randomElement(using: &random)!,
            count: Int.random(in: .min ... .max, using: &random),
            ratio: Float(Int.random(in: -1000 ... 1000, using: &random)) / 4,
            flag: Bool.random(using: &random),
            tags: Bool.random(using: &random) ? ["a", "b"] : nil,
            // Not empty: an empty array is no data, so it wouldn't decode.
            nested: (0 ..< Int.random(in: 1 ..< 3, using: &random)).map {
                Nested(level: Int16($0), at: Date(timeIntervalSince1970: Double($0) * 1000))
            },
            scores: ["one": UInt8.random(in: 0 ... 255, using: &random)],
            url: Bool.random(using: &random) ? URL(string: "https://example.com/a?b=c") : nil
        )
    }
}
