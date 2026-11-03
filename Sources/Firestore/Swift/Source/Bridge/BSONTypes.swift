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

// The BSON types (upstream 13.0). Firestore stores them as maps with a special
// key; the bridge converts them both ways, as upstream's FSTUserDataReader and
// FSTUserDataWriter do. They're final classes, like upstream's
// `objc_subclassing_restricted` ones; the Codable conformances are upstream's
// files in `Codable/`.

/// The smallest value of any type, for ordering and range queries.
public final class MinKey: Hashable, Sendable, CustomStringConvertible {
  /// The only `MinKey`.
  public static let shared = MinKey()

  init() {}

  public static func == (lhs: MinKey, rhs: MinKey) -> Bool { true }
  public func hash(into hasher: inout Hasher) {}
  public var description: String { "<FIRMinKey>" }
}

/// The largest value of any type, for ordering and range queries.
public final class MaxKey: Hashable, Sendable, CustomStringConvertible {
  /// The only `MaxKey`.
  public static let shared = MaxKey()

  init() {}

  public static func == (lhs: MaxKey, rhs: MaxKey) -> Bool { true }
  public func hash(into hasher: inout Hasher) {}
  public var description: String { "<FIRMaxKey>" }
}

/// A regular expression, with BSON's options.
public final class RegexValue: Hashable, Sendable, CustomStringConvertible {
  public let pattern: String
  public let options: String

  public init(pattern: String, options: String) {
    self.pattern = pattern
    self.options = options
  }

  public static func == (lhs: RegexValue, rhs: RegexValue) -> Bool {
    lhs.pattern == rhs.pattern && lhs.options == rhs.options
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(pattern)
    hasher.combine(options)
  }

  public var description: String { "<FIRRegexValue: (pattern:\(pattern), options:\(options))>" }
}

/// A 32-bit integer, which Firestore keeps apart from its 64-bit integers.
public final class Int32Value: Hashable, Sendable, CustomStringConvertible {
  public let value: Int32

  public init(_ value: Int32) {
    self.value = value
  }

  public static func == (lhs: Int32Value, rhs: Int32Value) -> Bool {
    lhs.value == rhs.value
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  public var description: String { "<FIRInt32Value: (\(value))>" }
}

/// A BSON ObjectId, as its 24 hexadecimal digits.
public final class BSONObjectId: Hashable, Sendable, CustomStringConvertible {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }

  public static func == (lhs: BSONObjectId, rhs: BSONObjectId) -> Bool {
    lhs.value == rhs.value
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(value)
  }

  public var description: String { "<FIRBSONObjectId: (\(value))>" }
}

/// A BSON timestamp: seconds and an ordinal within the second.
public final class BSONTimestamp: Hashable, Sendable, CustomStringConvertible {
  public let seconds: UInt32
  public let increment: UInt32

  public init(seconds: UInt32, increment: UInt32) {
    self.seconds = seconds
    self.increment = increment
  }

  public static func == (lhs: BSONTimestamp, rhs: BSONTimestamp) -> Bool {
    lhs.seconds == rhs.seconds && lhs.increment == rhs.increment
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(seconds)
    hasher.combine(increment)
  }

  public var description: String {
    "<FIRBSONTimestamp: (seconds:\(seconds), increment:\(increment))>"
  }
}

/// A 128-bit decimal, as its string. Two values are equal if they're the same
/// number, so "1.0" equals "1" and "-0" equals "0", as upstream.
public final class Decimal128Value: Hashable, Sendable, CustomStringConvertible {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }

  public static func == (lhs: Decimal128Value, rhs: Decimal128Value) -> Bool {
    CppBridgeFieldValue.Decimal128Equal(std.string(lhs.value), std.string(rhs.value))
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(CppBridgeFieldValue.Decimal128Hash(std.string(value)))
  }

  public var description: String { "<FIRDecimal128Value: (\(value))>" }
}

/// Bytes with a BSON binary subtype. Subtype 0 is stored as plain bytes, so
/// it reads back as `Data`, as upstream.
public final class Blob: Hashable, Sendable, CustomStringConvertible {
  public let subtype: UInt8
  public let bytes: Data

  private init(bytes: Data, subtype: UInt8) {
    self.bytes = bytes
    self.subtype = subtype
  }

  /// Bytes with subtype 0.
  public convenience init(bytes: Data) {
    self.init(bytes: bytes, subtype: 0)
  }

  /// Bytes with subtype 0.
  public convenience init(bsonBinary bytes: Data) {
    self.init(bytes: bytes, subtype: 0)
  }

  public convenience init(bsonBinary bytes: Data, subtype: UInt8) {
    self.init(bytes: bytes, subtype: subtype)
  }

  public static func == (lhs: Blob, rhs: Blob) -> Bool {
    lhs.subtype == rhs.subtype && lhs.bytes == rhs.bytes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(subtype)
    hasher.combine(bytes)
  }

  /// Orders by subtype, then by the bytes, as upstream.
  public func compare(_ other: Blob) -> ComparisonResult {
    if subtype != other.subtype {
      return subtype < other.subtype ? .orderedAscending : .orderedDescending
    }
    if bytes.lexicographicallyPrecedes(other.bytes) { return .orderedAscending }
    if other.bytes.lexicographicallyPrecedes(bytes) { return .orderedDescending }
    return .orderedSame
  }

  public var description: String { "<FIRBlob: subtype:\(subtype), bytes:\(bytes)>" }
}
