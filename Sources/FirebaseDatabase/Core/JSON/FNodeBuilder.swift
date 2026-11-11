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

import Foundation
import NIOCore
import SortedCollections

/// Nodes from JSON, by the rules `FSnapshotUtilities.nodeFrom` applies to
/// Foundation values: nulls and empty objects are dropped, arrays are objects
/// with the keys "0", "1", …, `.priority` sets the priority, `.value` holds a
/// leaf's value, and `.sv` is a server value. Other keys starting with "."
/// are ignored. (Unlike user writes, the keys aren't validated: this is data
/// from the server or the cache.)
extension FJSONScanner {
    /// Reads a value as a node.
    mutating func readNode() throws -> FNode {
        try readNode(depth: 0)
    }

    /// Reads an object of paths and values as a merge's writes, keeping nulls
    /// (as empty nodes: they remove the data).
    mutating func readMerge() throws -> [String: FNode] {
        var writes: [String: FNode] = [:]
        try beginObject()
        var first = true
        while let path = try nextKey(&first) {
            writes[path] = try readNode(depth: 1)
        }
        return writes
    }

    @_lifetime(self: copy self)
    private mutating func readNode(depth: Int) throws -> FNode {
        guard depth <= kFirebaseMaxObjectDepth else { throw error(.tooDeep) }
        switch try peek() {
        case UInt8(ascii: "{"):
            return try readObjectNode(depth: depth)
        case UInt8(ascii: "["):
            return try readArrayNode(depth: depth)
        case UInt8(ascii: "\""):
            return .leaf(.string(try readString()))
        case UInt8(ascii: "t"), UInt8(ascii: "f"):
            return .leaf(.bool(try readBool()))
        case UInt8(ascii: "n"):
            _ = try readNull()
            return .empty
        default:
            return .leaf(try readNumber())
        }
    }

    @_lifetime(self: copy self)
    private mutating func readObjectNode(depth: Int) throws -> FNode {
        try beginObject()
        var children: [FChild] = []
        var sorted = true
        var priority: FNode?
        var leaf: LeafValue?
        var first = true
        while let key = try nextKey(&first) {
            if key.utf8.first == UInt8(ascii: ".") {
                switch key {
                case kPayloadPriority:
                    let node = try readNode(depth: depth + 1)
                    priority = node.isEmpty ? nil : node
                case kPayloadValue:
                    if case .leaf(let value) = try readNode(depth: depth + 1).type {
                        leaf = value
                    }
                case kServerValueSubKey:
                    leaf = .deferredValue(try readServerValue())
                default:
                    try skipValue()
                }
                continue
            }
            let child = try readNode(depth: depth + 1)
            guard !child.isEmpty else { continue }
            let key = KeyIndex(key: key)
            if sorted, let last = children.last?.key, !(last < key) {
                sorted = false
            }
            children.append(FChild(key: key, value: child))
        }
        if let leaf {
            return .leaf(leaf, priority: priority)
        }
        guard !children.isEmpty else { return .empty }
        if !sorted {
            children = Self.sortedRemovingDuplicates(children)
        }
        return .children(FChildren(sortedChildren: children), priority: priority)
    }

    /// Children in key order; for a key that's there more than once, the last
    /// value (as JSONSerialization keeps).
    private static func sortedRemovingDuplicates(_ children: [FChild]) -> [FChild] {
        var children = children
        // Stable, so of equal keys the last stays last.
        children.sort { $0.key < $1.key }
        guard zip(children, children.dropFirst()).contains(where: { $0.key == $1.key }) else { return children }
        var result: [FChild] = []
        result.reserveCapacity(children.count)
        for child in children {
            if result.last?.key == child.key {
                result[result.count - 1] = child
            } else {
                result.append(child)
            }
        }
        return result
    }

    @_lifetime(self: copy self)
    private mutating func readArrayNode(depth: Int) throws -> FNode {
        try beginArray()
        var children: [FChild] = []
        var index = 0
        var first = true
        while try nextElement(&first) {
            let child = try readNode(depth: depth + 1)
            if !child.isEmpty {
                children.append(FChild(key: KeyIndex(key: String(index)), value: child))
            }
            index += 1
        }
        guard !children.isEmpty else { return .empty }
        return .children(FChildren(sortedChildren: children))
    }

    /// `"timestamp"` or `{"increment": delta}`.
    private mutating func readServerValue() throws -> ServerValueOp {
        switch try peek() {
        case UInt8(ascii: "\""):
            guard try readString() == ServerValues.timestampKey else { throw error(.invalidServerValue) }
            return .timestamp
        case UInt8(ascii: "{"):
            try beginObject()
            var delta: LeafValue?
            var first = true
            while let key = try nextKey(&first) {
                if key == ServerValues.incrementKey {
                    delta = try readNumber()
                } else {
                    try skipValue()
                }
            }
            guard let delta else { throw error(.invalidServerValue) }
            return .increment(delta)
        default:
            throw error(.invalidServerValue)
        }
    }
}

// MARK: - Foundation values

extension FJSONScanner {
    /// Reads a value as JSONSerialization would: strings, `NSNumber`s (also
    /// for booleans), dictionaries, arrays and `NSNull`.
    ///
    /// - Parameter rawAt: A path of keys whose value is kept as a `RawJSON`
    ///   slice of `message` instead (`message` holds the bytes being read).
    @_lifetime(self: copy self)
    mutating func readFoundationValue(rawAt rawPath: ArraySlice<String> = [],
                                      in message: ByteBuffer? = nil) throws -> Any {
        try readFoundationValue(depth: 0, rawPath: rawPath, message: message)
    }

    @_lifetime(self: copy self)
    private mutating func readFoundationValue(depth: Int, rawPath: ArraySlice<String>,
                                              message: ByteBuffer?) throws -> Any {
        guard depth <= kFirebaseMaxObjectDepth else { throw error(.tooDeep) }
        switch try peek() {
        case UInt8(ascii: "{"):
            try beginObject()
            var object: [String: Any] = [:]
            var first = true
            while let key = try nextKey(&first) {
                if key == rawPath.first, let message {
                    if rawPath.count == 1 {
                        skipWhitespace()
                        let start = offset
                        try skipValue()
                        object[key] = RawJSON(message.getSlice(at: message.readerIndex + start,
                                                               length: offset - start)!)
                    } else {
                        object[key] = try readFoundationValue(depth: depth + 1, rawPath: rawPath.dropFirst(),
                                                              message: message)
                    }
                } else {
                    object[key] = try readFoundationValue(depth: depth + 1, rawPath: [], message: nil)
                }
            }
            return object
        case UInt8(ascii: "["):
            try beginArray()
            var array: [Any] = []
            var first = true
            while try nextElement(&first) {
                array.append(try readFoundationValue(depth: depth + 1, rawPath: [], message: nil))
            }
            return array
        case UInt8(ascii: "\""):
            return try readString()
        case UInt8(ascii: "t"), UInt8(ascii: "f"):
            return NSNumber(value: try readBool())
        case UInt8(ascii: "n"):
            _ = try readNull()
            return NSNull()
        default:
            switch try readNumber() {
            case .int64(let value): return NSNumber(value: value)
            case .double(let value): return NSNumber(value: value)
            default: throw error(.invalidNumber)
            }
        }
    }
}

/// An unparsed JSON value: a slice of a server message, read once its
/// consumer knows what it is (a node, a merge, or something else).
struct RawJSON: CustomStringConvertible {
    let bytes: ByteBuffer

    init(_ bytes: ByteBuffer) {
        self.bytes = bytes
    }

    init(_ string: String) {
        bytes = ByteBuffer(string: string)
    }

    func node() throws -> FNode {
        try FJSONScanner.withScanner(bytes) { scanner in
            let node = try scanner.readNode()
            try scanner.expectEnd()
            return node
        }
    }

    func merge() throws -> [String: FNode] {
        try FJSONScanner.withScanner(bytes) { scanner in
            let merge = try scanner.readMerge()
            try scanner.expectEnd()
            return merge
        }
    }

    func foundationValue() throws -> Any {
        try FJSONScanner.withScanner(bytes) { scanner in
            let value = try scanner.readFoundationValue()
            try scanner.expectEnd()
            return value
        }
    }

    var description: String { String(buffer: bytes) }
}
