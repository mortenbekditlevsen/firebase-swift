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

/// FNodeDecoder against FirebaseDataDecoder on `val()` (the path before it).
struct FNodeDecoderTests {
    private func decodeBothWays<T: Decodable>(_ type: T.Type, _ node: FNode,
                                              _ decoder: FirebaseDataDecoder = .init()) -> (new: Result<T, any Error>,
                                                                                            old: Result<T, any Error>) {
        (Result { try FNodeDecoder(decoder).decode(type, from: node) },
         Result { try decoder.decode(type, from: node.val()) })
    }

    // The old path's NSNumbers bridge to Bool differently on Linux.
    #if canImport(Darwin)
    @Test func randomTreesDecodeAsBefore() throws {
        var random = SeededRandom(seed: 0xC0DE)
        for _ in 0 ..< 500 {
            let node = FSnapshotUtilities.nodeFrom(randomJSON(depth: 0, using: &random))
            let (new, old) = decodeBothWays(AnyJSON.self, node)
            switch (new, old) {
            case let (.success(new), .success(old)):
                #expect(new == old, "\(node.val())")
            case (.failure, .failure):
                break
            default:
                Issue.record("\(node): \(new) vs \(old)")
            }
        }
    }
    #endif

    @Test func randomModelsDecodeAsBefore() throws {
        var random = SeededRandom(seed: 0x5EED)
        for _ in 0 ..< 200 {
            let model = Model.random(using: &random)
            let node = FSnapshotUtilities.nodeFrom(try FirebaseDataEncoder().encode(model))
            let (new, old) = decodeBothWays(Model.self, node)
            #expect(try new.get() == model)
            #if canImport(Darwin)
            #expect(try old.get() == model)
            #endif
        }
    }

    @Test func dictionariesOfModels() throws {
        let models = ["-Kf1": Model(name: "a", count: 1), "-Kf2": Model(name: "b", count: 2, tags: ["x"])]
        let node = FSnapshotUtilities.nodeFrom(try FirebaseDataEncoder().encode(models))
        #expect(try FNodeDecoder(.init()).decode([String: Model].self, from: node) == models)
    }

    @Test func sparseArraysHaveNils() throws {
        let node = FSnapshotUtilities.nodeFrom(["0": "a", "2": "c"])
        let (new, old) = decodeBothWays([String?].self, node)
        #expect(try new.get() == ["a", nil, "c"])
        #expect(try old.get() == ["a", nil, "c"])
        // Too sparse to be an array.
        let sparse = FSnapshotUtilities.nodeFrom(["0": "a", "5": "f"])
        #expect(throws: DecodingError.self) { try FNodeDecoder(.init()).decode([String?].self, from: sparse) }
        #expect(try FNodeDecoder(.init()).decode([String: String].self, from: sparse) == ["0": "a", "5": "f"])
    }

    @Test func integerKeysDecodeAsDictionariesToo() throws {
        // Unlike before, where `val()` made an array of them.
        let node = FSnapshotUtilities.nodeFrom(["0": "a", "1": "b"])
        #expect(try FNodeDecoder(.init()).decode([String: String].self, from: node) == ["0": "a", "1": "b"])
        #expect(try FNodeDecoder(.init()).decode([String].self, from: node) == ["a", "b"])
        #expect(throws: DecodingError.self) { try FirebaseDataDecoder().decode([String: String].self, from: node.val()) }
    }

    @Test func numbersMustFit() throws {
        let decoder = FNodeDecoder(.init())
        #expect(throws: DecodingError.self) { try decoder.decode(Int8.self, from: .leaf(.int64(300))) }
        #expect(throws: DecodingError.self) { try decoder.decode(Int.self, from: .leaf(.double(1.5))) }
        #expect(throws: DecodingError.self) { try decoder.decode(UInt.self, from: .leaf(.int64(-1))) }
        #expect(throws: DecodingError.self) { try decoder.decode(Float.self, from: .leaf(.double(1e300))) }
        #expect(try decoder.decode(Int.self, from: .leaf(.double(2))) == 2)
        #expect(try decoder.decode(Double.self, from: .leaf(.int64(3))) == 3)
        #expect(try decoder.decode(Int64.self, from: .leaf(.int64(.max))) == .max)
        // As on Darwin, 0 and 1 are Booleans too; Booleans aren't numbers.
        #expect(try decoder.decode(Bool.self, from: .leaf(.int64(1))) == true)
        #expect(throws: DecodingError.self) { try decoder.decode(Int.self, from: .leaf(.bool(true))) }
    }

    @Test func missingAndNullValues() throws {
        let decoder = FNodeDecoder(.init())
        #expect(try decoder.decode(Int?.self, from: .empty) == nil)
        #expect(throws: DecodingError.self) { try decoder.decode(Int.self, from: .empty) }
        let node = FSnapshotUtilities.nodeFrom(["name": "x"])
        do {
            _ = try decoder.decode(Model.self, from: node)
            Issue.record("decoded without a count")
        } catch DecodingError.keyNotFound(let key, _) {
            #expect(key.stringValue == "count")
        }
    }

    @Test func errorsHaveTheirCodingPath() {
        let node = FSnapshotUtilities.nodeFrom(["a": ["name": "x", "count": "many"]])
        do {
            _ = try FNodeDecoder(.init()).decode([String: Model].self, from: node)
            Issue.record("decoded a string as a count")
        } catch DecodingError.typeMismatch(_, let context) {
            #expect(context.codingPath.map(\.stringValue) == ["a", "count"])
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func keyStrategies() throws {
        struct Keys: Decodable, Equatable {
            var firstName: String
            var lastName: String
        }
        let decoder = FirebaseDataDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let node = FSnapshotUtilities.nodeFrom(["first_name": "Ada", "last_name": "Lovelace"])
        let (new, old) = decodeBothWays(Keys.self, node, decoder)
        #expect(try new.get() == Keys(firstName: "Ada", lastName: "Lovelace"))
        #expect(try old.get() == new.get())

        decoder.keyDecodingStrategy = .custom { path in
            FCodingKey(path.last!.stringValue.replacingOccurrences(of: "_name", with: "Name"))
        }
        #expect(try FNodeDecoder(decoder).decode(Keys.self, from: node) == Keys(firstName: "Ada", lastName: "Lovelace"))
    }

    @Test func dateAndDataStrategies() throws {
        let decoder = FirebaseDataDecoder()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(FirebaseDataDecoder.DateDecodingStrategy, FNode)] = [
            (.secondsSince1970, .leaf(.int64(1_700_000_000))),
            (.millisecondsSince1970, .leaf(.int64(1_700_000_000_000))),
            (.iso8601, .leaf(.string("2023-11-14T22:13:20Z"))),
            (.deferredToDate, .leaf(.double(date.timeIntervalSinceReferenceDate))),
        ]
        for (strategy, node) in cases {
            decoder.dateDecodingStrategy = strategy
            let (new, old) = decodeBothWays(Date.self, node, decoder)
            #expect(try new.get() == date)
            #expect(try old.get() == date)
        }
        let data = Data("bytes".utf8)
        let (new, old) = decodeBothWays(Data.self, .leaf(.string(data.base64EncodedString())), decoder)
        #expect(try new.get() == data)
        #expect(try old.get() == data)

        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf",
                                                                        nan: "nan")
        #expect(try FNodeDecoder(decoder).decode(Double.self, from: .leaf(.string("-inf"))) == -.infinity)
    }

    @Test func serverTimestamps() throws {
        struct Stamped: Decodable {
            @ServerTimestamp var at: Date?
        }
        let node = FSnapshotUtilities.nodeFrom(["at": 1_700_000_000_000])
        let stamped = try FNodeDecoder(.init()).decode(Stamped.self, from: node)
        #expect(stamped.at == Date(timeIntervalSince1970: 1_700_000_000))
    }
}

// MARK: - Models

/// Any JSON, decoded by trying each type in turn.
private enum AnyJSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AnyJSON].self))
        }
    }
}

private struct Model: Codable, Equatable {
    struct Nested: Codable, Equatable {
        var level: Int8
        var weights: [Double]
    }

    var name: String
    var count: Int
    var ratio: Double = 0.5
    var flag: Bool = false
    var tags: [String]?
    var nested: Nested?
    var scores: [String: Int]?
    var maybe: UInt32?

    static func random(using random: inout SeededRandom) -> Model {
        func maybe<T>(_ make: () -> T) -> T? {
            Bool.random(using: &random) ? make() : nil
        }
        return Model(
            name: ["", "x", "æ😀", "quote\"d"].randomElement(using: &random)!,
            count: Int.random(in: -1_000_000 ... 1_000_000, using: &random),
            ratio: Double(Int.random(in: -1000 ... 1000, using: &random)) / 8,
            flag: Bool.random(using: &random),
            tags: maybe { (0 ..< Int.random(in: 1 ..< 4, using: &random)).map { "t\($0)" } },
            nested: maybe { Nested(level: Int8.random(in: .min ... .max, using: &random), weights: [1, 2.5]) },
            scores: maybe { ["a": 1, "b_c": Int.random(in: 0 ..< 100, using: &random)] },
            maybe: maybe { UInt32.random(in: 0 ... .max, using: &random) }
        )
    }
}
