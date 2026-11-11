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

/// Encodes values straight to nodes, as `FirebaseDataEncoder` and
/// `nodeFrom` together make them, without the Foundation values between.
///
/// It uses the encoder's date, data, non-conforming float and key
/// strategies, and its `userInfo`, and applies the rules of `nodeFrom`
/// (`.sv` server values, `.priority`, `.value`, nulls and empty containers
/// dropped). Unlike `nodeFrom`, invalid data (keys with `.#$[]/`, NaN,
/// infinities, strings over 10 MB) throws `EncodingError.invalidValue`
/// instead of stopping the program. `.blob` data can't be stored, so it
/// throws too.
struct FNodeEncoder: Sendable {
    let context: FNodeEncodingContext

    init(_ encoder: FirebaseDataEncoder) {
        context = FNodeEncodingContext(encoder)
    }

    func encode<T: Encodable>(_ value: T) throws -> FNode {
        let encoded = try context.box(value, at: .root)
        return try context.node(encoded, depth: 0, path: .root)
    }
}

/// A value being encoded. Containers are references, so nested containers
/// and super encoders can fill them in after they're placed.
enum FEncodedValue {
    case null
    case leaf(LeafValue)
    case object(FEncodedObject)
    case array(FEncodedArray)
    /// What an encoder handed out for later (a super encoder) encodes.
    case pending(FEncodedSlot)
}

final class FEncodedObject {
    var children: [String: FEncodedValue] = [:]
}

final class FEncodedArray {
    var elements: [FEncodedValue] = []
}

final class FEncodedSlot {
    var value: FEncodedValue?
}

/// The encoder's options, shared by one encode. (Unchecked: it doesn't
/// change, as FNodeDecodingContext.)
final class FNodeEncodingContext: @unchecked Sendable {
    let dateStrategy: FirebaseDataEncoder.DateEncodingStrategy
    let dataStrategy: FirebaseDataEncoder.DataEncodingStrategy
    let floatStrategy: FirebaseDataEncoder.NonConformingFloatEncodingStrategy
    let keyStrategy: FirebaseDataEncoder.KeyEncodingStrategy
    let userInfo: [CodingUserInfoKey: Any]

    init(_ encoder: FirebaseDataEncoder) {
        dateStrategy = encoder.dateEncodingStrategy
        dataStrategy = encoder.dataEncodingStrategy
        floatStrategy = encoder.nonConformingFloatEncodingStrategy
        keyStrategy = encoder.keyEncodingStrategy
        userInfo = encoder.userInfo
    }

    // MARK: Values

    func box<T: Encodable>(_ value: T, at path: FCodingPath) throws -> FEncodedValue {
        switch value {
        case let date as Date:
            return try box(date, at: path)
        case let data as Data:
            return try box(data, at: path)
        case let url as URL:
            return .leaf(.string(url.absoluteString))
        case let decimal as Decimal:
            return .leaf(.number(NSDecimalNumber(decimal: decimal)))
        case let dictionary as FNodeStringKeyedEncodable:
            // As FirebaseDataEncoder does, without converting the keys.
            return try dictionary.box(context: self, at: path)
        default:
            let encoder = FNodeValueEncoder(context: self, path: path)
            try value.encode(to: encoder)
            // A value that encodes nothing is an empty object, as before.
            return encoder.slot.value ?? .object(FEncodedObject())
        }
    }

    func float<T: BinaryFloatingPoint & LosslessStringConvertible>(_ value: T, at path: FCodingPath) throws
        -> FEncodedValue {
        guard value.isFinite else {
            guard case .convertToString(let positiveInfinity, let negativeInfinity, let nan) = floatStrategy else {
                throw EncodingError.invalidValue(value, .init(
                    codingPath: path.keys,
                    debugDescription: "Unable to encode \(T.self).\(value) directly. Use "
                        + "NonConformingFloatEncodingStrategy.convertToString to specify how it should be encoded."
                ))
            }
            return .leaf(.string(value.isNaN ? nan : value < 0 ? negativeInfinity : positiveInfinity))
        }
        return .leaf(.double(Double(value)))
    }

    private func box(_ date: Date, at path: FCodingPath) throws -> FEncodedValue {
        switch dateStrategy {
        case .deferredToDate:
            return try encoded(at: path) { try date.encode(to: $0) }
        case .secondsSince1970:
            return .leaf(.double(date.timeIntervalSince1970))
        case .millisecondsSince1970:
            return .leaf(.double(1000 * date.timeIntervalSince1970))
        case .iso8601:
            let style = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .standard,
                                                timeSeparator: .colon)
            return .leaf(.string(date.formatted(style)))
        case .formatted(let formatter):
            return .leaf(.string(formatter.string(from: date)))
        case .custom(let closure):
            return try encoded(at: path) { try closure(date, $0) }
        }
    }

    private func box(_ data: Data, at path: FCodingPath) throws -> FEncodedValue {
        switch dataStrategy {
        case .deferredToData:
            return try encoded(at: path) { try data.encode(to: $0) }
        case .base64:
            return .leaf(.string(data.base64EncodedString()))
        case .blob:
            throw EncodingError.invalidValue(data, .init(codingPath: path.keys,
                                                         debugDescription: "The Database can't store blobs."))
        case .custom(let closure):
            return try encoded(at: path) { try closure(data, $0) }
        }
    }

    private func encoded(at path: FCodingPath, _ encode: (any Encoder) throws -> Void) throws -> FEncodedValue {
        let encoder = FNodeValueEncoder(context: self, path: path)
        try encode(encoder)
        return encoder.slot.value ?? .object(FEncodedObject())
    }

    func key(_ key: some CodingKey, at path: FCodingPath) -> String {
        switch keyStrategy {
        case .useDefaultKeys:
            key.stringValue
        case .convertToSnakeCase:
            FirebaseDataEncoder.KeyEncodingStrategy._convertToSnakeCase(key.stringValue)
        case .custom(let convert):
            convert(path.appending(key).keys).stringValue
        }
    }

    // MARK: Nodes

    /// The node of an encoded value, by the rules of `nodeFrom`.
    func node(_ value: FEncodedValue, depth: Int, path: FCodingPath) throws -> FNode {
        guard depth <= kFirebaseMaxObjectDepth else {
            throw invalid(value, at: path, "Max object depth exceeded.")
        }
        switch value {
        case .null:
            return .empty
        case .leaf(let leaf):
            try validate(leaf, at: path)
            return .leaf(leaf)
        case .pending(let slot):
            return try node(slot.value ?? .null, depth: depth, path: path)
        case .array(let array):
            var children: [(key: KeyIndex, value: FNode)] = []
            for (index, element) in array.elements.enumerated() {
                let child = try node(element, depth: depth + 1, path: path.appending(FCodingKey(index: index)))
                if !child.isEmpty {
                    children.append((KeyIndex(key: String(index)), child))
                }
            }
            return children.isEmpty ? .empty : .children(SortedDictionary(sortedKeysWithValues: children))
        case .object(let object):
            return try node(object, depth: depth, path: path)
        }
    }

    private func node(_ object: FEncodedObject, depth: Int, path: FCodingPath) throws -> FNode {
        if let serverValue = object.children[kServerValueSubKey] {
            guard object.children.count == 1 else {
                throw invalid(.object(object), at: path, "Cannot store other keys with server value keys.")
            }
            return .leaf(.deferredValue(try serverValueOp(serverValue, at: path)))
        }
        var priority: FNode?
        if let value = object.children[kPayloadPriority] {
            let node = try node(value, depth: depth + 1, path: path.appending(FCodingKey(kPayloadPriority)))
            switch node.type {
            case .empty: break
            case .leaf(.string), .leaf(.int64), .leaf(.double): priority = node
            default: throw invalid(value, at: path, "Invalid priority: must be a string or a number.")
            }
        }
        if let value = object.children[kPayloadValue] {
            let node = try node(value, depth: depth + 1, path: path.appending(FCodingKey(kPayloadValue)))
            guard case .leaf(let leaf) = node.type else {
                throw invalid(value, at: path, "Invalid data type used with .value: can only be a string, number or boolean.")
            }
            return .leaf(leaf, priority: priority)
        }
        var children: [(key: KeyIndex, value: FNode)] = []
        children.reserveCapacity(object.children.count)
        for (key, value) in object.children where key != kPayloadPriority {
            let childPath = path.appending(FCodingKey(key))
            guard FValidation.isValidKey(key) else {
                throw invalid(value, at: childPath,
                              "Invalid key \"\(key)\": keys must be non-empty and can't contain '/' '.' '#' '$' '[' or ']'.")
            }
            let child = try node(value, depth: depth + 1, path: childPath)
            if !child.isEmpty {
                children.append((KeyIndex(key: key), child))
            }
        }
        guard !children.isEmpty else { return .empty }
        children.sort { $0.key < $1.key }
        return .children(SortedDictionary(sortedKeysWithValues: children), priority: priority)
    }

    private func serverValueOp(_ value: FEncodedValue, at path: FCodingPath) throws -> ServerValueOp {
        switch value {
        case .leaf(.string(ServerValues.timestampKey)):
            return .timestamp
        case .object(let object):
            if object.children.count == 1, case .leaf(let delta) = object.children[ServerValues.incrementKey],
               delta.doubleValue != nil {
                return .increment(delta)
            }
        default:
            break
        }
        throw invalid(value, at: path, "Unexpected server value.")
    }

    private func validate(_ leaf: LeafValue, at path: FCodingPath) throws {
        switch leaf {
        case .double(let double) where !double.isFinite:
            throw invalid(.leaf(leaf), at: path, "Cannot store \(double).")
        case .string(let string) where string.utf8.count > kFirebaseMaxLeafSize:
            throw invalid(.leaf(leaf), at: path, "String exceeds max size of \(kFirebaseMaxLeafSize) utf8 bytes.")
        default:
            break
        }
    }

    private func invalid(_ value: FEncodedValue, at path: FCodingPath, _ description: String) -> EncodingError {
        .invalidValue(value, .init(codingPath: path.keys, debugDescription: description))
    }
}

// MARK: - Encoder

/// An `Encoder` for one value, which ends up in `slot`.
private final class FNodeValueEncoder: Encoder, SingleValueEncodingContainer {
    let context: FNodeEncodingContext
    let path: FCodingPath
    let slot: FEncodedSlot

    init(context: FNodeEncodingContext, path: FCodingPath, slot: FEncodedSlot = FEncodedSlot()) {
        self.context = context
        self.path = path
        self.slot = slot
    }

    var codingPath: [any CodingKey] { path.keys }
    var userInfo: [CodingUserInfoKey: Any] { context.userInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        // Asking again gives the same container.
        let object: FEncodedObject
        if case .object(let existing) = slot.value {
            object = existing
        } else {
            object = FEncodedObject()
            slot.value = .object(object)
        }
        return KeyedEncodingContainer(FNodeKeyedEncodingContainer<Key>(object: object, context: context, path: path))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        let array: FEncodedArray
        if case .array(let existing) = slot.value {
            array = existing
        } else {
            array = FEncodedArray()
            slot.value = .array(array)
        }
        return FNodeUnkeyedEncodingContainer(array: array, context: context, path: path)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        self
    }

    func encodeNil() { slot.value = .null }
    func encode(_ value: Bool) { slot.value = .leaf(.bool(value)) }
    func encode(_ value: String) { slot.value = .leaf(.string(value)) }
    func encode(_ value: Double) throws { slot.value = try context.float(value, at: path) }
    func encode(_ value: Float) throws { slot.value = try context.float(value, at: path) }
    func encode(_ value: Int) { slot.value = .leaf(.int(value)) }
    func encode(_ value: Int8) { slot.value = .leaf(.int(value)) }
    func encode(_ value: Int16) { slot.value = .leaf(.int(value)) }
    func encode(_ value: Int32) { slot.value = .leaf(.int(value)) }
    func encode(_ value: Int64) { slot.value = .leaf(.int(value)) }
    func encode(_ value: UInt) { slot.value = .leaf(.int(value)) }
    func encode(_ value: UInt8) { slot.value = .leaf(.int(value)) }
    func encode(_ value: UInt16) { slot.value = .leaf(.int(value)) }
    func encode(_ value: UInt32) { slot.value = .leaf(.int(value)) }
    func encode(_ value: UInt64) { slot.value = .leaf(.int(value)) }
    func encode<T: Encodable>(_ value: T) throws { slot.value = try context.box(value, at: path) }
}

extension LeafValue {
    /// An integer as `.int64`, or `.double` if it doesn't fit (as `number(_:)`).
    static func int(_ value: some BinaryInteger) -> LeafValue {
        Int64(exactly: value).map(LeafValue.int64) ?? .double(Double(value))
    }
}

private struct FNodeKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let object: FEncodedObject
    let context: FNodeEncodingContext
    let path: FCodingPath

    var codingPath: [any CodingKey] { path.keys }

    private func set(_ value: FEncodedValue, _ key: Key) {
        object.children[context.key(key, at: path)] = value
    }

    mutating func encodeNil(forKey key: Key) { set(.null, key) }
    mutating func encode(_ value: Bool, forKey key: Key) { set(.leaf(.bool(value)), key) }
    mutating func encode(_ value: String, forKey key: Key) { set(.leaf(.string(value)), key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { set(try context.float(value, at: path.appending(key)), key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { set(try context.float(value, at: path.appending(key)), key) }
    mutating func encode(_ value: Int, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: Int8, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: Int16, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: Int32, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: Int64, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: UInt, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: UInt8, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: UInt16, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: UInt32, forKey key: Key) { set(.leaf(.int(value)), key) }
    mutating func encode(_ value: UInt64, forKey key: Key) { set(.leaf(.int(value)), key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        set(try context.box(value, at: path.appending(key)), key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type,
                                                        forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let nested = FEncodedObject()
        set(.object(nested), key)
        return KeyedEncodingContainer(FNodeKeyedEncodingContainer<NestedKey>(object: nested, context: context,
                                                                            path: path.appending(key)))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let nested = FEncodedArray()
        set(.array(nested), key)
        return FNodeUnkeyedEncodingContainer(array: nested, context: context, path: path.appending(key))
    }

    mutating func superEncoder() -> any Encoder {
        superEncoder(at: FCodingKey.super.stringValue, codingKey: FCodingKey.super)
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        superEncoder(at: context.key(key, at: path), codingKey: key)
    }

    private func superEncoder(at key: String, codingKey: some CodingKey) -> any Encoder {
        let slot = FEncodedSlot()
        object.children[key] = .pending(slot)
        return FNodeValueEncoder(context: context, path: path.appending(codingKey), slot: slot)
    }
}

private struct FNodeUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let array: FEncodedArray
    let context: FNodeEncodingContext
    let path: FCodingPath

    var codingPath: [any CodingKey] { path.keys }
    var count: Int { array.elements.count }

    private var nextPath: FCodingPath { path.appending(FCodingKey(index: count)) }

    private func append(_ value: FEncodedValue) {
        array.elements.append(value)
    }

    mutating func encodeNil() { append(.null) }
    mutating func encode(_ value: Bool) { append(.leaf(.bool(value))) }
    mutating func encode(_ value: String) { append(.leaf(.string(value))) }
    mutating func encode(_ value: Double) throws { append(try context.float(value, at: nextPath)) }
    mutating func encode(_ value: Float) throws { append(try context.float(value, at: nextPath)) }
    mutating func encode(_ value: Int) { append(.leaf(.int(value))) }
    mutating func encode(_ value: Int8) { append(.leaf(.int(value))) }
    mutating func encode(_ value: Int16) { append(.leaf(.int(value))) }
    mutating func encode(_ value: Int32) { append(.leaf(.int(value))) }
    mutating func encode(_ value: Int64) { append(.leaf(.int(value))) }
    mutating func encode(_ value: UInt) { append(.leaf(.int(value))) }
    mutating func encode(_ value: UInt8) { append(.leaf(.int(value))) }
    mutating func encode(_ value: UInt16) { append(.leaf(.int(value))) }
    mutating func encode(_ value: UInt32) { append(.leaf(.int(value))) }
    mutating func encode(_ value: UInt64) { append(.leaf(.int(value))) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        append(try context.box(value, at: nextPath))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey> {
        let nested = FEncodedObject()
        let path = nextPath
        append(.object(nested))
        return KeyedEncodingContainer(FNodeKeyedEncodingContainer<NestedKey>(object: nested, context: context,
                                                                            path: path))
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let nested = FEncodedArray()
        let path = nextPath
        append(.array(nested))
        return FNodeUnkeyedEncodingContainer(array: nested, context: context, path: path)
    }

    mutating func superEncoder() -> any Encoder {
        let slot = FEncodedSlot()
        let path = nextPath
        append(.pending(slot))
        return FNodeValueEncoder(context: context, path: path, slot: slot)
    }
}

// MARK: - Dictionaries

/// `[String: Value]`, which encodes its keys unconverted.
private protocol FNodeStringKeyedEncodable {
    func box(context: FNodeEncodingContext, at path: FCodingPath) throws -> FEncodedValue
}

extension Dictionary: FNodeStringKeyedEncodable where Key == String, Value: Encodable {
    fileprivate func box(context: FNodeEncodingContext, at path: FCodingPath) throws -> FEncodedValue {
        let object = FEncodedObject()
        object.children.reserveCapacity(count)
        for (key, value) in self {
            object.children[key] = try context.box(value, at: path.appending(FCodingKey(key)))
        }
        return .object(object)
    }
}
