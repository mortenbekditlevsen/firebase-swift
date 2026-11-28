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

// firebase-swift: `data(as:)` decodes the core's values in place
// (FirestoreValueDecoder). These tests decode the same documents that way and
// as before, from `data(with:)` with Firestore.Decoder, and expect the same
// values and errors, for every kind of value against many types.

import FirebaseCore
@testable import FirebaseFirestore
import Foundation
import Testing

/// Serialized, and yielding between fields: each case decodes for a while
/// without suspending, and in parallel they held every thread of the
/// concurrency pool for seconds, so other suites' timeouts expired (on CI's
/// Linux and Android runners).
@Suite("FirestoreValueDecoder", .serialized)
struct FirestoreValueDecoderTests {
  /// One value of every kind Firestore stores, by field name.
  static let values: [String: Any] = [
    "null": NSNull(),
    "true": true,
    "false": false,
    "zero": 0,
    "one": 1,
    "two": 2,
    "minusOne": -1,
    "large": 300,
    "int64Max": Int64.max,
    "int64Min": Int64.min,
    "doubleWhole": 1.0,
    "doubleHalf": 2.5,
    "doubleNegative": -0.5,
    "doubleHuge": 1e300,
    "nan": Double.nan,
    "infinity": Double.infinity,
    "emptyString": "",
    "string": "abc",
    "unicode": "æøå 🎉",
    "isoDate": "2024-01-01T00:00:00Z",
    "url": "https://example.com/a?b=c",
    "base64": "aGVsbG8=",
    "numeric": "1",
    "infString": "inf",
    "map": ["a": 1, "b": "x", "c": NSNull()],
    "emptyMap": [String: Any](),
    "snakeMap": ["first_name": "Ada", "last_name": "Lovelace"],
    "intMap": ["x": 1, "y": 2],
    "array": [1, 2, 3],
    "arrayWithNull": ["a", NSNull(), "c"],
    "emptyArray": [Any](),
    "arrayOfMaps": [["a": 1], ["a": 2, "b": "y"]],
    "timestamp": Timestamp(seconds: 1_700_000_000, nanoseconds: 123_000_000),
    "geoPoint": GeoPoint(latitude: 55.7, longitude: 12.6),
    "blob": Data([1, 2, 3]),
    "reference": FSTTestDocRef("coll/doc"),
    "vector": VectorValue([1, 2.5]),
    "minKey": MinKey.shared,
    "maxKey": MaxKey.shared,
    "regex": RegexValue(pattern: "^a", options: "i"),
    "int32": Int32Value(7),
    "decimal128": Decimal128Value("1.5"),
    "objectId": BSONObjectId("507f191e810c19729de860ea"),
    "bsonTimestamp": BSONTimestamp(seconds: 1, increment: 2),
  ]

  /// Fields that are server timestamps not set yet, and their values before.
  static let serverTimestamps: [String: Any] = ["pendingTime": 5, "pendingTimeNew": NSNull()]

  static let behaviors: [ServerTimestampBehavior] = [.none, .estimate, .previous]

  @Test(arguments: behaviors)
  func valuesDecodeAsFromData(behavior: ServerTimestampBehavior) async throws {
    let snapshot = try await Self.snapshot()
    let fields = Array(Self.values.keys) + Array(Self.serverTimestamps.keys) + ["missing"]
    var checked = 0
    for field in fields {
      await Task.yield()
      checked += compare(Bool.self, field, snapshot, behavior)
      checked += compare(Int.self, field, snapshot, behavior)
      checked += compare(Int8.self, field, snapshot, behavior)
      checked += compare(Int16.self, field, snapshot, behavior)
      checked += compare(Int32.self, field, snapshot, behavior)
      checked += compare(Int64.self, field, snapshot, behavior)
      checked += compare(UInt.self, field, snapshot, behavior)
      checked += compare(UInt8.self, field, snapshot, behavior)
      checked += compare(UInt16.self, field, snapshot, behavior)
      checked += compare(UInt32.self, field, snapshot, behavior)
      checked += compare(UInt64.self, field, snapshot, behavior)
      checked += compare(Double.self, field, snapshot, behavior)
      checked += compare(Float.self, field, snapshot, behavior)
      checked += compare(String.self, field, snapshot, behavior)
      checked += compare(Date.self, field, snapshot, behavior)
      checked += compare(Data.self, field, snapshot, behavior)
      checked += compare(URL.self, field, snapshot, behavior)
      checked += compare(Decimal.self, field, snapshot, behavior)
      checked += compare(Timestamp.self, field, snapshot, behavior)
      checked += compare(GeoPoint.self, field, snapshot, behavior)
      checked += compare(DocumentReference.self, field, snapshot, behavior)
      checked += compare(VectorValue.self, field, snapshot, behavior)
      checked += compare(MinKey.self, field, snapshot, behavior)
      checked += compare(RegexValue.self, field, snapshot, behavior)
      checked += compare(Int32Value.self, field, snapshot, behavior)
      checked += compare(Decimal128Value.self, field, snapshot, behavior)
      checked += compare(BSONObjectId.self, field, snapshot, behavior)
      checked += compare(BSONTimestamp.self, field, snapshot, behavior)
      checked += compare([Int].self, field, snapshot, behavior)
      checked += compare([String?].self, field, snapshot, behavior)
      checked += compare([[Int]].self, field, snapshot, behavior)
      checked += compare([String: Int].self, field, snapshot, behavior)
      checked += compare([String: String?].self, field, snapshot, behavior)
      checked += compare(Nested.self, field, snapshot, behavior)
      checked += compare([Nested].self, field, snapshot, behavior)
      checked += compare(Letter.self, field, snapshot, behavior)
      checked += compare(Count.self, field, snapshot, behavior)
      checked += compare(Bool?.self, field, snapshot, behavior)
      checked += compare(Int?.self, field, snapshot, behavior)
      checked += compare(Double?.self, field, snapshot, behavior)
      checked += compare(String?.self, field, snapshot, behavior)
      checked += compare(Date?.self, field, snapshot, behavior)
      checked += compare(Timestamp?.self, field, snapshot, behavior)
      checked += compare([Int]?.self, field, snapshot, behavior)
      checked += compare(Nested?.self, field, snapshot, behavior)
    }
    #expect(checked == fields.count * 45)
  }

  /// `decodeIfPresent`, as synthesized `Decodable` reads optional properties:
  /// it asks `contains` and `decodeNil(forKey:)` first.
  @Test(arguments: behaviors)
  func optionalPropertiesDecodeAsFromData(behavior: ServerTimestampBehavior) async throws {
    let snapshot = try await Self.snapshot()
    for field in Array(Self.values.keys) + Array(Self.serverTimestamps.keys) + ["missing"] {
      await Task.yield()
      compare(Int.self, field, snapshot, behavior, ifPresent: true)
      compare(Double.self, field, snapshot, behavior, ifPresent: true)
      compare(Bool.self, field, snapshot, behavior, ifPresent: true)
      compare(String.self, field, snapshot, behavior, ifPresent: true)
      compare(Timestamp.self, field, snapshot, behavior, ifPresent: true)
      compare(Date.self, field, snapshot, behavior, ifPresent: true)
      compare([Int].self, field, snapshot, behavior, ifPresent: true)
      compare(Nested.self, field, snapshot, behavior, ifPresent: true)
    }
  }

  /// The decoder's strategies, which the in-place path takes over or passes
  /// to FirebaseDataDecoder.
  @Test(arguments: [
    Strategy.snakeCaseKeys, .customKeys, .secondsSince1970, .millisecondsSince1970, .iso8601,
    .base64Data, .floatsFromStrings,
  ])
  func strategiesDecodeAsFromData(strategy: Strategy) async throws {
    let snapshot = try await Self.snapshot()
    let decoder = strategy.decoder
    for field in Self.values.keys {
      await Task.yield()
      _ = compare(Date.self, field, snapshot, .none, decoder: decoder)
      _ = compare(Data.self, field, snapshot, .none, decoder: decoder)
      _ = compare(Double.self, field, snapshot, .none, decoder: decoder)
      _ = compare(Float.self, field, snapshot, .none, decoder: decoder)
      _ = compare(Person.self, field, snapshot, .none, decoder: decoder)
      _ = compare([String: String].self, field, snapshot, .none, decoder: decoder)
    }
  }

  /// Whole documents, with `@DocumentID` and `@ServerTimestamp`, and the
  /// errors of a document that doesn't fit.
  @Test(arguments: behaviors)
  func documentsDecodeAsFromData(behavior: ServerTimestampBehavior) async throws {
    let snapshot = try await Self.snapshot()
    _ = compareDocument(Model.self, snapshot, behavior)
    _ = compareDocument([String: Int].self, snapshot, behavior)
    _ = compareDocument(Nested.self, snapshot, behavior)
    _ = compareDocument(Int.self, snapshot, behavior)
    _ = compareDocument([Int].self, snapshot, behavior)

    // With .previous, pendingTime is its previous value, 5, which isn't a Timestamp.
    if behavior != .previous {
      let model = try snapshot.data(as: Model.self, with: behavior)
      #expect(model.id == snapshot.documentID)
      #expect(model.string == "abc")
      #expect(model.array == [1, 2, 3])
      #expect((model.pendingTime == nil) == (behavior == .none))
    }
  }

  @Test func missingDocumentsDecodeAsBefore() async throws {
    let db = try await Self.offlineFirestore()
    // Deleted first, so that the cache knows it doesn't exist.
    let document = db.document("coll/none")
    document.delete { _ in }
    let snapshot = try await document.getDocument(source: .cache)
    #expect(!snapshot.exists)
    #expect(throws: (any Error).self) { try snapshot.data(as: Model.self) }
    #expect(try snapshot.data(as: Model?.self) == nil)
  }

  // MARK: Comparing

  /// Decodes `field` as `T` both ways and expects the same outcome. Returns 1.
  @discardableResult
  private func compare<T: Decodable & Equatable>(_ type: T.Type, _ field: String,
                                                 _ snapshot: DocumentSnapshot,
                                                 _ behavior: ServerTimestampBehavior,
                                                 decoder: Firestore.Decoder = .init(),
                                                 ifPresent: Bool = false) -> Int {
    decoder.userInfo[Probe<T>.fieldKey] = field
    if ifPresent {
      let expected = outcome { try oldPath(ProbeIfPresent<T>.self, snapshot, behavior, decoder).value }
      let actual = outcome { try snapshot.data(as: ProbeIfPresent<T>.self, with: behavior, decoder: decoder).value }
      #expect(actual.matches(expected, inDictionary: false), "\(field) if present as \(T.self), \(behavior)")
      return 1
    }
    let expected = outcome { try oldPath(Probe<T>.self, snapshot, behavior, decoder).value }
    let actual = outcome { try snapshot.data(as: Probe<T>.self, with: behavior, decoder: decoder).value }
    #expect(actual.matches(expected, inDictionary: T.self is any StringKeyedDictionary.Type),
            "\(field) as \(T.self), \(behavior)")
    return 1
  }

  @discardableResult
  private func compareDocument<T: Decodable & Equatable>(_ type: T.Type, _ snapshot: DocumentSnapshot,
                                                         _ behavior: ServerTimestampBehavior) -> Int {
    let decoder = Firestore.Decoder()
    let expected = outcome { try oldPath(T.self, snapshot, behavior, decoder) }
    let actual = outcome { try snapshot.data(as: T.self, with: behavior, decoder: decoder) }
    #expect(actual.matches(expected, inDictionary: T.self is any StringKeyedDictionary.Type),
            "the document as \(T.self), \(behavior)")
    return 1
  }

  /// `data(as:)` before FirestoreValueDecoder.
  private func oldPath<T: Decodable>(_ type: T.Type, _ snapshot: DocumentSnapshot,
                                     _ behavior: ServerTimestampBehavior,
                                     _ decoder: Firestore.Decoder) throws -> T {
    let data: Any = snapshot.data(with: behavior) ?? NSNull()
    return try decoder.decode(T.self, from: data, in: snapshot.reference)
  }

  private func outcome<T: Equatable>(_ body: () throws -> T) -> Outcome<T> {
    do {
      return .value(try body())
    } catch let error as DecodingError {
      return .decodingError(Outcome<T>.describe(error))
    } catch {
      return .otherError("\(type(of: error)): \(error)")
    }
  }

  // MARK: Documents

  static func offlineFirestore() async throws -> Firestore {
    var options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
    options.projectID = "test-project"
    let app = FirebaseApp(options: options, name: "FirestoreValueDecoder-\(UUID().uuidString)")
    let db = Firestore.firestore(app: app)
    let settings = db.settings
    settings.cacheSettings = MemoryCacheSettings()
    db.settings = settings
    try await db.disableNetwork()
    return db
  }

  /// A document with `values`, and `serverTimestamps` set to
  /// `FieldValue.serverTimestamp()` after their previous values. Offline, the
  /// writes stay pending, so the server timestamps aren't set.
  static func snapshot() async throws -> DocumentSnapshot {
    let db = try await offlineFirestore()
    let document = db.document("coll/doc")
    var values = self.values
    values["reference"] = db.document("coll/other")
    for (field, previous) in serverTimestamps {
      values[field] = previous
    }
    document.setData(values) { _ in }
    document.updateData(serverTimestamps.mapValues { _ in FieldValue.serverTimestamp() }) { _ in }
    return try await document.getDocument(source: .cache)
  }
}

// MARK: - Types

/// Decodes the field named in `userInfo` as `T`, so one document serves every
/// field.
private struct Probe<T: Decodable>: Decodable {
  static var fieldKey: CodingUserInfoKey { CodingUserInfoKey(rawValue: "probeField")! }

  let value: T

  init(from decoder: any Decoder) throws {
    let field = decoder.userInfo[Self.fieldKey] as! String
    let container = try decoder.container(keyedBy: FirestoreCodingKey.self)
    value = try container.decode(T.self, forKey: FirestoreCodingKey(field))
  }
}

/// As `Probe`, with `decodeIfPresent`.
private struct ProbeIfPresent<T: Decodable & Equatable>: Decodable {
  let value: T?

  init(from decoder: any Decoder) throws {
    let field = decoder.userInfo[Probe<T>.fieldKey] as! String
    let container = try decoder.container(keyedBy: FirestoreCodingKey.self)
    value = try container.decodeIfPresent(T.self, forKey: FirestoreCodingKey(field))
  }
}

private enum Outcome<T: Equatable>: Equatable, CustomStringConvertible {
  case value(T)
  case decodingError(String)
  case otherError(String)

  static func == (lhs: Outcome, rhs: Outcome) -> Bool {
    switch (lhs, rhs) {
    case let (.value(a), .value(b)):
      // NaNs are equal here. Not by how dates print: on Linux and Android,
      // `Date.description` traps for a NaN date.
      if a == b { return true }
      if let a = a as? Date, let b = b as? Date {
        return a.timeIntervalSinceReferenceDate.isNaN && b.timeIntervalSinceReferenceDate.isNaN
      }
      return String(reflecting: a) == String(reflecting: b)
    case let (.decodingError(a), .decodingError(b)), let (.otherError(a), .otherError(b)):
      return a == b
    default:
      return false
    }
  }

  /// Equal, but where a dictionary failed, only failing too: FirebaseDataDecoder
  /// decodes `[String: Any]` in hash order, so which entry fails first, and
  /// how, isn't deterministic.
  func matches(_ other: Outcome, inDictionary: Bool) -> Bool {
    guard inDictionary, case .decodingError = self, case .decodingError = other else {
      return self == other
    }
    return true
  }

  /// The error's case and coding path; messages may differ.
  static func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
      context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: "/")
    }
    switch error {
    case let .typeMismatch(_, context): return "typeMismatch at \(path(context))"
    case let .valueNotFound(_, context): return "valueNotFound at \(path(context))"
    case let .keyNotFound(key, context): return "keyNotFound \(key.stringValue) at \(path(context))"
    case let .dataCorrupted(context): return "dataCorrupted at \(path(context))"
    @unknown default: return "\(error)"
    }
  }

  var description: String {
    switch self {
    case let .value(value as Date):
      return "value Date(timeIntervalSinceReferenceDate: \(value.timeIntervalSinceReferenceDate))"
    case let .value(value): return "value \(String(reflecting: value))"
    case let .decodingError(error): return error
    case let .otherError(error): return error
    }
  }
}

private protocol StringKeyedDictionary {}
extension Dictionary: StringKeyedDictionary where Key == String {}

private struct Nested: Codable, Equatable {
  var a: Int?
  var b: String?
}

private struct Person: Codable, Equatable {
  var firstName: String
  var lastName: String
}

private enum Letter: String, Codable, Equatable {
  case abc, x
}

private enum Count: Int, Codable, Equatable {
  case zero, one, two
}

private struct Model: Codable, Equatable {
  @DocumentID var id: String?
  var string: String
  var array: [Int]
  var map: Nested
  var timestamp: Timestamp
  var date: Date?
  var geoPoint: GeoPoint
  var reference: DocumentReference
  @ServerTimestamp var pendingTime: Timestamp?
  @ServerTimestamp var pendingTimeNew: Date?
  var optionalMissing: String?

  enum CodingKeys: String, CodingKey {
    case id, string, array, map, timestamp, geoPoint, reference, pendingTime, pendingTimeNew,
         optionalMissing
    case date = "timestamp_date"
  }
}

enum Strategy: CaseIterable, Sendable {
  case snakeCaseKeys, customKeys, secondsSince1970, millisecondsSince1970, iso8601, base64Data,
       floatsFromStrings

  var decoder: Firestore.Decoder {
    let decoder = Firestore.Decoder()
    switch self {
    case .snakeCaseKeys: decoder.keyDecodingStrategy = .convertFromSnakeCase
    case .customKeys:
      decoder.keyDecodingStrategy = .custom { path in
        FirestoreCodingKey(path.last!.stringValue.replacingOccurrences(of: "_", with: ""))
      }
    case .secondsSince1970: decoder.dateDecodingStrategy = .secondsSince1970
    case .millisecondsSince1970: decoder.dateDecodingStrategy = .millisecondsSince1970
    case .iso8601: decoder.dateDecodingStrategy = .iso8601
    case .base64Data: decoder.dataDecodingStrategy = .base64
    case .floatsFromStrings:
      decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
      )
    }
    return decoder
  }
}
