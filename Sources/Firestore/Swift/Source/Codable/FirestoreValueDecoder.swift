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

typealias CppFieldValueRef = firebase.firestore.swift_bridge.FieldValueRef
typealias CppFieldMapRef = firebase.firestore.swift_bridge.FieldMapRef
typealias CppFieldArrayRef = firebase.firestore.swift_bridge.FieldArrayRef
typealias CppFieldBytes = firebase.firestore.swift_bridge.FieldBytes
typealias CppFieldValueKind = firebase.firestore.swift_bridge.FieldValueKind
private typealias Bridge = firebase.firestore.swift_bridge

/// Decodes a document straight from the values the C++ core keeps, as
/// `Firestore.Decoder` decodes the `[String: Any]` that `data()` makes of
/// them, without making those (Docs/FirestorePerformance.md).
///
/// It reads nulls, booleans, numbers, strings, maps and arrays in place, and
/// timestamps, geo points and references decoded as their own types; a `Date`
/// with a custom strategy (the default `.timestamp` is one) decodes with it,
/// in place. Where the result could depend on how `FirebaseDataDecoder`
/// treats the Foundation value (an integer decoded as a `Bool`, a double as an
/// `Int`, a `Date` with another strategy, a blob, …), it converts that one
/// value as `data()` would and lets `FirebaseDataDecoder` decode it, so the
/// result is the same, errors included. The values belong to the snapshot, which must live during the
/// decode.
struct FirestoreValueDecoder {
  let context: FirestoreDecodingContext

  func decode<T: Decodable>(_ type: T.Type, from snapshot: DocumentSnapshot) throws -> T {
    try withExtendedLifetime(snapshot) {
      // Swift imports GetFields() with this name because what it returns
      // points into the snapshot, which outlives the decode here.
      try context.unwrap(.map(snapshot.cppBridge.__GetFieldsUnsafe()), as: type, at: .root)
    }
  }
}

/// A value of the document: one the core keeps, or the document's root map.
enum FirestoreValue {
  case value(CppFieldValueRef)
  case map(CppFieldMapRef)

  var kind: CppFieldValueKind {
    switch self {
    case let .value(value): return Bridge.KindOf(value)
    case .map: return .Map
    }
  }

  var map: CppFieldMapRef {
    switch self {
    case let .value(value): return Bridge.MapOf(value)
    case let .map(map): return map
    }
  }
}

extension CppFieldValueKind {
  /// Whether the decoder's containers read values of this kind in place;
  /// others decode as `data()` makes them.
  var isReadInPlace: Bool {
    switch self {
    case .Null, .Boolean, .Integer, .Double, .String, .Map, .Array: return true
    default: return false
    }
  }
}

/// The options and the snapshot, shared by the decoders and containers of one
/// decode. (Unchecked: it doesn't change, and FirebaseDataDecoder, whose
/// strategies these are, is unchecked too.)
final class FirestoreDecodingContext: @unchecked Sendable {
  let snapshot: DocumentSnapshot
  let serverTimestampBehavior: ServerTimestampBehavior
  /// Configured as Firestore.Decoder configures it: decodes the values that
  /// aren't read in place.
  let fallback: FirebaseDataDecoder
  let userInfo: [CodingUserInfoKey: Any]

  init(snapshot: DocumentSnapshot, serverTimestampBehavior: ServerTimestampBehavior,
       fallback: FirebaseDataDecoder) {
    self.snapshot = snapshot
    self.serverTimestampBehavior = serverTimestampBehavior
    self.fallback = fallback
    userInfo = fallback.userInfo
  }

  // MARK: Values

  func unwrap<T: Decodable>(_ value: FirestoreValue, as type: T.Type, at path: FirestoreCodingPath) throws -> T {
    let kind = value.kind
    if case let .value(ref) = value, let result = firestoreType(ref, kind, as: type) {
      return result
    } else if type == Date.self, kind != .Null, kind != .Other,
              case let .custom(closure) = fallback.dateDecodingStrategy {
      // As FirebaseDataDecoder decodes a Date with a custom strategy (the
      // default, .timestamp, is one): the closure decodes the value, here in
      // place.
      return try closure(FirestoreValueDecoderAt(value: value, context: self, path: path)) as! T
    } else if !kind.isReadInPlace || type == Date.self || type == Data.self || type == URL.self
      || type == Decimal.self {
      return try decodeConverted(value, as: type, at: path)
    } else if let dictionary = type as? FirestoreStringKeyedDictionary.Type {
      // As FirebaseDataDecoder does, without converting the keys.
      return try dictionary.decode(from: value, context: self, at: path) as! T
    }
    return try T(from: FirestoreValueDecoderAt(value: value, context: self, path: path))
  }

  /// A timestamp, geo point or reference decoded as its own type, which
  /// FirebaseDataDecoder passes through as `data()` makes it.
  private func firestoreType<T>(_ ref: CppFieldValueRef, _ kind: CppFieldValueKind, as type: T.Type) -> T? {
    switch kind {
    case .Timestamp where type == Timestamp.self:
      let timestamp = Bridge.TimestampOf(ref)
      return Timestamp(seconds: timestamp.seconds, nanoseconds: timestamp.nanos) as? T
    case .GeoPoint where type == GeoPoint.self:
      let geoPoint = Bridge.GeoPointOf(ref)
      return GeoPoint(latitude: geoPoint.latitude, longitude: geoPoint.longitude) as? T
    case .Reference where type == DocumentReference.self:
      return referencedDocument(ref, firestore: snapshot.firestore) as? T
    default:
      return nil
    }
  }

  func isNull(_ value: FirestoreValue) -> Bool {
    switch value.kind {
    case .Null: return true
    // A server timestamp that isn't set yet can be null.
    case .Other: return converted(value) is NSNull
    default: return false
    }
  }

  func bool(_ value: FirestoreValue, at path: FirestoreCodingPath) throws -> Bool {
    if case let .value(ref) = value, Bridge.KindOf(ref) == .Boolean {
      return Bridge.BooleanOf(ref)
    }
    return try decodeConverted(value, as: Bool.self, at: path)
  }

  func integer<T: FixedWidthInteger & Decodable>(_ value: FirestoreValue, as type: T.Type,
                                                 at path: FirestoreCodingPath) throws -> T {
    if case let .value(ref) = value, Bridge.KindOf(ref) == .Integer,
       let result = T(exactly: Bridge.IntegerOf(ref)) {
      return result
    }
    return try decodeConverted(value, as: type, at: path)
  }

  func double(_ value: FirestoreValue, at path: FirestoreCodingPath) throws -> Double {
    if case let .value(ref) = value {
      switch Bridge.KindOf(ref) {
      case .Double: return Bridge.DoubleOf(ref)
      // As NSNumber's doubleValue.
      case .Integer: return Double(Bridge.IntegerOf(ref))
      default: break
      }
    }
    return try decodeConverted(value, as: Double.self, at: path)
  }

  func string(_ value: FirestoreValue, at path: FirestoreCodingPath) throws -> String {
    if case let .value(ref) = value, Bridge.KindOf(ref) == .String {
      return String(Bridge.StringOf(ref))
    }
    return try decodeConverted(value, as: String.self, at: path)
  }

  /// The value as `data()` makes it.
  func converted(_ value: FirestoreValue) -> Any {
    switch value {
    case let .value(ref):
      return fromBridgeFieldValue(
        snapshot.cppBridge.ConvertValue(ref, Int32(serverTimestampBehavior.rawValue)),
        firestore: snapshot.firestore
      )
    case .map:
      return snapshot.data(with: serverTimestampBehavior) ?? NSNull()
    }
  }

  /// Decodes the value as `data()` makes it, with `FirebaseDataDecoder`.
  func decodeConverted<T: Decodable>(_ value: FirestoreValue, as type: T.Type,
                                     at path: FirestoreCodingPath) throws -> T {
    let converted = converted(value)
    do {
      return try fallback.decode(type, from: converted)
    } catch let error as DecodingError {
      // It decoded from the top; its errors' coding paths start here.
      throw error.prefixingCodingPath(path.keys)
    }
  }

  // MARK: Keys

  /// The map's entries by the keys a keyed container sees, if the key
  /// strategy converts them (as FirebaseDataDecoder does, the first of keys
  /// that convert to the same one wins).
  func convertedKeys(_ map: CppFieldMapRef, at path: FirestoreCodingPath) -> [String: Int]? {
    let convert: (String) -> String
    switch fallback.keyDecodingStrategy {
    case .useDefaultKeys:
      return nil
    case .convertFromSnakeCase:
      convert = FirebaseDataDecoder.KeyDecodingStrategy._convertFromSnakeCase
    case let .custom(converter):
      let codingPath = path.keys
      convert = { converter(codingPath + [FirestoreCodingKey($0)]).stringValue }
    }
    var keys: [String: Int] = [:]
    for index in 0 ..< map.count {
      let key = convert(String(Bridge.KeyAt(map, index)))
      if keys[key] == nil {
        keys[key] = index
      }
    }
    return keys
  }
}

extension String {
  /// The bytes as a string, as `data()` makes keys and strings.
  init(_ bytes: CppFieldBytes) {
    guard let data = bytes.data, bytes.count > 0 else {
      self = ""
      return
    }
    self = String(decoding: UnsafeBufferPointer(start: data, count: bytes.count), as: UTF8.self)
  }

  /// Whether the string's UTF-8 is `bytes`, without making a string of them.
  func matches(_ bytes: CppFieldBytes) -> Bool {
    var string = self
    return string.withUTF8 { utf8 in
      guard utf8.count == bytes.count else { return false }
      guard let data = bytes.data, let base = utf8.baseAddress else { return utf8.isEmpty }
      return memcmp(base, data, utf8.count) == 0
    }
  }
}

extension DecodingError {
  func prefixingCodingPath(_ prefix: [any CodingKey]) -> DecodingError {
    guard !prefix.isEmpty else { return self }
    func prefixed(_ context: Context) -> Context {
      Context(codingPath: prefix + context.codingPath, debugDescription: context.debugDescription,
              underlyingError: context.underlyingError)
    }
    switch self {
    case let .typeMismatch(type, context): return .typeMismatch(type, prefixed(context))
    case let .valueNotFound(type, context): return .valueNotFound(type, prefixed(context))
    case let .keyNotFound(key, context): return .keyNotFound(key, prefixed(context))
    case let .dataCorrupted(context): return .dataCorrupted(prefixed(context))
    @unknown default: return self
    }
  }
}

// MARK: - Coding paths

/// A coding path, built up without copying arrays (`keys` makes the array
/// when an error or a user's code needs it).
indirect enum FirestoreCodingPath {
  case root
  case key(any CodingKey, FirestoreCodingPath)

  func appending(_ key: any CodingKey) -> FirestoreCodingPath {
    .key(key, self)
  }

  var keys: [any CodingKey] {
    var keys: [any CodingKey] = []
    var path = self
    while case let .key(key, parent) = path {
      keys.append(key)
      path = parent
    }
    return keys.reversed()
  }
}

struct FirestoreCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ string: String) {
    stringValue = string
    intValue = nil
  }

  init(index: Int) {
    stringValue = "Index \(index)"
    intValue = index
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }

  static let `super` = FirestoreCodingKey("super")
}

// MARK: - Decoder

/// A `Decoder` at one value.
private struct FirestoreValueDecoderAt: Decoder, SingleValueDecodingContainer {
  let value: FirestoreValue
  let context: FirestoreDecodingContext
  let path: FirestoreCodingPath

  var codingPath: [any CodingKey] { path.keys }
  var userInfo: [CodingUserInfoKey: Any] { context.userInfo }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard value.kind == .Map else {
      // The same error FirebaseDataDecoder gives.
      throw failure(KeyedDecodingContainer<Key>.self) { try $0.container(keyedBy: type) }
    }
    return KeyedDecodingContainer(FirestoreKeyedContainer<Key>(value: value, context: context, path: path))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case let .value(ref) = value, Bridge.KindOf(ref) == .Array else {
      throw failure(UnkeyedDecodingContainer.self) { try $0.unkeyedContainer() }
    }
    return FirestoreUnkeyedContainer(array: Bridge.ArrayOf(ref), context: context, path: path)
  }

  /// The error FirebaseDataDecoder throws for `attempt` at this value.
  private func failure<T>(_ type: T.Type, _ attempt: @escaping (any Decoder) throws -> T) -> Error {
    do {
      _ = try context.decodeConverted(value, as: ContainerProbe<T>.self, at: path)
      return DecodingError.typeMismatch(type, .init(codingPath: codingPath,
                                                    debugDescription: "Expected \(type)."))
    } catch {
      return error
    }
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    self
  }

  func decodeNil() -> Bool { context.isNull(value) }
  func decode(_ type: Bool.Type) throws -> Bool { try context.bool(value, at: path) }
  func decode(_ type: String.Type) throws -> String { try context.string(value, at: path) }
  func decode(_ type: Double.Type) throws -> Double { try context.double(value, at: path) }
  func decode(_ type: Float.Type) throws -> Float { try context.decodeConverted(value, as: type, at: path) }
  func decode(_ type: Int.Type) throws -> Int { try context.integer(value, as: type, at: path) }
  func decode(_ type: Int8.Type) throws -> Int8 { try context.integer(value, as: type, at: path) }
  func decode(_ type: Int16.Type) throws -> Int16 { try context.integer(value, as: type, at: path) }
  func decode(_ type: Int32.Type) throws -> Int32 { try context.integer(value, as: type, at: path) }
  func decode(_ type: Int64.Type) throws -> Int64 { try context.integer(value, as: type, at: path) }
  func decode(_ type: UInt.Type) throws -> UInt { try context.integer(value, as: type, at: path) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try context.integer(value, as: type, at: path) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try context.integer(value, as: type, at: path) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try context.integer(value, as: type, at: path) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try context.integer(value, as: type, at: path) }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { try context.unwrap(value, as: type, at: path) }
}

/// Asks FirebaseDataDecoder for a container, to get its error for a value
/// that has none of that kind.
private struct ContainerProbe<T>: Decodable {
  init(from decoder: any Decoder) throws {
    if T.self == UnkeyedDecodingContainer.self {
      _ = try decoder.unkeyedContainer()
    } else {
      _ = try decoder.container(keyedBy: FirestoreCodingKey.self)
    }
  }
}

// MARK: - Keyed container

private struct FirestoreKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  /// The map this container reads.
  let value: FirestoreValue
  let map: CppFieldMapRef
  let context: FirestoreDecodingContext
  let path: FirestoreCodingPath
  /// The entries by their converted keys, if the key strategy converts them.
  let convertedKeys: [String: Int]?

  init(value: FirestoreValue, context: FirestoreDecodingContext, path: FirestoreCodingPath) {
    self.value = value
    map = value.map
    self.context = context
    self.path = path
    convertedKeys = context.convertedKeys(map, at: path)
  }

  var codingPath: [any CodingKey] { path.keys }

  var allKeys: [Key] {
    if let convertedKeys {
      return convertedKeys.keys.compactMap { Key(stringValue: $0) }
    }
    return (0 ..< map.count).compactMap { Key(stringValue: String(Bridge.KeyAt(map, $0))) }
  }

  private func entry(_ key: Key) -> FirestoreValue? {
    if let convertedKeys {
      return convertedKeys[key.stringValue].map { .value(Bridge.ValueAt(map, $0)) }
    }
    let name = key.stringValue
    for index in 0 ..< map.count where name.matches(Bridge.KeyAt(map, index)) {
      return .value(Bridge.ValueAt(map, index))
    }
    return nil
  }

  /// The entry at `key`, which must be there.
  private func value(_ key: Key) throws -> FirestoreValue {
    guard let value = entry(key) else {
      throw DecodingError.keyNotFound(key, .init(
        codingPath: codingPath,
        debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."
      ))
    }
    return value
  }

  /// The entry at `key`, which must be there and not be null.
  private func nonNull(_ key: Key, _ type: Any.Type) throws -> FirestoreValue {
    let value = try value(key)
    if context.isNull(value) {
      throw DecodingError.valueNotFound(type, .init(
        codingPath: path.appending(key).keys,
        debugDescription: "Expected \(type) value but found null instead."
      ))
    }
    return value
  }

  func contains(_ key: Key) -> Bool { entry(key) != nil }

  func decodeNil(forKey key: Key) throws -> Bool {
    try context.isNull(value(key))
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    try context.bool(nonNull(key, type), at: path.appending(key))
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    try context.string(nonNull(key, type), at: path.appending(key))
  }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    try context.double(nonNull(key, type), at: path.appending(key))
  }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    try context.decodeConverted(nonNull(key, type), as: type, at: path.appending(key))
  }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try integer(type, key) }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try integer(type, key) }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try integer(type, key) }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try integer(type, key) }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try integer(type, key) }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try integer(type, key) }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try integer(type, key) }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try integer(type, key) }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try integer(type, key) }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try integer(type, key) }

  private func integer<T: FixedWidthInteger & Decodable>(_ type: T.Type, _ key: Key) throws -> T {
    try context.integer(nonNull(key, type), as: type, at: path.appending(key))
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    if type is StructureCodingUncodedUnkeyed.Type {
      // As FirebaseDataDecoder does: from this container's decoder, without
      // the key (@DocumentID reads the reference from userInfo).
      return try T(from: FirestoreValueDecoderAt(value: value, context: context, path: path))
    }
    // Nulls too: an optional decodes them, and anything else fails as
    // FirebaseDataDecoder fails.
    return try context.unwrap(value(key), as: type, at: path.appending(key))
  }

  func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type,
                                             forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
    try FirestoreValueDecoderAt(value: value(key), context: context, path: path.appending(key))
      .container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try FirestoreValueDecoderAt(value: value(key), context: context, path: path.appending(key))
      .unkeyedContainer()
  }

  func superDecoder() throws -> any Decoder {
    try decoder(at: FirestoreCodingKey.super, entry: entry(Key(stringValue: "super")!))
  }

  func superDecoder(forKey key: Key) throws -> any Decoder {
    try decoder(at: key, entry: entry(key))
  }

  /// A decoder at `entry`, or at a null where it's missing, as FirebaseDataDecoder gives.
  private func decoder(at key: any CodingKey, entry: FirestoreValue?) throws -> any Decoder {
    guard let entry else {
      return NullDecoder(codingPath: path.appending(key).keys, userInfo: context.userInfo)
    }
    return FirestoreValueDecoderAt(value: entry, context: context, path: path.appending(key))
  }
}

/// A decoder at a missing value, which decodes only as null.
private struct NullDecoder: Decoder, SingleValueDecodingContainer {
  let codingPath: [any CodingKey]
  let userInfo: [CodingUserInfoKey: Any]

  private func notFound(_ type: Any.Type) -> DecodingError {
    .valueNotFound(type, .init(codingPath: codingPath, debugDescription: "Expected \(type) value but found null instead."))
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self, .init(
      codingPath: codingPath,
      debugDescription: "Cannot get keyed decoding container -- found null value instead."
    ))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self, .init(
      codingPath: codingPath,
      debugDescription: "Cannot get unkeyed decoding container -- found null value instead."
    ))
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer { self }
  func decodeNil() -> Bool { true }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { throw notFound(type) }
}

// MARK: - Unkeyed container

private struct FirestoreUnkeyedContainer: UnkeyedDecodingContainer {
  let array: CppFieldArrayRef
  let context: FirestoreDecodingContext
  let path: FirestoreCodingPath
  private(set) var currentIndex = 0

  init(array: CppFieldArrayRef, context: FirestoreDecodingContext, path: FirestoreCodingPath) {
    self.array = array
    self.context = context
    self.path = path
  }

  var codingPath: [any CodingKey] { path.keys }
  var count: Int? { array.count }
  var isAtEnd: Bool { currentIndex >= array.count }

  private var indexPath: FirestoreCodingPath { path.appending(FirestoreCodingKey(index: currentIndex)) }

  private func atEnd(_ type: Any.Type) -> DecodingError {
    .valueNotFound(type, .init(codingPath: indexPath.keys, debugDescription: "Unkeyed container is at end."))
  }

  private var current: FirestoreValue { .value(Bridge.ElementAt(array, currentIndex)) }

  /// The next element, which must be there and not be null.
  private func next(_ type: Any.Type) throws -> FirestoreValue {
    guard !isAtEnd else { throw atEnd(type) }
    let value = current
    guard !context.isNull(value) else {
      throw DecodingError.valueNotFound(type, .init(codingPath: indexPath.keys,
                                                    debugDescription: "Expected \(type) but found null instead."))
    }
    return value
  }

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else { throw atEnd(Any?.self) }
    guard context.isNull(current) else { return false }
    currentIndex += 1
    return true
  }

  private mutating func decodeNext<T>(
    _ type: T.Type, _ read: (FirestoreDecodingContext, FirestoreValue, FirestoreCodingPath) throws -> T
  ) throws -> T {
    let value = try read(context, next(type), indexPath)
    currentIndex += 1
    return value
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeNext(type) { try $0.bool($1, at: $2) } }
  mutating func decode(_ type: String.Type) throws -> String { try decodeNext(type) { try $0.string($1, at: $2) } }
  mutating func decode(_ type: Double.Type) throws -> Double { try decodeNext(type) { try $0.double($1, at: $2) } }
  mutating func decode(_ type: Float.Type) throws -> Float {
    try decodeNext(type) { try $0.decodeConverted($1, as: type, at: $2) }
  }

  mutating func decode(_ type: Int.Type) throws -> Int { try integer(type) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }

  private mutating func integer<T: FixedWidthInteger & Decodable>(_ type: T.Type) throws -> T {
    try decodeNext(type) { try $0.integer($1, as: type, at: $2) }
  }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    // Nulls too: an optional decodes them.
    guard !isAtEnd else { throw atEnd(type) }
    let value = try context.unwrap(current, as: type, at: indexPath)
    currentIndex += 1
    return value
  }

  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey> {
    try decodeNext(KeyedDecodingContainer<NestedKey>.self) { context, value, path in
      try FirestoreValueDecoderAt(value: value, context: context, path: path).container(keyedBy: type)
    }
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    try decodeNext(UnkeyedDecodingContainer.self) { context, value, path in
      try FirestoreValueDecoderAt(value: value, context: context, path: path).unkeyedContainer()
    }
  }

  mutating func superDecoder() throws -> any Decoder {
    guard !isAtEnd else { throw atEnd(Decoder.self) }
    defer { currentIndex += 1 }
    return FirestoreValueDecoderAt(value: current, context: context, path: indexPath)
  }
}

// MARK: - Dictionaries

/// `[String: Value]`, which decodes its keys unconverted.
private protocol FirestoreStringKeyedDictionary {
  static func decode(from value: FirestoreValue, context: FirestoreDecodingContext,
                     at path: FirestoreCodingPath) throws -> Any
}

extension Dictionary: FirestoreStringKeyedDictionary where Key == String, Value: Decodable {
  fileprivate static func decode(from value: FirestoreValue, context: FirestoreDecodingContext,
                                 at path: FirestoreCodingPath) throws -> Any {
    guard value.kind == .Map else {
      return try context.decodeConverted(value, as: Self.self, at: path)
    }
    let map = value.map
    var result: [String: Value] = .init(minimumCapacity: map.count)
    for index in 0 ..< map.count {
      let key = String(Bridge.KeyAt(map, index))
      result[key] = try context.unwrap(.value(Bridge.ValueAt(map, index)), as: Value.self,
                                       at: path.appending(FirestoreCodingKey(key)))
    }
    return result
  }
}
