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

typealias CppFilterBridge = firebase.firestore.swift_bridge.FilterBridge
typealias CppFilterBridgeVector = firebase.firestore.swift_bridge.FilterBridgeVector
typealias CppFilterOperator = firebase.firestore.swift_bridge.FilterOperator

/// A query filter, which can combine other filters with `andFilter(_:)` and
/// `orFilter(_:)`. Pass it to `Query.whereFilter(_:)`.
public final class Filter: @unchecked Sendable {
  private enum Node {
    case field(FieldPath, CppFilterOperator, Any)
    case and([Filter])
    case or([Filter])
  }

  private let node: Node

  private init(_ node: Node) {
    self.node = node
  }

  var cppBridge: CppFilterBridge {
    switch node {
    case let .field(path, op, value):
      return CppFilterBridge.Field(path.cppSegments, op, toBridgeFieldValue(value))
    case let .and(filters):
      return CppFilterBridge.And(Self.cppVector(filters))
    case let .or(filters):
      return CppFilterBridge.Or(Self.cppVector(filters))
    }
  }

  private static func cppVector(_ filters: [Filter]) -> CppFilterBridgeVector {
    var vector = CppFilterBridgeVector()
    for filter in filters {
      vector.push_back(filter.cppBridge)
    }
    return vector
  }

  static func field(_ path: FieldPath, _ op: CppFilterOperator, _ value: Any) -> Filter {
    Filter(.field(path, op, value))
  }

  /// A filter that matches documents matching all of `filters`.
  public static func andFilter(_ filters: [Filter]) -> Filter {
    Filter(.and(filters))
  }

  /// A filter that matches documents matching any of `filters`.
  public static func orFilter(_ filters: [Filter]) -> Filter {
    Filter(.or(filters))
  }

  public static func whereField(_ field: String, isEqualTo value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isEqualTo: value)
  }

  public static func whereField(_ path: FieldPath, isEqualTo value: Any) -> Filter {
    field(path, .Equal, value)
  }

  public static func whereField(_ field: String, isNotEqualTo value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isNotEqualTo: value)
  }

  public static func whereField(_ path: FieldPath, isNotEqualTo value: Any) -> Filter {
    field(path, .NotEqual, value)
  }

  public static func whereField(_ field: String, isGreaterThan value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isGreaterThan: value)
  }

  public static func whereField(_ path: FieldPath, isGreaterThan value: Any) -> Filter {
    field(path, .GreaterThan, value)
  }

  // Upstream's name, without "Than".
  public static func whereField(_ field: String, isGreaterOrEqualTo value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isGreaterOrEqualTo: value)
  }

  public static func whereField(_ path: FieldPath, isGreaterOrEqualTo value: Any) -> Filter {
    field(path, .GreaterThanOrEqual, value)
  }

  public static func whereField(_ field: String, isLessThan value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isLessThan: value)
  }

  public static func whereField(_ path: FieldPath, isLessThan value: Any) -> Filter {
    field(path, .LessThan, value)
  }

  public static func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), isLessThanOrEqualTo: value)
  }

  public static func whereField(_ path: FieldPath, isLessThanOrEqualTo value: Any) -> Filter {
    field(path, .LessThanOrEqual, value)
  }

  public static func whereField(_ field: String, arrayContains value: Any) -> Filter {
    whereField(FieldPath(dotSeparated: field), arrayContains: value)
  }

  public static func whereField(_ path: FieldPath, arrayContains value: Any) -> Filter {
    field(path, .ArrayContains, value)
  }

  public static func whereField(_ field: String, arrayContainsAny values: [Any]) -> Filter {
    whereField(FieldPath(dotSeparated: field), arrayContainsAny: values)
  }

  public static func whereField(_ path: FieldPath, arrayContainsAny values: [Any]) -> Filter {
    field(path, .ArrayContainsAny, values)
  }

  public static func whereField(_ field: String, in values: [Any]) -> Filter {
    whereField(FieldPath(dotSeparated: field), in: values)
  }

  public static func whereField(_ path: FieldPath, in values: [Any]) -> Filter {
    field(path, .In, values)
  }

  public static func whereField(_ field: String, notIn values: [Any]) -> Filter {
    whereField(FieldPath(dotSeparated: field), notIn: values)
  }

  public static func whereField(_ path: FieldPath, notIn values: [Any]) -> Filter {
    field(path, .NotIn, values)
  }
}
