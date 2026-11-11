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
import SortedCollections

/// Decodes values straight from nodes, as `FirebaseDataDecoder` decodes
/// the Foundation values `val()` makes of them, without making those.
///
/// It uses the decoder's date, data, non-conforming float and key
/// strategies, and its `userInfo`. It differs where the Foundation values
/// lose information:
/// - A node whose keys are small integers ("0", "1", …) decodes as a keyed
///   container (a struct or a dictionary) too, not only as an array.
/// - Booleans don't decode as numbers.
/// - Passthrough types aren't supported (no Database type is one).
struct FNodeDecoder: Sendable {
    let context: FNodeDecodingContext

    init(_ decoder: FirebaseDataDecoder) {
        context = FNodeDecodingContext(decoder)
    }

    func decode<T: Decodable>(_ type: T.Type, from node: FNode) throws -> sending T {
        // A new value, which nothing else refers to (as with JSONDecoder,
        // unless a type's own `init(from:)` keeps something from `userInfo`).
        nonisolated(unsafe) let value = try context.unwrap(node, as: type, at: .root)
        return value
    }
}

/// The decoder's options, shared by the decoders and containers of one decode.
/// (Unchecked: it doesn't change, and FirebaseDataDecoder, whose strategies
/// these are, is unchecked too.)
final class FNodeDecodingContext: @unchecked Sendable {
    let dateStrategy: FirebaseDataDecoder.DateDecodingStrategy
    let dataStrategy: FirebaseDataDecoder.DataDecodingStrategy
    let floatStrategy: FirebaseDataDecoder.NonConformingFloatDecodingStrategy
    let keyStrategy: FirebaseDataDecoder.KeyDecodingStrategy
    let userInfo: [CodingUserInfoKey: Any]

    init(_ decoder: FirebaseDataDecoder) {
        dateStrategy = decoder.dateDecodingStrategy
        dataStrategy = decoder.dataDecodingStrategy
        floatStrategy = decoder.nonConformingFloatDecodingStrategy
        keyStrategy = decoder.keyDecodingStrategy
        userInfo = decoder.userInfo
    }

    // MARK: Values

    func unwrap<T: Decodable>(_ node: FNode, as type: T.Type, at path: FCodingPath) throws -> T {
        if type == Date.self {
            return try date(node, at: path) as! T
        } else if type == Data.self {
            return try data(node, at: path) as! T
        } else if type == URL.self {
            let string = try string(node, at: path)
            guard let url = URL(string: string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: path.keys, debugDescription: "Invalid URL string."))
            }
            return url as! T
        } else if type == Decimal.self {
            if case .leaf(.int64(let value)) = node.type {
                return Decimal(value) as! T
            }
            return Decimal(try float(node, as: Double.self, at: path)) as! T
        } else if let dictionary = type as? FNodeStringKeyedDictionary.Type {
            // As FirebaseDataDecoder does, without converting the keys.
            return try dictionary.decode(from: node, context: self, at: path) as! T
        }
        return try T(from: FNodeValueDecoder(node: node, context: self, path: path))
    }

    func bool(_ node: FNode, at path: FCodingPath) throws -> Bool {
        switch node.type {
        case .leaf(.bool(let value)):
            return value
        // As on Darwin, where an NSNumber 0 or 1 bridges to Bool.
        case .leaf(.int64(let value)) where value == 0 || value == 1:
            return value == 1
        case .leaf(.double(let value)) where value == 0 || value == 1:
            return value == 1
        default:
            throw mismatch(Bool.self, node, at: path)
        }
    }

    func integer<T: FixedWidthInteger>(_ node: FNode, as type: T.Type, at path: FCodingPath) throws -> T {
        let result: T?
        switch node.type {
        case .leaf(.int64(let value)): result = T(exactly: value)
        case .leaf(.double(let value)): result = T(exactly: value)
        default: throw mismatch(type, node, at: path)
        }
        guard let result else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: path.keys,
                debugDescription: "Parsed JSON number <\(node.val())> does not fit in \(type)."
            ))
        }
        return result
    }

    func float<T: BinaryFloatingPoint>(_ node: FNode, as type: T.Type, at path: FCodingPath) throws -> T {
        switch node.type {
        case .leaf(.int64(let value)):
            return T(value)
        case .leaf(.double(let value)):
            // Floats lose precision, but must fit.
            guard value.isNaN || abs(value) <= Double(T.greatestFiniteMagnitude) || value.isInfinite else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path.keys,
                    debugDescription: "Parsed JSON number \(value) does not fit in \(type)."
                ))
            }
            return T(value)
        case .leaf(.string(let string)):
            if case .convertFromString(let positiveInfinity, let negativeInfinity, let nan) = floatStrategy {
                switch string {
                case positiveInfinity: return .infinity
                case negativeInfinity: return -.infinity
                case nan: return .nan
                default: break
                }
            }
            throw mismatch(type, node, at: path)
        default:
            throw mismatch(type, node, at: path)
        }
    }

    func string(_ node: FNode, at path: FCodingPath) throws -> String {
        guard case .leaf(.string(let value)) = node.type else { throw mismatch(String.self, node, at: path) }
        return value
    }

    private func date(_ node: FNode, at path: FCodingPath) throws -> Date {
        switch dateStrategy {
        case .deferredToDate:
            return try Date(from: FNodeValueDecoder(node: node, context: self, path: path))
        case .secondsSince1970:
            return Date(timeIntervalSince1970: try float(node, as: Double.self, at: path))
        case .millisecondsSince1970:
            return Date(timeIntervalSince1970: try float(node, as: Double.self, at: path) / 1000)
        case .iso8601:
            guard let date = try? Date(try string(node, at: path), strategy: .iso8601) else {
                throw DecodingError.dataCorrupted(.init(codingPath: path.keys,
                                                        debugDescription: "Expected date string to be ISO8601-formatted."))
            }
            return date
        case .formatted(let formatter):
            guard let date = formatter.date(from: try string(node, at: path)) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: path.keys,
                    debugDescription: "Date string does not match format expected by formatter."
                ))
            }
            return date
        case .custom(let closure):
            return try closure(FNodeValueDecoder(node: node, context: self, path: path))
        }
    }

    private func data(_ node: FNode, at path: FCodingPath) throws -> Data {
        switch dataStrategy {
        case .deferredToData:
            return try Data(from: FNodeValueDecoder(node: node, context: self, path: path))
        case .base64, .blob:
            // A node can't hold a blob; .blob reads Base64 too, as upstream does.
            guard let data = Data(base64Encoded: try string(node, at: path)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: path.keys,
                                                        debugDescription: "Encountered Data is not valid Base64."))
            }
            return data
        case .custom(let closure):
            return try closure(FNodeValueDecoder(node: node, context: self, path: path))
        }
    }

    func mismatch(_ type: Any.Type, _ node: FNode, at path: FCodingPath) -> DecodingError {
        if node.isEmpty {
            return .valueNotFound(type, .init(codingPath: path.keys,
                                              debugDescription: "Expected \(type) value but found null instead."))
        }
        let reality: String
        switch node.type {
        case .leaf(.bool): reality = "a boolean"
        case .leaf(.int64), .leaf(.double): reality = "a number"
        case .leaf(.string): reality = "a string"
        case .leaf(.deferredValue): reality = "a server value"
        case .children: reality = node.arrayLength == nil ? "a dictionary" : "an array"
        case .empty: reality = "null"
        }
        return .typeMismatch(type, .init(codingPath: path.keys,
                                         debugDescription: "Expected to decode \(type) but found \(reality) instead."))
    }

    // MARK: Keys

    /// The children by the keys a keyed container sees: the stored keys,
    /// converted by the key strategy.
    func keyed(_ children: FChildren, at path: FCodingPath) -> [String: KeyIndex]? {
        switch keyStrategy {
        case .useDefaultKeys:
            return nil
        case .convertFromSnakeCase:
            var keys: [String: KeyIndex] = [:]
            for (key, _) in children {
                keys[FirebaseDataDecoder.KeyDecodingStrategy._convertFromSnakeCase(key.key)] = key
            }
            return keys
        case .custom(let convert):
            var keys: [String: KeyIndex] = [:]
            let codingPath = path.keys
            for (key, _) in children {
                keys[convert(codingPath + [FCodingKey(key.key)]).stringValue] = key
            }
            return keys
        }
    }
}

// MARK: - Coding paths

/// A coding path, built up without copying arrays (`keys` makes the array
/// when an error or a user's code needs it).
indirect enum FCodingPath {
    case root
    case key(any CodingKey, FCodingPath)

    func appending(_ key: any CodingKey) -> FCodingPath {
        .key(key, self)
    }

    var keys: [any CodingKey] {
        var keys: [any CodingKey] = []
        var path = self
        while case .key(let key, let parent) = path {
            keys.append(key)
            path = parent
        }
        return keys.reversed()
    }
}

struct FCodingKey: CodingKey {
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

    static let `super` = FCodingKey("super")
}

// MARK: - Decoder

/// A `Decoder` at one node.
private struct FNodeValueDecoder: Decoder, SingleValueDecodingContainer {
    let node: FNode
    let context: FNodeDecodingContext
    let path: FCodingPath

    var codingPath: [any CodingKey] { path.keys }
    var userInfo: [CodingUserInfoKey: Any] { context.userInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .children(let children) = node.type else {
            if node.isEmpty {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Cannot get keyed decoding container -- found null value instead."
                ))
            }
            throw context.mismatch([String: Any].self, node, at: path)
        }
        return KeyedDecodingContainer(FNodeKeyedContainer<Key>(children: children, context: context, path: path))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let elements = node.arrayElements else {
            if node.isEmpty {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Cannot get unkeyed decoding container -- found null value instead."
                ))
            }
            throw context.mismatch([Any].self, node, at: path)
        }
        return FNodeUnkeyedContainer(elements: elements, context: context, path: path)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        self
    }

    func decodeNil() -> Bool { node.isEmpty }
    func decode(_ type: Bool.Type) throws -> Bool { try context.bool(node, at: path) }
    func decode(_ type: String.Type) throws -> String { try context.string(node, at: path) }
    func decode(_ type: Double.Type) throws -> Double { try context.float(node, as: type, at: path) }
    func decode(_ type: Float.Type) throws -> Float { try context.float(node, as: type, at: path) }
    func decode(_ type: Int.Type) throws -> Int { try context.integer(node, as: type, at: path) }
    func decode(_ type: Int8.Type) throws -> Int8 { try context.integer(node, as: type, at: path) }
    func decode(_ type: Int16.Type) throws -> Int16 { try context.integer(node, as: type, at: path) }
    func decode(_ type: Int32.Type) throws -> Int32 { try context.integer(node, as: type, at: path) }
    func decode(_ type: Int64.Type) throws -> Int64 { try context.integer(node, as: type, at: path) }
    func decode(_ type: UInt.Type) throws -> UInt { try context.integer(node, as: type, at: path) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try context.integer(node, as: type, at: path) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try context.integer(node, as: type, at: path) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try context.integer(node, as: type, at: path) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try context.integer(node, as: type, at: path) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try context.unwrap(node, as: type, at: path) }
}

// MARK: - Keyed container

private struct FNodeKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let children: FChildren
    let context: FNodeDecodingContext
    let path: FCodingPath
    /// The keys by their converted names, if the key strategy converts them.
    let convertedKeys: [String: KeyIndex]?

    init(children: FChildren, context: FNodeDecodingContext, path: FCodingPath) {
        self.children = children
        self.context = context
        self.path = path
        convertedKeys = context.keyed(children, at: path)
    }

    var codingPath: [any CodingKey] { path.keys }

    var allKeys: [Key] {
        if let convertedKeys {
            return convertedKeys.keys.compactMap { Key(stringValue: $0) }
        }
        return children.keys.compactMap { Key(stringValue: $0.key) }
    }

    private func child(_ key: Key) -> FNode {
        if let convertedKeys {
            return convertedKeys[key.stringValue].flatMap { children[$0] } ?? .empty
        }
        return children[KeyIndex(key: key.stringValue)] ?? .empty
    }

    /// The child at `key`, which must be there.
    private func value(_ key: Key) throws -> FNode {
        let node = child(key)
        guard !node.isEmpty else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: codingPath,
                debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."
            ))
        }
        return node
    }

    func contains(_ key: Key) -> Bool { !child(key).isEmpty }

    func decodeNil(forKey key: Key) throws -> Bool {
        // Null children aren't stored, so a key is either there or not.
        _ = try value(key)
        return false
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try context.bool(value(key), at: path.appending(key))
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try context.string(value(key), at: path.appending(key))
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try context.float(value(key), as: type, at: path.appending(key))
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try context.float(value(key), as: type, at: path.appending(key))
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

    private func integer<T: FixedWidthInteger>(_ type: T.Type, _ key: Key) throws -> T {
        try context.integer(value(key), as: type, at: path.appending(key))
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try context.unwrap(value(key), as: type, at: path.appending(key))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type,
                                               forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try FNodeValueDecoder(node: value(key), context: context, path: path.appending(key)).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try FNodeValueDecoder(node: value(key), context: context, path: path.appending(key)).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        FNodeValueDecoder(node: children[KeyIndex(key: FCodingKey.super.stringValue)] ?? .empty,
                          context: context, path: path.appending(FCodingKey.super))
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        FNodeValueDecoder(node: child(key), context: context, path: path.appending(key))
    }
}

// MARK: - Unkeyed container

private struct FNodeUnkeyedContainer: UnkeyedDecodingContainer {
    let elements: [FNode]
    let context: FNodeDecodingContext
    let path: FCodingPath
    private(set) var currentIndex = 0

    init(elements: [FNode], context: FNodeDecodingContext, path: FCodingPath) {
        self.elements = elements
        self.context = context
        self.path = path
    }

    var codingPath: [any CodingKey] { path.keys }
    var count: Int? { elements.count }
    var isAtEnd: Bool { currentIndex >= elements.count }

    private var indexPath: FCodingPath { path.appending(FCodingKey(index: currentIndex)) }

    /// The next element, which must be there and not be null.
    private func next(_ type: Any.Type) throws -> FNode {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, .init(codingPath: indexPath.keys,
                                                          debugDescription: "Unkeyed container is at end."))
        }
        let node = elements[currentIndex]
        guard !node.isEmpty else {
            throw DecodingError.valueNotFound(type, .init(codingPath: indexPath.keys,
                                                          debugDescription: "Expected \(type) but found null instead."))
        }
        return node
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any?.self, .init(codingPath: indexPath.keys,
                                                               debugDescription: "Unkeyed container is at end."))
        }
        guard elements[currentIndex].isEmpty else { return false }
        currentIndex += 1
        return true
    }

    private mutating func decodeNext<T>(
        _ type: T.Type, _ read: (FNodeDecodingContext, FNode, FCodingPath) throws -> T
    ) throws -> T {
        let value = try read(context, next(type), indexPath)
        currentIndex += 1
        return value
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeNext(type) { try $0.bool($1, at: $2) } }
    mutating func decode(_ type: String.Type) throws -> String { try decodeNext(type) { try $0.string($1, at: $2) } }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeNext(type) { try $0.float($1, as: type, at: $2) } }
    mutating func decode(_ type: Float.Type) throws -> Float { try decodeNext(type) { try $0.float($1, as: type, at: $2) } }
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

    private mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        try decodeNext(type) { try $0.integer($1, as: type, at: $2) }
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Nulls too: an optional decodes them.
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, .init(codingPath: indexPath.keys,
                                                          debugDescription: "Unkeyed container is at end."))
        }
        let value = try context.unwrap(elements[currentIndex], as: type, at: indexPath)
        currentIndex += 1
        return value
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey> {
        try decodeNext(KeyedDecodingContainer<NestedKey>.self) { context, node, path in
            try FNodeValueDecoder(node: node, context: context, path: path).container(keyedBy: type)
        }
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try decodeNext(UnkeyedDecodingContainer.self) { context, node, path in
            try FNodeValueDecoder(node: node, context: context, path: path).unkeyedContainer()
        }
    }

    mutating func superDecoder() throws -> any Decoder {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Decoder.self, .init(codingPath: indexPath.keys,
                                                                  debugDescription: "Unkeyed container is at end."))
        }
        defer { currentIndex += 1 }
        return FNodeValueDecoder(node: elements[currentIndex], context: context, path: indexPath)
    }
}

// MARK: - Dictionaries

/// `[String: Value]`, which decodes its keys unconverted.
private protocol FNodeStringKeyedDictionary {
    static func decode(from node: FNode, context: FNodeDecodingContext, at path: FCodingPath) throws -> Any
}

extension Dictionary: FNodeStringKeyedDictionary where Key == String, Value: Decodable {
    fileprivate static func decode(from node: FNode, context: FNodeDecodingContext,
                                   at path: FCodingPath) throws -> Any {
        guard case .children(let children) = node.type else {
            throw context.mismatch(Self.self, node, at: path)
        }
        var result: [String: Value] = .init(minimumCapacity: children.count)
        for (key, child) in children {
            result[key.key] = try context.unwrap(child, as: Value.self, at: path.appending(FCodingKey(key.key)))
        }
        return result
    }
}

// MARK: - Arrays

extension FNode {
    /// The children as the array `val()` makes of them: when all keys are
    /// integers (without leading zeros) and at least half the indices are
    /// there. Nil if `val()` makes a dictionary.
    var arrayElements: [FNode]? {
        guard let length = arrayLength, case .children(let children) = type else { return nil }
        var elements = [FNode](repeating: .empty, count: length)
        for (key, child) in children {
            if let index = FUtilities.intForString(key.key), index >= 0 {
                elements[index] = child
            }
        }
        return elements
    }

    /// The length of the array `val()` makes of the children, if it makes one.
    var arrayLength: Int? {
        guard case .children(let children) = type, !children.isEmpty else { return nil }
        var maxKey = 0
        for (key, _) in children {
            // Integer keys come first, so a dictionary is known at its first key.
            let utf8 = key.key.utf8
            if utf8.first == UInt8(ascii: "0") && utf8.count > 1 { return nil }
            guard let int = FUtilities.intForString(key.key) else { return nil }
            maxKey = Swift.max(maxKey, int)
        }
        return maxKey < 2 * children.count ? maxKey + 1 : nil
    }
}
