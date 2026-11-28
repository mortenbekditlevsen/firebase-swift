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

private typealias Bridge = firebase.firestore.swift_bridge

/// A document's fields as `data()` returns them, made from the values the
/// C++ core keeps, as `FirestoreValueDecoder` reads them, rather than from a
/// `BridgeFieldValueMap` copy of them (Docs/FirestorePerformance.md).
///
/// Nulls, booleans, numbers, strings, maps and arrays are made in place.
/// Every other value (timestamps, references, server timestamps, the BSON
/// types, …) is converted as before, one value at a time, so the result is
/// the same.
struct DocumentFields {
  let snapshot: DocumentSnapshot
  let serverTimestampBehavior: ServerTimestampBehavior

  /// The fields, or an empty dictionary if the document doesn't exist.
  func make() -> [String: Any] {
    withExtendedLifetime(snapshot) {
      // GetFields() points into the snapshot, which outlives this.
      map(snapshot.cppBridge.__GetFieldsUnsafe())
    }
  }

  private func value(_ ref: CppFieldValueRef) -> Any {
    switch Bridge.KindOf(ref) {
    case .Null:
      return NSNull()
    case .Boolean:
      return Bridge.BooleanOf(ref)
    case .Integer:
      return NSNumber(value: Bridge.IntegerOf(ref))
    case .Double:
      return NSNumber(value: Bridge.DoubleOf(ref))
    case .String:
      return String(Bridge.StringOf(ref))
    case .Map:
      return map(Bridge.MapOf(ref))
    case .Array:
      let array = Bridge.ArrayOf(ref)
      var result: [Any] = []
      result.reserveCapacity(array.count)
      for index in 0 ..< array.count {
        result.append(value(Bridge.ElementAt(array, index)))
      }
      return result
    default:
      return fromBridgeFieldValue(
        snapshot.cppBridge.ConvertValue(ref, Int32(serverTimestampBehavior.rawValue)),
        firestore: snapshot.firestore
      )
    }
  }

  private func map(_ map: CppFieldMapRef) -> [String: Any] {
    var result: [String: Any] = .init(minimumCapacity: map.count)
    for index in 0 ..< map.count {
      result[String(Bridge.KeyAt(map, index))] = value(Bridge.ValueAt(map, index))
    }
    return result
  }
}
