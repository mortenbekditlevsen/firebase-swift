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

typealias CppAggregateKind = firebase.firestore.swift_bridge.AggregateKind
typealias CppBridgeAggregateField = firebase.firestore.swift_bridge.BridgeAggregateField
typealias CppBridgeAggregateFields = firebase.firestore.swift_bridge.BridgeAggregateFields

/// Where an aggregation runs.
public enum AggregateSource: Int, Sendable {
  /// On the server, ignoring the local cache and pending writes. Fails if the
  /// server can't be reached.
  case server = 0
}

/// An aggregation for `Query.aggregate(_:)`.
public final class AggregateField: Hashable, Sendable {
  enum Kind: Hashable {
    case count, sum, average

    /// Upstream's name, for messages.
    var name: String {
      switch self {
      case .count: "count"
      case .sum: "sum"
      case .average: "avg"
      }
    }
  }

  let kind: Kind
  let fieldPath: FieldPath?

  private init(kind: Kind, fieldPath: FieldPath?) {
    self.kind = kind
    self.fieldPath = fieldPath
  }

  /// Counts the documents.
  public static func count() -> AggregateField {
    AggregateField(kind: .count, fieldPath: nil)
  }

  /// Sums a dot-separated field over the documents.
  public static func sum(_ field: String) -> AggregateField {
    sum(FieldPath(dotSeparated: field))
  }

  /// Sums a field over the documents.
  public static func sum(_ fieldPath: FieldPath) -> AggregateField {
    AggregateField(kind: .sum, fieldPath: fieldPath)
  }

  /// Averages a dot-separated field over the documents.
  public static func average(_ field: String) -> AggregateField {
    average(FieldPath(dotSeparated: field))
  }

  /// Averages a field over the documents.
  public static func average(_ fieldPath: FieldPath) -> AggregateField {
    AggregateField(kind: .average, fieldPath: fieldPath)
  }

  public static func == (lhs: AggregateField, rhs: AggregateField) -> Bool {
    lhs.kind == rhs.kind && lhs.fieldPath == rhs.fieldPath
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(kind)
    hasher.combine(fieldPath)
  }

  var cppField: CppBridgeAggregateField {
    let kind: CppAggregateKind = switch kind {
    case .count: .Count
    case .sum: .Sum
    case .average: .Average
    }
    return CppBridgeAggregateField(first: kind, second: fieldPath?.cppSegments ?? CppStringVector())
  }
}

/// Aggregations over the results of a query, which only download the results
/// of the aggregations.
public final class AggregateQuery: Hashable, Sendable {
  /// The query whose results are aggregated.
  public let query: Query
  let fields: [AggregateField]

  init(query: Query, fields: [AggregateField]) {
    self.query = query
    self.fields = fields
  }

  public static func == (lhs: AggregateQuery, rhs: AggregateQuery) -> Bool {
    lhs.query == rhs.query && lhs.fields == rhs.fields
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(query)
    hasher.combine(fields)
  }

  /// Runs the aggregations.
  public func getAggregation(source: AggregateSource) async throws -> AggregateQuerySnapshot {
    var cppFields = CppBridgeAggregateFields()
    for field in fields {
      cppFields.push_back(field.cppField)
    }
    return try await withCheckedThrowingContinuation { continuation in
      let handler: AggregateHandler = { [self] results, error in
        if let results {
          let values = fromBridgeFieldValueVector(results, firestore: query.firestore)
          continuation.resume(returning: AggregateQuerySnapshot(
            query: self,
            values: Dictionary(zip(fields, values), uniquingKeysWith: { first, _ in first })
          ))
        } else {
          continuation.resume(throwing: error ?? FirestoreErrorCode(.unknown))
        }
      }
      query.cppQueryBridge.GetAggregate(cppFields, retainedContext(handler),
                                        aggregateCallbackTrampoline)
    }
  }
}

/// The results of an `AggregateQuery`.
public final class AggregateQuerySnapshot: @unchecked Sendable {
  /// The aggregate query that produced these results.
  public let query: AggregateQuery
  // Immutable; the values are from the bridge (NSNumber or NSNull).
  private let values: [AggregateField: Any]

  init(query: AggregateQuery, values: [AggregateField: Any]) {
    self.query = query
    self.values = values
  }

  /// The number of documents, if the query asked for `AggregateField.count()`
  /// (as `Query.count` does).
  public var count: NSNumber {
    self.get(.count()) as! NSNumber
  }

  /// The result of an aggregation: an `NSNumber`, or `NSNull` for the average
  /// of no numbers. Stops the process if the query didn't ask for it.
  public func get(_ aggregateField: AggregateField) -> Any {
    guard let value = values[aggregateField] else {
      let path = aggregateField.fieldPath?.segments.joined(separator: ".") ?? ""
      invalidArgument(
        "'\(aggregateField.kind.name)(\(path))' was not requested in the aggregation query."
      )
    }
    return value
  }
}

public extension Query {
  /// Counts the documents in the results without downloading them.
  var count: AggregateQuery {
    aggregate([.count()])
  }

  /// Aggregates the documents in the results without downloading them.
  func aggregate(_ aggregateFields: [AggregateField]) -> AggregateQuery {
    AggregateQuery(query: self, fields: aggregateFields)
  }
}

private typealias AggregateHandler = (CppBridgeFieldValueVector?, Error?) -> Void

private func aggregateCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  results: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<AggregateHandler>>.fromOpaque(context).takeRetainedValue()
  box.handler(takeBridge(results, as: CppBridgeFieldValueVector.self),
              firestoreError(code: code, message: message))
}
