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

// toBridgeFieldValue against the conversion it replaced (below, as it was),
// for every kind of value Firestore stores, as Swift values, as Foundation
// values and as Firestore.Encoder makes them, and for values it can't store.

import FirebaseCore
@testable import FirebaseFirestore
import Foundation
import Testing

@Suite("BridgeFieldValue")
struct BridgeFieldValueTests {
  private struct Unstorable {}

  private static func values(firestore: Firestore) -> [(String, Any)] {
    let reference = firestore.document("coll/doc")
    let swift: [(String, Any)] = [
      ("nil", Int?.none as Any),
      ("some", Int?.some(5) as Any),
      ("nested nil", Int??.some(nil) as Any),
      ("nested some", String??.some("a") as Any),
      ("null", NSNull()),
      ("true", true), ("false", false),
      ("Int", 1), ("Int.min", Int.min), ("Int64", Int64.max), ("Int32", Int32(-3)),
      ("Int16", Int16(4)), ("Int8", Int8(5)),
      ("UInt", UInt(6)), ("UInt64", UInt64(7)), ("UInt32", UInt32.max), ("UInt16", UInt16(9)),
      ("UInt8", UInt8(1)),
      ("Double", 1.5), ("whole Double", 2.0), ("NaN", Double.nan), ("infinity", Double.infinity),
      ("Float", Float(2.5)),
      ("String", "abc"), ("empty String", ""), ("unicode", "æøå 🎉"),
      ("Substring", "abcdef".dropFirst(2)),
      ("Data", Data([1, 2, 3])), ("empty Data", Data()),
      ("Timestamp", Timestamp(seconds: 1_700_000_000, nanoseconds: 5)),
      ("Date", Date(timeIntervalSince1970: 1_700_000_000.25)),
      ("GeoPoint", GeoPoint(latitude: 55.7, longitude: 12.6)),
      ("VectorValue", VectorValue([1, 2.5])),
      ("DocumentReference", reference),
      ("MinKey", MinKey.shared), ("MaxKey", MaxKey.shared),
      ("RegexValue", RegexValue(pattern: "^a", options: "i")),
      ("Int32Value", Int32Value(7)),
      ("Decimal128Value", Decimal128Value("1.5")),
      ("BSONObjectId", BSONObjectId("507f191e810c19729de860ea")),
      ("BSONTimestamp", BSONTimestamp(seconds: 1, increment: 2)),
      ("Blob", Blob(bsonBinary: Data([4, 5]), subtype: 3)),
      ("delete", FieldValue.delete()),
      ("serverTimestamp", FieldValue.serverTimestamp()),
      ("increment", FieldValue.increment(Int64(2))),
      ("arrayUnion", FieldValue.arrayUnion([1, "a", Int?.none as Any])),
      ("unsupported struct", Unstorable()),
      ("unsupported Set", Set([1])),
      ("unsupported Int keys", [1: "a"]),
    ]
    let foundation: [(String, Any)] = [
      ("NSNumber Bool", NSNumber(value: true)),
      ("NSNumber Int", NSNumber(value: 1)),
      ("NSNumber Double", NSNumber(value: 1.0)),
      ("NSNumber Float", NSNumber(value: Float(1.5))),
      ("NSNumber Int8", NSNumber(value: Int8(3))),
      ("NSNumber UInt8", NSNumber(value: UInt8(3))),
      ("NSNumber UInt64", NSNumber(value: UInt64(5))),
      ("NSNumber Int64.min", NSNumber(value: Int64.min)),
      ("NSDecimalNumber", NSDecimalNumber(string: "1.25")),
      ("NSString", NSString(string: "abc")),
      ("NSMutableString", NSMutableString(string: "æøå")),
      ("NSArray", NSArray(array: [1, "a", NSNull()])),
      ("NSMutableArray", NSMutableArray(array: [NSNumber(value: 2.5), NSString(string: "b")])),
      ("NSDictionary", NSDictionary(dictionary: ["a": 1, "b": NSString(string: "x")])),
      ("NSMutableDictionary", NSMutableDictionary(dictionary: ["c": NSNumber(value: true)])),
    ]
    let containers: [(String, Any)] = [
      ("Array", [1, "a", 2.5, true, Int?.none as Any, ["nested": [1, 2]], NSNull()] as [Any]),
      ("empty Array", [Any]()),
      ("typed Array", [1, 2, 3]),
      ("Dictionary", ["a": 1, "b": ["c": [true, "d"]], "e": Int?.none as Any] as [String: Any]),
      ("empty Dictionary", [String: Any]()),
      ("typed Dictionary", ["a": "b"]),
      ("every kind in a map", Dictionary(uniqueKeysWithValues: (swift + foundation).filter {
        !$0.0.hasPrefix("unsupported") && !$0.0.hasPrefix("delete") && !$0.0.hasPrefix("server")
      })),
    ]
    return swift + foundation + containers
  }

  @Test func convertsAsBefore() async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    for (name, value) in Self.values(firestore: firestore) {
      #expect(describeBridgeValue(toBridgeFieldValue(value)) == describeBridgeValue(bridgeBefore(value)), "\(name)")
    }
  }

  /// What Firestore.Encoder makes: NSDictionary, NSNumber, NSString, ….
  @Test func convertsEncodedDocumentsAsBefore() async throws {
    let firestore = try await FirestoreValueDecoderTests.offlineFirestore()
    struct Item: Encodable {
      var name = "a b"
      var count = 3
      var rating = 4.5
      var whole = 2.0
      var active = true
      var tags = ["x", "y"]
      var nested = ["k": [1, 2]]
      var missing: Int? = nil
      var created = Timestamp(seconds: 1, nanoseconds: 2)
      var date = Date(timeIntervalSince1970: 3)
      var location = GeoPoint(latitude: 1, longitude: 2)
      var owner: DocumentReference
      var bytes = Data([9])
    }
    let encoded = try Firestore.Encoder().encode(Item(owner: firestore.document("coll/x")))
    #expect(describeBridgeValue(toBridgeFieldValue(encoded)) == describeBridgeValue(bridgeBefore(encoded)))
    #expect(Int(toBridgeFieldValueMap(encoded).size()) == encoded.count)
  }
}

/// Every part of a bridge value, whatever its tag; maps sorted by key.
func describeBridgeValue(_ value: CppBridgeFieldValue) -> String {
  var parts = ["tag \(value.tag().rawValue)"]
  switch value.tag() {
  case .Array, .SentinelArrayUnion, .SentinelArrayRemove, .SentinelIncrement, .SentinelMinimum,
       .SentinelMaximum:
    let array = value.array_value()
    parts.append("[" + (0 ..< array.size()).map { describeBridgeValue(array[$0]) }.joined(separator: ", ") + "]")
  case .Map:
    let map = value.map_value()
    let entries = (0 ..< map.size()).map { "\(String(map[$0].first)): \(describeBridgeValue(map[$0].second))" }
    parts.append("{" + entries.sorted().joined(separator: ", ") + "}")
  default:
    let vector = value.vector_value()
    let blob = value.blob_bytes()
    parts += [
      "bool \(value.bool_value())", "int \(value.int64_value())",
      "double \(value.double_value().bitPattern)",
      "string \(String(value.string_value()))", "string2 \(String(value.string2_value()))",
      "blob \((0 ..< blob.size()).map { blob[$0] })",
      "timestamp \(value.timestamp_seconds()) \(value.timestamp_nanos())",
      "geo \(value.geo_latitude().bitPattern) \(value.geo_longitude().bitPattern)",
      "vector \((0 ..< vector.size()).map { vector[$0].bitPattern })",
      "bson \(value.bson_timestamp_seconds()) \(value.bson_timestamp_increment()) \(value.bson_subtype())",
    ]
  }
  return parts.joined(separator: " ")
}

// MARK: - The conversion before (Sources/Firestore/Swift/Source/Bridge/FirestoreTypes.swift)

private func unwrappingOptionalBefore(_ value: Any) -> Any? {
  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else { return value }
  return mirror.children.first.flatMap { unwrappingOptionalBefore($0.value) }
}

private func bridgeBefore(_ number: NSNumber) -> CppBridgeFieldValue {
  switch String(cString: number.objCType).first {
  case "c", "B", "C":
    return CppBridgeFieldValue.FromBool(number.boolValue)
  case "f", "d":
    return CppBridgeFieldValue.FromDouble(number.doubleValue)
  case "L", "Q":
    let value = number.uint64Value
    if value > UInt64(Int64.max) {
      invalidArgument("NSNumber (\(value)) is too large")
    }
    return CppBridgeFieldValue.FromInt64(Int64(value))
  default:
    return CppBridgeFieldValue.FromInt64(number.int64Value)
  }
}

private func bridgeBefore(_ value: Any) -> CppBridgeFieldValue {
  guard let value = unwrappingOptionalBefore(value) else {
    return CppBridgeFieldValue.Null()
  }
  switch value {
  case let fieldValue as FieldValue:
    return fieldValue.toBridgeFieldValue()
  case is NSNull:
    return CppBridgeFieldValue.Null()
  case let number as NSNumber where type(of: value) is NSNumber.Type:
    return bridgeBefore(number)
  case let bool as Bool:
    return CppBridgeFieldValue.FromBool(bool)
  case let int as Int:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int64:
    return CppBridgeFieldValue.FromInt64(int)
  case let int as Int32:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int16:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int8:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let uint as UInt:
    return bridgeBefore(NSNumber(value: uint))
  case let uint as UInt64:
    return bridgeBefore(NSNumber(value: uint))
  case let uint as UInt32:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let uint as UInt16:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let uint as UInt8:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let double as Double:
    return CppBridgeFieldValue.FromDouble(double)
  case let float as Float:
    return CppBridgeFieldValue.FromDouble(Double(float))
  case let string as String:
    return CppBridgeFieldValue.FromString(std.string(string))
  case let substring as Substring:
    return CppBridgeFieldValue.FromString(std.string(String(substring)))
  case let data as Data:
    return data.withUnsafeBytes { buffer in
      CppBridgeFieldValue.FromBlob(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
    }
  case let timestamp as Timestamp:
    return CppBridgeFieldValue.FromTimestamp(timestamp.seconds, timestamp.nanoseconds)
  case let date as Date:
    let timestamp = Timestamp(date: date)
    return CppBridgeFieldValue.FromTimestamp(timestamp.seconds, timestamp.nanoseconds)
  case let geoPoint as GeoPoint:
    return CppBridgeFieldValue.FromGeoPoint(geoPoint.latitude, geoPoint.longitude)
  case let vector as VectorValue:
    var doubles = CppDoubleVector()
    for d in vector.array {
      doubles.push_back(d)
    }
    return CppBridgeFieldValue.FromVector(doubles)
  case let reference as DocumentReference:
    return CppBridgeFieldValue.FromReference(reference.cppBridge)
  case is MinKey:
    return CppBridgeFieldValue.MinKey()
  case is MaxKey:
    return CppBridgeFieldValue.MaxKey()
  case let regex as RegexValue:
    return CppBridgeFieldValue.FromRegex(std.string(regex.pattern), std.string(regex.options))
  case let int32 as Int32Value:
    return CppBridgeFieldValue.FromInt32(int32.value)
  case let decimal as Decimal128Value:
    return CppBridgeFieldValue.FromDecimal128(std.string(decimal.value))
  case let objectId as BSONObjectId:
    return CppBridgeFieldValue.FromBsonObjectId(std.string(objectId.value))
  case let timestamp as BSONTimestamp:
    return CppBridgeFieldValue.FromBsonTimestamp(timestamp.seconds, timestamp.increment)
  case let blob as Blob:
    return blob.bytes.withUnsafeBytes { buffer in
      CppBridgeFieldValue.FromBsonBinaryData(
        buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, blob.subtype
      )
    }
  case let array as [Any]:
    var cppArray = CppBridgeFieldValueVector()
    for element in array {
      cppArray.push_back(bridgeBefore(element))
    }
    return CppBridgeFieldValue.FromArray(cppArray)
  case let dictionary as [String: Any]:
    var map = CppBridgeFieldValueMap()
    for (key, value) in dictionary {
      map.push_back(CppBridgeFieldValueMapEntry(first: std.string(key), second: bridgeBefore(value)))
    }
    return CppBridgeFieldValue.FromMap(map)
  default:
    return CppBridgeFieldValue.Unsupported(std.string(String(describing: type(of: value))))
  }
}
