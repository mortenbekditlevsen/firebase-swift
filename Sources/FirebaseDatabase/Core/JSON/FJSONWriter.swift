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

/// A value that can't be written as JSON.
struct FJSONWriterError: Error, CustomStringConvertible {
    let value: String

    var description: String { "Can't write \(value) as JSON" }
}

/// Writes JSON as UTF-8 bytes.
///
/// It writes nodes (`FNode`) as `val(forExport: true)` would give them, but
/// without making the Foundation tree first; and Foundation values, which
/// may contain nodes.
struct FJSONWriter {
    private(set) var buffer: ByteBuffer

    init(capacity: Int = 256) {
        buffer = ByteBufferAllocator().buffer(capacity: capacity)
    }

    /// `value` as JSON bytes.
    static func bytes(_ value: Any) throws -> ByteBuffer {
        var writer = FJSONWriter()
        try writer.write(value)
        return writer.buffer
    }

    /// Writes a Foundation value (strings, numbers, booleans, dictionaries
    /// with string keys, arrays, `NSNull`, nil) or a node.
    mutating func write(_ value: Any?) throws {
        guard let value else {
            buffer.writeStaticString("null")
            return
        }
        switch value {
        case let node as FNode:
            try write(node)
        case let string as String:
            write(string: string)
        case _ where isBoolean(value):
            let bool = (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
            buffer.writeStaticString(bool ? "true" : "false")
        case let number as Int:
            try write(leaf: .int64(Int64(number)))
        case let number as Int64:
            try write(leaf: .int64(number))
        case let number as Double:
            try write(double: number)
        case let number as NSNumber:
            try write(leaf: .number(number))
        case let dictionary as [String: Any]:
            buffer.writeInteger(UInt8(ascii: "{"))
            var first = true
            for (key, child) in dictionary {
                writeKey(key, first: &first)
                try write(child)
            }
            buffer.writeInteger(UInt8(ascii: "}"))
        case let array as [Any]:
            buffer.writeInteger(UInt8(ascii: "["))
            for (index, child) in array.enumerated() {
                if index > 0 { buffer.writeInteger(UInt8(ascii: ",")) }
                try write(child)
            }
            buffer.writeInteger(UInt8(ascii: "]"))
        case is NSNull:
            buffer.writeStaticString("null")
        default:
            throw FJSONWriterError(value: "\(type(of: value))")
        }
    }

    /// Writes a node in export form: with `.priority`, `.value` and `.sv` keys.
    mutating func write(_ node: FNode) throws {
        let priority = node.getPriority()
        switch node.type {
        case .empty:
            buffer.writeStaticString("null")
        case .leaf(let value):
            if priority.isEmpty {
                try write(leaf: value)
            } else {
                buffer.writeStaticString("{\".value\":")
                try write(leaf: value)
                buffer.writeStaticString(",\".priority\":")
                try write(priority)
                buffer.writeInteger(UInt8(ascii: "}"))
            }
        case .children(let children):
            guard !children.isEmpty else {
                buffer.writeStaticString("null")
                return
            }
            buffer.writeInteger(UInt8(ascii: "{"))
            var first = true
            for (key, child) in children {
                writeKey(key.key, first: &first)
                try write(child)
            }
            if !priority.isEmpty {
                writeKey(kPayloadPriority, first: &first)
                try write(priority)
            }
            buffer.writeInteger(UInt8(ascii: "}"))
        }
    }

    private mutating func write(leaf: LeafValue) throws {
        switch leaf {
        case .bool(let value):
            buffer.writeStaticString(value ? "true" : "false")
        case .int64(let value):
            buffer.writeString(String(value))
        case .double(let value):
            try write(double: value)
        case .string(let value):
            write(string: value)
        case .deferredValue(.timestamp):
            buffer.writeStaticString("{\".sv\":\"timestamp\"}")
        case .deferredValue(.increment(let delta)):
            buffer.writeStaticString("{\".sv\":{\"increment\":")
            try write(leaf: delta)
            buffer.writeStaticString("}}")
        }
    }

    /// The shortest form that reads back as the same double.
    private mutating func write(double: Double) throws {
        guard double.isFinite else { throw FJSONWriterError(value: "\(double)") }
        if let integer = Int64(exactly: double), abs(integer) < 1 << 53 {
            // As JSONSerialization does: no ".0".
            buffer.writeString(String(integer))
        } else {
            buffer.writeString(double.description)
        }
    }

    private mutating func writeKey(_ key: String, first: inout Bool) {
        if !first { buffer.writeInteger(UInt8(ascii: ",")) }
        first = false
        write(string: key)
        buffer.writeInteger(UInt8(ascii: ":"))
    }

    private mutating func write(string: String) {
        buffer.writeInteger(UInt8(ascii: "\""))
        var string = string
        string.withUTF8 { utf8 in
            var start = 0
            for (index, byte) in utf8.enumerated() where byte < 0x20 || byte == UInt8(ascii: "\"")
                || byte == UInt8(ascii: "\\") {
                buffer.writeBytes(UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: utf8[start ..< index])))
                switch byte {
                case UInt8(ascii: "\""): buffer.writeStaticString("\\\"")
                case UInt8(ascii: "\\"): buffer.writeStaticString("\\\\")
                case 0x0A: buffer.writeStaticString("\\n")
                case 0x0D: buffer.writeStaticString("\\r")
                case 0x09: buffer.writeStaticString("\\t")
                default:
                    let hex = String(byte, radix: 16)
                    buffer.writeString("\\u00" + (hex.count == 1 ? "0" + hex : hex))
                }
                start = index + 1
            }
            buffer.writeBytes(UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: utf8[start...])))
        }
        buffer.writeInteger(UInt8(ascii: "\""))
    }
}
