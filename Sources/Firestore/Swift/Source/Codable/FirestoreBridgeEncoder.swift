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

import FirebaseShared
import Foundation
import Synchronization

/// Encodes a value straight to the bridge's values, as `Firestore.Encoder`
/// and `toBridgeFieldValue` together make them, without the `[String: Any]`
/// between (Docs/FirestorePerformance.md). The writes that take an
/// `Encodable` use it; `Firestore.Encoder.encode(_:)` still makes the
/// dictionary.
///
/// It follows `FirebaseDataEncoder`'s rules: its strategies and `userInfo`,
/// the types it treats specially (`Date`, `Data`, `URL`, `Decimal`,
/// `[String: Encodable]`, Firestore's passthrough types, `@DocumentID`), a
/// value that encodes nothing being an empty map, and its errors. Each value
/// becomes what the bridge makes of the Foundation value `FirebaseDataEncoder`
/// makes of it, an integer by its `NSNumber`'s type on this platform. Coding
/// paths are `FirebaseDataEncoder`'s too: values in a nested container get
/// their parent's path and their key, without the nested container's key,
/// which a custom key strategy sees and errors report.
struct FirestoreBridgeEncoder {
  let context: FirestoreEncodingContext

  init(_ encoder: Firestore.Encoder) {
    context = FirestoreEncodingContext(encoder)
  }

  /// The document's fields.
  func encode<T: Encodable>(_ value: T) throws -> CppBridgeFieldValueMap {
    guard let encoded = try context.encodedOrNil(value, at: .root) else {
      throw EncodingError.invalidValue(value, .init(
        codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."
      ))
    }
    guard case let .map(map) = encoded.resolved else {
      // As Firestore.Encoder, for a value that isn't a dictionary.
      throw EncodingError.invalidValue(value, .init(
        codingPath: [], debugDescription: "Top-level \(T.self) is not allowed."
      ))
    }
    return map.bridged
  }
}

/// A value being encoded. Containers are references, so nested containers and
/// super encoders can fill them in after they're placed.
enum FirestoreEncodedValue {
  case value(CppBridgeFieldValue)
  case map(FirestoreEncodedMap)
  case array(FirestoreEncodedArray)
  /// What a super encoder encodes, once it has.
  case pending(FirestoreEncodedSlot)

  /// The value, with a pending one's in its place (an empty map if it encoded
  /// nothing, as FirebaseDataEncoder's referencing encoder writes).
  var resolved: FirestoreEncodedValue {
    guard case let .pending(slot) = self else { return self }
    return slot.value?.resolved ?? .map(FirestoreEncodedMap())
  }

  var bridged: CppBridgeFieldValue {
    switch resolved {
    case let .value(value): return value
    case let .map(map): return CppBridgeFieldValue.FromMap(map.bridged)
    case let .array(array):
      var elements = CppBridgeFieldValueVector()
      for element in array.elements {
        elements.push_back(element.bridged)
      }
      return CppBridgeFieldValue.FromArray(elements)
    case .pending: fatalError("Resolved values aren't pending.")
    }
  }
}

final class FirestoreEncodedMap {
  var entries: [String: FirestoreEncodedValue] = [:]

  var bridged: CppBridgeFieldValueMap {
    var map = CppBridgeFieldValueMap()
    map.reserve(entries.count)
    for (key, value) in entries {
      map.push_back(CppBridgeFieldValueMapEntry(first: std.string(key), second: value.bridged))
    }
    return map
  }
}

final class FirestoreEncodedArray {
  var elements: [FirestoreEncodedValue] = []
}

final class FirestoreEncodedSlot {
  var value: FirestoreEncodedValue?
}

/// The encoder's options, shared by one encode. (Unchecked: it doesn't change,
/// as FirestoreDecodingContext.)
final class FirestoreEncodingContext: @unchecked Sendable {
  let dateStrategy: FirebaseDataEncoder.DateEncodingStrategy
  let dataStrategy: FirebaseDataEncoder.DataEncodingStrategy
  let floatStrategy: FirebaseDataEncoder.NonConformingFloatEncodingStrategy
  let keyStrategy: FirebaseDataEncoder.KeyEncodingStrategy
  let userInfo: [CodingUserInfoKey: Any]

  init(_ encoder: Firestore.Encoder) {
    dateStrategy = encoder.dateEncodingStrategy
    dataStrategy = encoder.dataEncodingStrategy
    floatStrategy = encoder.nonConformingFloatEncodingStrategy
    keyStrategy = encoder.keyEncodingStrategy
    userInfo = encoder.userInfo
  }

  // MARK: Values

  func encoded<T: Encodable>(_ value: T, at path: FirestoreCodingPath) throws -> FirestoreEncodedValue {
    try encodedOrNil(value, at: path) ?? .map(FirestoreEncodedMap())
  }

  /// The value encoded, or nil if it encoded nothing; in FirebaseDataEncoder's
  /// order (its `box_`).
  func encodedOrNil<T: Encodable>(_ value: T, at path: FirestoreCodingPath) throws
    -> FirestoreEncodedValue? {
    switch Self.treatment(of: value) {
    case .date:
      return try encoded(value as! Date, at: path)
    case .data:
      return try encoded(value as! Data, at: path)
    case .url:
      return string((value as! URL).absoluteString)
    case .decimal:
      return .value(toBridgeFieldValue(value as! NSDecimalNumber))
    case .stringKeyedDictionary:
      // As FirebaseDataEncoder does, without converting the keys.
      return try (value as! any FirestoreStringKeyedEncodable).encoded(context: self, at: path)
    case .passthrough:
      // As the bridge converts the value FirebaseDataEncoder passes through.
      return .value(toBridgeFieldValue(value))
    case .encodesItself:
      let encoder = FirestoreValueEncoder(context: self, path: path)
      try value.encode(to: encoder)
      return encoder.slot.value
    }
  }

  /// How FirebaseDataEncoder treats a value: by its checks, in their order.
  private enum Treatment {
    case date, data, url, decimal, stringKeyedDictionary, passthrough, encodesItself
  }

  /// The treatments of the types whose values all get the same: all but
  /// Optionals, whose casts see the wrapped value. The checks are dynamic
  /// casts, slower than encoding most values.
  private static let treatments = Mutex<[ObjectIdentifier: Treatment]>([:])

  private static func treatment<T: Encodable>(of value: T) -> Treatment {
    let type = Swift.type(of: value as Any)
    guard !(type is any ExpressibleByNilLiteral.Type) else { return checkedTreatment(of: value, type) }
    let id = ObjectIdentifier(type)
    if let known = treatments.withLock({ $0[id] }) {
      return known
    }
    let treatment = checkedTreatment(of: value, type)
    treatments.withLock { $0[id] = treatment }
    return treatment
  }

  private static func checkedTreatment<T: Encodable>(of value: T, _ type: Any.Type) -> Treatment {
    if type == Date.self || type == NSDate.self {
      return .date
    } else if type == Data.self || type == NSData.self {
      return .data
    } else if type == URL.self || type == NSURL.self {
      return .url
    } else if type == Decimal.self || type == NSDecimalNumber.self {
      return .decimal
    } else if value is any FirestoreStringKeyedEncodable {
      return .stringKeyedDictionary
    } else if FirestorePassthroughTypes.isPassthroughType(value) {
      return .passthrough
    }
    return .encodesItself
  }

  func string(_ value: String) -> FirestoreEncodedValue {
    .value(CppBridgeFieldValue.FromString(std.string(value)))
  }

  func bool(_ value: Bool) -> FirestoreEncodedValue {
    .value(CppBridgeFieldValue.FromBool(value))
  }

  /// As the bridge converts the integer's `NSNumber`.
  func integer<T: FixedWidthInteger>(_ value: T) -> FirestoreEncodedValue {
    switch NSNumberKind.of(T.self) {
    case .boolean:
      return .value(CppBridgeFieldValue.FromBool(value != 0))
    case .double:
      return .value(CppBridgeFieldValue.FromDouble(Double(value)))
    case .unsigned:
      guard let int64 = Int64(exactly: value) else {
        invalidArgument("NSNumber (\(value)) is too large")
      }
      return .value(CppBridgeFieldValue.FromInt64(int64))
    case .signed:
      return .value(CppBridgeFieldValue.FromInt64(Int64(truncatingIfNeeded: value)))
    }
  }

  func float<T: BinaryFloatingPoint>(_ value: T, at path: FirestoreCodingPath) throws
    -> FirestoreEncodedValue {
    guard value.isFinite else {
      guard case let .convertToString(positiveInfinity, negativeInfinity, nan) = floatStrategy else {
        let description = value.isNaN ? "\(T.self).nan"
          : value < 0 ? "-\(T.self).infinity" : "\(T.self).infinity"
        throw EncodingError.invalidValue(value, .init(
          codingPath: path.keys,
          debugDescription: "Unable to encode \(description) directly in JSON. Use "
            + "JSONEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the "
            + "value should be encoded."
        ))
      }
      return string(value.isNaN ? nan : value < 0 ? negativeInfinity : positiveInfinity)
    }
    return .value(CppBridgeFieldValue.FromDouble(Double(value)))
  }

  private func encoded(_ date: Date, at path: FirestoreCodingPath) throws -> FirestoreEncodedValue {
    switch dateStrategy {
    case .deferredToDate:
      return try encoded(at: path) { try date.encode(to: $0) }
    case .secondsSince1970:
      return .value(CppBridgeFieldValue.FromDouble(date.timeIntervalSince1970))
    case .millisecondsSince1970:
      return .value(CppBridgeFieldValue.FromDouble(1000.0 * date.timeIntervalSince1970))
    case .iso8601:
      let style = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .standard,
                                          timeSeparator: .colon)
      return string(date.formatted(style))
    case let .formatted(formatter):
      return string(formatter.string(from: date))
    case let .custom(closure):
      return try encoded(at: path) { try closure(date, $0) }
    }
  }

  private func encoded(_ data: Data, at path: FirestoreCodingPath) throws -> FirestoreEncodedValue {
    switch dataStrategy {
    case .deferredToData:
      return try encoded(at: path) { try data.encode(to: $0) }
    case .base64:
      return string(data.base64EncodedString())
    case .blob:
      return .value(data.withUnsafeBytes { buffer in
        CppBridgeFieldValue.FromBlob(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
      })
    case let .custom(closure):
      return try encoded(at: path) { try closure(data, $0) }
    }
  }

  /// What `encode` encodes to an encoder at `path`, or an empty map.
  private func encoded(at path: FirestoreCodingPath, _ encode: (any Encoder) throws -> Void) throws
    -> FirestoreEncodedValue {
    let encoder = FirestoreValueEncoder(context: self, path: path)
    try encode(encoder)
    return encoder.slot.value ?? .map(FirestoreEncodedMap())
  }

  /// The key as the key strategy converts it.
  func key(_ key: some CodingKey, at path: FirestoreCodingPath) -> String {
    switch keyStrategy {
    case .useDefaultKeys:
      return key.stringValue
    case .convertToSnakeCase:
      return FirebaseDataEncoder.KeyEncodingStrategy._convertToSnakeCase(key.stringValue)
    case let .custom(convert):
      return convert(path.appending(key).keys).stringValue
    }
  }
}

// MARK: - Encoder

/// An `Encoder` for one value, which ends up in `slot`.
private final class FirestoreValueEncoder: Encoder, SingleValueEncodingContainer {
  let context: FirestoreEncodingContext
  let path: FirestoreCodingPath
  let slot: FirestoreEncodedSlot

  init(context: FirestoreEncodingContext, path: FirestoreCodingPath,
       slot: FirestoreEncodedSlot = FirestoreEncodedSlot()) {
    self.context = context
    self.path = path
    self.slot = slot
  }

  var codingPath: [any CodingKey] { path.keys }
  var userInfo: [CodingUserInfoKey: Any] { context.userInfo }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    // Asking again gives the same container, as FirebaseDataEncoder's does.
    let map: FirestoreEncodedMap
    switch slot.value {
    case nil:
      map = FirestoreEncodedMap()
      slot.value = .map(map)
    case let .map(existing)?:
      map = existing
    default:
      preconditionFailure(
        "Attempt to push new keyed encoding container when already previously encoded at this path."
      )
    }
    return KeyedEncodingContainer(FirestoreKeyedEncodingContainer<Key>(map: map, context: context,
                                                                       path: path, valuePath: path))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    let array: FirestoreEncodedArray
    switch slot.value {
    case nil:
      array = FirestoreEncodedArray()
      slot.value = .array(array)
    case let .array(existing)?:
      array = existing
    default:
      preconditionFailure(
        "Attempt to push new unkeyed encoding container when already previously encoded at this path."
      )
    }
    return FirestoreUnkeyedEncodingContainer(array: array, context: context, path: path,
                                             valuePath: path)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    self
  }

  private func set(_ value: FirestoreEncodedValue) {
    precondition(slot.value == nil,
                 "Attempt to encode value through single value container when previously value already encoded.")
    slot.value = value
  }

  func encodeNil() { set(.value(CppBridgeFieldValue.Null())) }
  func encode(_ value: Bool) { set(context.bool(value)) }
  func encode(_ value: String) { set(context.string(value)) }
  func encode(_ value: Double) throws { set(try context.float(value, at: path)) }
  func encode(_ value: Float) throws { set(try context.float(value, at: path)) }
  func encode(_ value: Int) { set(context.integer(value)) }
  func encode(_ value: Int8) { set(context.integer(value)) }
  func encode(_ value: Int16) { set(context.integer(value)) }
  func encode(_ value: Int32) { set(context.integer(value)) }
  func encode(_ value: Int64) { set(context.integer(value)) }
  func encode(_ value: UInt) { set(context.integer(value)) }
  func encode(_ value: UInt8) { set(context.integer(value)) }
  func encode(_ value: UInt16) { set(context.integer(value)) }
  func encode(_ value: UInt32) { set(context.integer(value)) }
  func encode(_ value: UInt64) { set(context.integer(value)) }
  func encode<T: Encodable>(_ value: T) throws { set(try context.encoded(value, at: path)) }
}

private struct FirestoreKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let map: FirestoreEncodedMap
  let context: FirestoreEncodingContext
  /// The container's coding path, which its keys are converted with.
  let path: FirestoreCodingPath
  /// The path its values are encoded at, with their key: FirebaseDataEncoder's
  /// encoder's, which nested containers don't extend.
  let valuePath: FirestoreCodingPath

  var codingPath: [any CodingKey] { path.keys }

  private func set(_ value: FirestoreEncodedValue, _ key: Key) {
    map.entries[context.key(key, at: path)] = value
  }

  mutating func encodeNil(forKey key: Key) { set(.value(CppBridgeFieldValue.Null()), key) }
  mutating func encode(_ value: Bool, forKey key: Key) { set(context.bool(value), key) }
  mutating func encode(_ value: String, forKey key: Key) { set(context.string(value), key) }
  mutating func encode(_ value: Double, forKey key: Key) throws {
    set(try context.float(value, at: valuePath.appending(key)), key)
  }

  mutating func encode(_ value: Float, forKey key: Key) throws {
    set(try context.float(value, at: valuePath.appending(key)), key)
  }

  mutating func encode(_ value: Int, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: Int8, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: Int16, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: Int32, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: Int64, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: UInt, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: UInt8, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: UInt16, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: UInt32, forKey key: Key) { set(context.integer(value), key) }
  mutating func encode(_ value: UInt64, forKey key: Key) { set(context.integer(value), key) }

  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    // @DocumentID isn't stored, as in FirebaseDataEncoder.
    if T.self is StructureCodingUncodedUnkeyed.Type { return }
    set(try context.encoded(value, at: valuePath.appending(key)), key)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type,
                                                      forKey key: Key)
    -> KeyedEncodingContainer<NestedKey> {
    // An existing map for the key is reused, as in FirebaseDataEncoder.
    let name = context.key(key, at: path)
    let nested: FirestoreEncodedMap
    switch map.entries[name] {
    case nil:
      nested = FirestoreEncodedMap()
      map.entries[name] = .map(nested)
    case let .map(existing)?:
      nested = existing
    default:
      preconditionFailure(
        "Attempt to re-encode into nested KeyedEncodingContainer<\(Key.self)> for key \"\(name)\" is "
          + "invalid: non-keyed container already encoded for this key"
      )
    }
    return KeyedEncodingContainer(FirestoreKeyedEncodingContainer<NestedKey>(
      map: nested, context: context, path: path.appending(key), valuePath: valuePath
    ))
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    let name = context.key(key, at: path)
    let nested: FirestoreEncodedArray
    switch map.entries[name] {
    case nil:
      nested = FirestoreEncodedArray()
      map.entries[name] = .array(nested)
    case let .array(existing)?:
      nested = existing
    default:
      preconditionFailure(
        "Attempt to re-encode into nested UnkeyedEncodingContainer for key \"\(name)\" is invalid: "
          + "keyed container/single value already encoded for this key"
      )
    }
    return FirestoreUnkeyedEncodingContainer(array: nested, context: context,
                                             path: path.appending(key), valuePath: valuePath)
  }

  mutating func superEncoder() -> any Encoder {
    superEncoder(for: FirestoreCodingKey.super)
  }

  mutating func superEncoder(forKey key: Key) -> any Encoder {
    superEncoder(for: key)
  }

  private func superEncoder(for key: some CodingKey) -> any Encoder {
    let slot = FirestoreEncodedSlot()
    map.entries[context.key(key, at: path)] = .pending(slot)
    return FirestoreValueEncoder(context: context, path: valuePath.appending(key), slot: slot)
  }
}

private struct FirestoreUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let array: FirestoreEncodedArray
  let context: FirestoreEncodingContext
  /// As FirestoreKeyedEncodingContainer's.
  let path: FirestoreCodingPath
  let valuePath: FirestoreCodingPath

  var codingPath: [any CodingKey] { path.keys }
  var count: Int { array.elements.count }

  private var nextKey: FirestoreCodingKey { FirestoreCodingKey(index: count) }
  private var nextPath: FirestoreCodingPath { valuePath.appending(nextKey) }

  private func append(_ value: FirestoreEncodedValue) {
    array.elements.append(value)
  }

  mutating func encodeNil() { append(.value(CppBridgeFieldValue.Null())) }
  mutating func encode(_ value: Bool) { append(context.bool(value)) }
  mutating func encode(_ value: String) { append(context.string(value)) }
  mutating func encode(_ value: Double) throws { append(try context.float(value, at: nextPath)) }
  mutating func encode(_ value: Float) throws { append(try context.float(value, at: nextPath)) }
  mutating func encode(_ value: Int) { append(context.integer(value)) }
  mutating func encode(_ value: Int8) { append(context.integer(value)) }
  mutating func encode(_ value: Int16) { append(context.integer(value)) }
  mutating func encode(_ value: Int32) { append(context.integer(value)) }
  mutating func encode(_ value: Int64) { append(context.integer(value)) }
  mutating func encode(_ value: UInt) { append(context.integer(value)) }
  mutating func encode(_ value: UInt8) { append(context.integer(value)) }
  mutating func encode(_ value: UInt16) { append(context.integer(value)) }
  mutating func encode(_ value: UInt32) { append(context.integer(value)) }
  mutating func encode(_ value: UInt64) { append(context.integer(value)) }

  mutating func encode<T: Encodable>(_ value: T) throws {
    append(try context.encoded(value, at: nextPath))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type)
    -> KeyedEncodingContainer<NestedKey> {
    let nested = FirestoreEncodedMap()
    let path = path.appending(nextKey)
    append(.map(nested))
    return KeyedEncodingContainer(FirestoreKeyedEncodingContainer<NestedKey>(
      map: nested, context: context, path: path, valuePath: valuePath
    ))
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let nested = FirestoreEncodedArray()
    let path = path.appending(nextKey)
    append(.array(nested))
    return FirestoreUnkeyedEncodingContainer(array: nested, context: context, path: path,
                                             valuePath: valuePath)
  }

  mutating func superEncoder() -> any Encoder {
    let slot = FirestoreEncodedSlot()
    let path = nextPath
    append(.pending(slot))
    return FirestoreValueEncoder(context: context, path: path, slot: slot)
  }
}

// MARK: - Dictionaries

/// `[String: Value]`, which encodes its keys unconverted.
private protocol FirestoreStringKeyedEncodable {
  func encoded(context: FirestoreEncodingContext, at path: FirestoreCodingPath) throws
    -> FirestoreEncodedValue
}

extension Dictionary: FirestoreStringKeyedEncodable where Key == String, Value: Encodable {
  fileprivate func encoded(context: FirestoreEncodingContext, at path: FirestoreCodingPath) throws
    -> FirestoreEncodedValue {
    let map = FirestoreEncodedMap()
    map.entries.reserveCapacity(count)
    for (key, value) in self {
      map.entries[key] = try context.encoded(value, at: path.appending(FirestoreCodingKey(key)))
    }
    return .map(map)
  }
}
