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

// FirestoreBridgeEncoder against the path it replaces for writes:
// Firestore.Encoder's [String: Any], converted by toBridgeFieldValue. Every
// part of the result is compared, and errors by their kind and coding path.

import FirebaseCore
@testable import FirebaseFirestore
import Foundation
import Testing

@Suite("FirestoreBridgeEncoder")
struct FirestoreBridgeEncoderTests {
  // MARK: Values

  @Test func everyKindOfValue() async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    expectSame(Everything(reference: firestore.document("coll/doc")))
  }

  @Test(arguments: EncodingStrategy.allCases)
  func strategies(_ strategy: EncodingStrategy) async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    let encoder = strategy.encoder
    expectSame(Everything(reference: firestore.document("coll/doc")), encoder)
    expectSame(Shapes(), encoder)
    expectSame(Edge.Sub(), encoder)
    expectSame(Edge.SubOfNothing(), encoder)
    expectSame(Edge.SuperInArray(), encoder)
    expectSame(Edge.NestedContainerTwice(), encoder)
    expectSame(["first_key": ["inner_key": 1]], encoder)
    expectSame(NonConforming(), encoder)
    expectSame(Edge.UsesUserInfo(), encoder)
  }

  /// Enums with associated values, which synthesized Codable encodes with
  /// nested containers.
  @Test func nestedContainers() {
    expectSame(Shapes())
  }

  /// Subclasses, which encode their superclass with a super encoder.
  @Test func superEncoders() {
    expectSame(Edge.Sub())
    expectSame(Edge.SubOfNothing())
    expectSame(Edge.SuperInArray())
  }

  @Test func propertyWrappers() async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    expectSame(Wrapped(id: firestore.document("coll/id")))
    expectSame(Wrapped(id: nil, created: Date(timeIntervalSince1970: 5), modified: Timestamp(seconds: 6, nanoseconds: 7)))
  }

  @Test func unusualEncodes() {
    expectSame(Edge.SameKeyTwice())
    expectSame(Edge.NestedContainerTwice())
    expectSame(Edge.Empty())
    expectSame(Edge.NestedEmpty())
    expectSame(Edge.Dictionaries())
    expectSame(Edge.Integers())
    // Firestore can't store these, but encodes them.
    expectSame(Edge.NestedArrays())
  }

  /// Optionals and existentials, which are treated by the value they hold
  /// rather than by their type.
  @Test func optionalsAndExistentials() async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    expectSame(Edge.Optionals(reference: firestore.document("coll/x")))
    expectSame(Edge.Optionals(reference: nil))
    expectSame(Edge.Existentials(reference: firestore.document("coll/y")))
    // Twice, as the second time a type's treatment is remembered.
    expectSame(Edge.Optionals(reference: firestore.document("coll/x")))
    expectSame(Edge.Existentials(reference: firestore.document("coll/y")))
  }

  // MARK: Errors

  @Test func topLevelValuesThatArentDocuments() {
    expectSame(5)
    expectSame([1, 2])
    expectSame("a")
    expectSame(Int?.none)
    expectSame(Edge.EncodesNothing())
    expectSame(Timestamp(seconds: 1, nanoseconds: 0))
    expectSame(Date(timeIntervalSince1970: 1))
  }

  @Test func nonConformingFloats() {
    expectSame(NonConforming())
    expectSame(["array": [1.0, Double.infinity]])
    expectSame(["nested": ["value": -Float.infinity]])
  }

  @Test func errorsFromValuesPassThrough() {
    expectSame(Edge.Throws())
  }

  /// FirebaseDataEncoder leaves nested containers' keys out of the paths of
  /// the values in them; so does this encoder, as a custom key strategy sees
  /// them.
  @Test func pathsInNestedContainersAsBefore() {
    expectSame(Edge.NestedNaN())
    #expect(outcome { try FirestoreBridgeEncoder(Firestore.Encoder()).encode(Edge.NestedNaN()) }
      == .error("invalidValue at inner"))
  }

  // MARK: Writes

  /// The writes that take an `Encodable` store what they stored when they
  /// encoded to `[String: Any]` first.
  @Test func writesStoreAsBefore() async throws {
    let db = try await FirestoreValueDecoderTests.offlineFirestore()
    let value = Everything(reference: db.document("coll/ref"))
    let encoder = Firestore.Encoder()
    let dictionary = try encoder.encode(value)
    let before = db.collection("before"), now = db.collection("now")
    func expectSameDocument(_ id: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
      let old = try await before.document(id).getDocument(source: .cache)
      let new = try await now.document(id).getDocument(source: .cache)
      #expect(new.exists)
      #expect(describeBridgeValue(CppBridgeFieldValue.FromMap(new.cppBridge.data(0)))
        == describeBridgeValue(CppBridgeFieldValue.FromMap(old.cppBridge.data(0))), "\(id)",
        sourceLocation: sourceLocation)
    }

    before.document("set").setData(dictionary) { _ in }
    try now.document("set").setData(from: value)
    try await expectSameDocument("set")

    for (id, merge) in [("merge", true), ("noMerge", false)] {
      before.document(id).setData(["existing": 1]) { _ in }
      now.document(id).setData(["existing": 1]) { _ in }
      before.document(id).setData(dictionary, merge: merge) { _ in }
      try now.document(id).setData(from: value, merge: merge)
      try await expectSameDocument(id)
    }

    before.document("mergeFields").setData(["existing": 1, "int": 0]) { _ in }
    now.document("mergeFields").setData(["existing": 1, "int": 0]) { _ in }
    before.document("mergeFields").setData(dictionary, mergeFields: ["int", "nested.name"]) { _ in }
    try now.document("mergeFields").setData(from: value, mergeFields: ["int", "nested.name"])
    try await expectSameDocument("mergeFields")

    let batch = db.batch()
    batch.setData(dictionary, forDocument: before.document("batch"))
    try batch.setData(from: value, forDocument: now.document("batch"))
    batch.setData(dictionary, forDocument: before.document("batchMerge"), merge: true)
    try batch.setData(from: value, forDocument: now.document("batchMerge"), merge: true)
    batch.setData(dictionary, forDocument: before.document("batchFields"), mergeFields: ["bool"])
    try batch.setData(from: value, forDocument: now.document("batchFields"), mergeFields: ["bool"])
    batch.commit { _ in }
    for id in ["batch", "batchMerge", "batchFields"] {
      try await expectSameDocument(id)
    }

    let added = try now.addDocument(from: value)
    before.document(added.documentID).setData(dictionary) { _ in }
    try await expectSameDocument(added.documentID)
  }

  // MARK: Helpers

  private func expectSame<T: Encodable>(_ value: T, _ encoder: Firestore.Encoder = Firestore.Encoder(),
                                        sourceLocation: SourceLocation = #_sourceLocation) {
    let new = outcome { try FirestoreBridgeEncoder(encoder).encode(value) }
    let old = outcome { try toBridgeFieldValueMap(encoder.encode(value)) }
    #expect(new == old, "\(T.self)", sourceLocation: sourceLocation)
  }

  private func outcome(_ body: () throws -> CppBridgeFieldValueMap) -> Outcome {
    do {
      return .fields(describeBridgeValue(CppBridgeFieldValue.FromMap(try body())))
    } catch let EncodingError.invalidValue(_, context) {
      let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
      return .error("invalidValue at \(path.joined(separator: "/"))"
        + (context.debugDescription.contains("Top-level") ? ": \(context.debugDescription)" : ""))
    } catch {
      return .error("\(type(of: error)): \(error)")
    }
  }

  private enum Outcome: Equatable {
    case fields(String)
    case error(String)
  }
}

// MARK: - Types

private struct Everything: Encodable {
  var bool = true
  var int = 1
  var int8 = Int8(-2)
  var int16 = Int16(3)
  var int32 = Int32(-4)
  var int64 = Int64.max
  var uint = UInt(5)
  var uint8 = UInt8(1)
  var uint16 = UInt16(7)
  var uint32 = UInt32.max
  var uint64 = UInt64(9)
  var float = Float(1.5)
  var double = 2.25
  var wholeDouble = 3.0
  var string = "æøå 🎉"
  var emptyString = ""
  var none: Int? = nil
  var some: Int? = 4
  var array = [1, 2, 3]
  var arrayOfOptionals: [Int?] = [1, nil]
  var dictionary = ["a": 1, "b": 2]
  var nestedDictionary = ["a": ["b": "c"]]
  var intKeys = [1: "a", 2: "b"]
  var set: Set<Int> = [1]
  var date = Date(timeIntervalSince1970: 1_700_000_000.5)
  var data = Data([1, 2, 3])
  var url = URL(string: "https://example.com/a?b=c")!
  var decimal = Decimal(string: "1.25")!
  var timestamp = Timestamp(seconds: 1_700_000_000, nanoseconds: 123)
  var optionalTimestamp: Timestamp? = Timestamp(seconds: 1, nanoseconds: 2)
  var geoPoint = GeoPoint(latitude: 55.7, longitude: 12.6)
  var reference: DocumentReference
  var optionalReference: DocumentReference?
  var vector = VectorValue([1, 2.5])
  var minKey = MinKey.shared
  var maxKey = MaxKey.shared
  var regex = RegexValue(pattern: "^a", options: "i")
  var int32Value = Int32Value(7)
  var decimal128 = Decimal128Value("1.5")
  var objectId = BSONObjectId("507f191e810c19729de860ea")
  var bsonTimestamp = BSONTimestamp(seconds: 1, increment: 2)
  var blob = Blob(bsonBinary: Data([4, 5]), subtype: 3)
  var serverTimestamp = FieldValue.serverTimestamp()
  var increment = FieldValue.increment(Int64(1))
  var nested = Nested()
  var nestedList = [Nested(), Nested(name: "b")]
  var snakeCaseName = "converted by key strategies"

  init(reference: DocumentReference) {
    self.reference = reference
    optionalReference = reference
  }
}

private struct Nested: Encodable {
  var name = "a"
  var tags = ["x"]
  var createdAt = Date(timeIntervalSince1970: 2)
  var bytes = Data([9])
}

private struct Wrapped: Encodable {
  @DocumentID var id: DocumentReference?
  @ServerTimestamp var created: Date?
  @ServerTimestamp var modified: Timestamp?
  @ExplicitNull var explicitNil: String?
  @ExplicitNull var explicitValue: String? = "here"
  var name = "w"

  init(id: DocumentReference?, created: Date? = nil, modified: Timestamp? = nil) {
    self.id = id
    self.created = created
    self.modified = modified
  }
}

private struct Shapes: Encodable {
  enum Shape: Encodable {
    case circle(radius: Double)
    case square(Double)
    case labeled(name: String, sides: [Int])
    case boxed(inner: Nested)
    case empty
  }

  var shapes: [Shape] = [.circle(radius: 1.5), .square(2), .labeled(name: "x", sides: [1, 2]),
                         .boxed(inner: Nested()), .empty]
  var one = Shape.labeled(name: "y", sides: [])
}

private struct NonConforming: Encodable {
  var nan = Double.nan
  var infinity = Float.infinity
  var negativeInfinity = -Double.infinity
  var list = [1.0, .nan]
}

private enum Edge {
  class Base: Encodable {
    var baseValue = 1
  }

  final class Sub: Base {
    var subValue = "s"

    enum CodingKeys: String, CodingKey { case subValue }

    override func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(subValue, forKey: .subValue)
      try super.encode(to: container.superEncoder())
    }
  }

  struct SubOfNothing: Encodable {
    enum CodingKeys: String, CodingKey { case value }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(1, forKey: .value)
      _ = container.superEncoder(forKey: .value)
      _ = container.superEncoder()
    }
  }

  struct SuperInArray: Encodable {
    enum CodingKeys: String, CodingKey { case list }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      var list = container.nestedUnkeyedContainer(forKey: .list)
      try list.encode(1)
      try Base().encode(to: list.superEncoder())
      try list.encode(3)
    }
  }

  struct SameKeyTwice: Encodable {
    enum CodingKeys: String, CodingKey { case value }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(1, forKey: .value)
      try container.encode("two", forKey: .value)
      var again = encoder.container(keyedBy: CodingKeys.self)
      try again.encode(true, forKey: .value)
    }
  }

  struct NestedContainerTwice: Encodable {
    enum CodingKeys: String, CodingKey { case map, list, a, b }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      var first = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .map)
      try first.encode(1, forKey: .a)
      var second = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .map)
      try second.encode(2, forKey: .b)
      var list = container.nestedUnkeyedContainer(forKey: .list)
      try list.encode(1)
      var listAgain = container.nestedUnkeyedContainer(forKey: .list)
      try listAgain.encode(2)
    }
  }

  struct Empty: Encodable {
    var empty = EmptyValue()
    var emptyList: [Int] = []
    var emptyMap: [String: Int] = [:]
  }

  struct EmptyValue: Encodable {
    func encode(to encoder: any Encoder) throws {}
  }

  struct NestedEmpty: Encodable {
    enum CodingKeys: String, CodingKey { case a, b }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      _ = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
      _ = container.nestedUnkeyedContainer(forKey: .b)
    }
  }

  struct EncodesNothing: Encodable {
    func encode(to encoder: any Encoder) throws {}
  }

  struct Dictionaries: Encodable {
    var stringKeys = ["camelCase": 1, "snake_case": 2]
    var optionalValues: [String: Int?] = ["a": nil, "b": 1]
    var anyEncodable: [String: [String: Date]] = ["x": ["y": Date(timeIntervalSince1970: 3)]]
  }

  /// Optionals passed to `encode`, not `encodeIfPresent`.
  struct Optionals: Encodable {
    var reference: DocumentReference?

    enum CodingKeys: String, CodingKey {
      case dictionary, noDictionary, timestamp, noTimestamp, date, noDate, reference, nested
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(Optional(["a": 1]), forKey: .dictionary)
      try container.encode([String: Int]?.none, forKey: .noDictionary)
      try container.encode(Optional(Timestamp(seconds: 1, nanoseconds: 2)), forKey: .timestamp)
      try container.encode(Timestamp?.none, forKey: .noTimestamp)
      try container.encode(Optional(Date(timeIntervalSince1970: 3)), forKey: .date)
      try container.encode(Date?.none, forKey: .noDate)
      try container.encode(reference, forKey: .reference)
      try container.encode(Optional(Optional(["b": Data([1])])), forKey: .nested)
    }
  }

  /// Values typed as `any Encodable`.
  struct Existentials: Encodable {
    var reference: DocumentReference

    func encode(to encoder: any Encoder) throws {
      let values: [any Encodable] = [
        1, "a", Date(timeIntervalSince1970: 4), Data([2]), ["c": 3], Timestamp(seconds: 5, nanoseconds: 6),
        reference, Int?.none, Optional(["d": 4]), URL(string: "https://a.b")!, Decimal(2.5),
      ]
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }
    }
  }

  struct NestedArrays: Encodable {
    var nested = [[1], [2, 3]]
  }

  struct Integers: Encodable {
    var values: [Int8] = [0, 1, 2, -1]
    var bytes: [UInt8] = [0, 1, 255]
    var single = UInt64(Int64.max)
    var mins = [Int64.min]
  }

  struct UsesUserInfo: Encodable {
    enum CodingKeys: String, CodingKey { case info }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(encoder.userInfo[CodingUserInfoKey(rawValue: "test")!] as? String ?? "none",
                           forKey: .info)
    }
  }

  struct Throws: Encodable {
    struct Failure: Error {}

    func encode(to encoder: any Encoder) throws {
      throw Failure()
    }
  }

  struct NestedNaN: Encodable {
    enum CodingKeys: String, CodingKey { case outer, inner }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outer)
      try nested.encode(Double.nan, forKey: .inner)
    }
  }
}

/// The encoder's strategies.
enum EncodingStrategy: CaseIterable, Sendable {
  case snakeCaseKeys, customKeys, deferredToDate, secondsSince1970, millisecondsSince1970, iso8601,
       formattedDates, customDates, deferredToData, base64Data, customData, floatsToStrings, userInfo

  var encoder: Firestore.Encoder {
    let encoder = Firestore.Encoder()
    switch self {
    case .snakeCaseKeys: encoder.keyEncodingStrategy = .convertToSnakeCase
    case .customKeys:
      // Depends on the path, to show it's the right one.
      encoder.keyEncodingStrategy = .custom { path in
        FirestoreCodingKey("\(path.count)-\(path.last!.stringValue)")
      }
    case .deferredToDate: encoder.dateEncodingStrategy = .deferredToDate
    case .secondsSince1970: encoder.dateEncodingStrategy = .secondsSince1970
    case .millisecondsSince1970: encoder.dateEncodingStrategy = .millisecondsSince1970
    case .iso8601: encoder.dateEncodingStrategy = .iso8601
    case .formattedDates:
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      formatter.timeZone = TimeZone(identifier: "UTC")
      encoder.dateEncodingStrategy = .formatted(formatter)
    case .customDates:
      encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.unkeyedContainer()
        try container.encode(date.timeIntervalSince1970)
        try container.encode("at \(encoder.codingPath.count)")
      }
    case .deferredToData: encoder.dataEncodingStrategy = .deferredToData
    case .base64Data: encoder.dataEncodingStrategy = .base64
    case .customData:
      encoder.dataEncodingStrategy = .custom { data, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(data.count)
      }
    case .floatsToStrings:
      encoder.nonConformingFloatEncodingStrategy = .convertToString(
        positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
      )
    case .userInfo:
      encoder.userInfo[CodingUserInfoKey(rawValue: "test")!] = "info"
    }
    return encoder
  }
}
