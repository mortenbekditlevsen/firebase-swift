// Copyright 2025 Google LLC
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

// MARK: - Expression Bridges

/// Base bridge type for all expression types.
/// Eventually this will hold a C++ `shared_ptr<api::Expr>`.
public class __ExprBridge: @unchecked Sendable {
}

/// Bridge for field expressions.
public final class __FieldBridge: __ExprBridge {
  private let _fieldName: String

  public init(name: String) {
    _fieldName = name
  }

  public init(path: FieldPath) {
    // TODO: Extract canonical path string from FieldPath
    _fieldName = ""
  }

  public func field_name() -> String {
    return _fieldName
  }
}

/// Bridge for variable expressions.
public final class __VariableBridge: __ExprBridge {
  public init(name: String) {
    super.init()
  }
}

/// Bridge for constant expressions.
public final class __ConstantBridge: __ExprBridge {
  public init(_ input: Any) {
    super.init()
  }
}

/// Bridge for function expressions.
public final class __FunctionExprBridge: __ExprBridge {
  public init(name: String, args: [__ExprBridge], options: [String: __ExprBridge]? = nil) {
    super.init()
  }
}

/// Bridge for pipeline expressions.
public final class __PipelineExprBridge: __ExprBridge {
  public init(stages: [__StageBridge]) {
    super.init()
  }
}

// MARK: - Aggregate Function Bridge

/// Bridge for aggregate function expressions.
public final class __AggregateFunctionBridge: @unchecked Sendable {
  public init(name: String, args: [__ExprBridge]) {
  }
}

// MARK: - Ordering Bridge

/// Bridge for sort orderings.
public final class __OrderingBridge: @unchecked Sendable {
  public init(expr: __ExprBridge, direction: String) {
  }
}

// MARK: - Stage Bridges

/// Base bridge type for all stage types.
public class __StageBridge: @unchecked Sendable {
  public var name: String { "" }
}

public final class __CollectionSourceStageBridge: __StageBridge {
  public init(ref: CollectionReference, firestore: Firestore, forceIndex: String?) {
  }
  override public var name: String { "collection" }
}

public final class __SubcollectionSourceStageBridge: __StageBridge {
  public init(path: String) {
  }
  override public var name: String { "subcollection" }
}

public final class __DatabaseSourceStageBridge: __StageBridge {
  public override init() {
  }
  override public var name: String { "database" }
}

public final class __CollectionGroupSourceStageBridge: __StageBridge {
  public init(collectionId: String, forceIndex: String?) {
  }
  override public var name: String { "collection_group" }
}

public final class __DocumentsSourceStageBridge: __StageBridge {
  public init(documents: [DocumentReference], firestore: Firestore) {
  }
  override public var name: String { "documents" }
}

public final class __WhereStageBridge: __StageBridge {
  public init(expr: __ExprBridge) {
  }
  override public var name: String { "where" }
}

public final class __LimitStageBridge: __StageBridge {
  public init(limit: Int) {
  }
  override public var name: String { "limit" }
}

public final class __OffsetStageBridge: __StageBridge {
  public init(offset: Int) {
  }
  override public var name: String { "offset" }
}

public final class __AddFieldsStageBridge: __StageBridge {
  public init(fields: [String: __ExprBridge]) {
  }
  override public var name: String { "add_fields" }
}

// The DML and literals stages upstream added in 13.0; stubs like the others.
public final class __LiteralsSourceStageBridge: __StageBridge {
  public init(data: [[String: __ExprBridge]]) {
  }
  override public var name: String { "literals" }
}

public final class __DeleteStageBridge: __StageBridge {
  override public init() {
  }
  override public var name: String { "delete" }
}

public final class __UpdateStageBridge: __StageBridge {
  public init(fields: [String: __ExprBridge]) {
  }
  override public var name: String { "update" }
}

public final class __InsertStageBridge: __StageBridge {
  public init(collectionPath: String?, documentIdExpression: __ExprBridge?) {
  }
  override public var name: String { "insert" }
}

public final class __UpsertStageBridge: __StageBridge {
  public init(additionalFields: [String: __ExprBridge], collectionPath: String?,
              documentIdExpression: __ExprBridge?) {
  }
  override public var name: String { "upsert" }
}

public final class __RemoveFieldsStageBridge: __StageBridge {
  public init(fields: [String]) {
  }
  override public var name: String { "remove_fields" }
}

public final class __SelectStageBridge: __StageBridge {
  public init(selections: [String: __ExprBridge]) {
  }
  override public var name: String { "select" }
}

public final class __DefineStageBridge: __StageBridge {
  public init(variables: [String: __ExprBridge]) {
  }
  override public var name: String { "let" }
}

public final class __DistinctStageBridge: __StageBridge {
  public init(groups: [String: __ExprBridge]) {
  }
  override public var name: String { "distinct" }
}

public final class __AggregateStageBridge: __StageBridge {
  public init(accumulators: [String: __AggregateFunctionBridge], groups: [String: __ExprBridge]) {
  }
  override public var name: String { "aggregate" }
}

public final class __FindNearestStageBridge: __StageBridge {
  public init(field: __FieldBridge, vectorValue: VectorValue, distanceMeasure: String,
              limit: NSNumber?, distanceField: __ExprBridge?) {
  }
  override public var name: String { "find_nearest" }
}

public final class __SearchStageBridge: __StageBridge {
  public init(options: [String: __ExprBridge], addFields: [String: __ExprBridge],
              select: [String: __ExprBridge], sort: [__OrderingBridge]) {
  }
  override public var name: String { "search" }
}

public final class __SortStageBridge: __StageBridge {
  public init(orderings: [Any]) {
  }
  override public var name: String { "sort" }
}

public final class __ReplaceWithStageBridge: __StageBridge {
  public init(expr: __ExprBridge) {
  }
  override public var name: String { "replace_with" }
}

public final class __SampleStageBridge: __StageBridge {
  public init(count: Int64) {
  }
  public init(percentage: Double) {
  }
  override public var name: String { "sample" }
}

public final class __UnionStageBridge: __StageBridge {
  public init(other: __PipelineBridge) {
  }
  override public var name: String { "union" }
}

public final class __UnnestStageBridge: __StageBridge {
  public init(field: __ExprBridge, alias: __ExprBridge, indexField: __ExprBridge?) {
  }
  override public var name: String { "unnest" }
}

public final class __RawStageBridge: __StageBridge {
  private let _name: String
  public init(name: String, params: [AnyObject], options: [String: __ExprBridge]?) {
    _name = name
  }
  override public var name: String { _name }
}

// MARK: - Pipeline Bridges

/// Bridge for pipeline execution.
public final class __PipelineBridge: @unchecked Sendable {
  public init(stages: [__StageBridge], db: Firestore, atomic: Bool = false) {
  }

  public func execute(completion: @escaping (__PipelineSnapshotBridge?, Error?) -> Void) {
    // TODO: Implement via C++ Pipeline::Execute
    completion(nil, NSError(domain: "FirebaseFirestore", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Not yet implemented"]))
  }

  public static func createStageBridges(from query: Query) -> [__StageBridge] {
    // TODO: Implement via C++ conversion
    return []
  }
}

/// Bridge for realtime pipeline listeners.
public final class __RealtimePipelineBridge: @unchecked Sendable {
  public init(stages: [__StageBridge], db: Firestore) {
  }

  public func addSnapshotListener(
    options: __PipelineListenOptionsBridge,
    listener: @escaping (__RealtimePipelineSnapshotBridge?, Error?) -> Void
  ) -> ListenerRegistration {
    // TODO: Implement via C++ RealtimePipeline
    return _NoOpListenerRegistration()
  }
}

// MARK: - Result Bridges

/// Bridge for individual pipeline results.
public final class __PipelineResultBridge: @unchecked Sendable {
  public var reference: DocumentReference? { nil }
  public var documentID: String? { nil }
  public var create_time: Timestamp? { nil }
  public var update_time: Timestamp? { nil }

  public func data() -> [String: Any] { [:] }
  public func data(with serverTimestampBehavior: ServerTimestampBehavior) -> [String: Any] { [:] }
  public func get(_ field: Any) -> Any? { nil }
  public func get(_ field: Any, serverTimestampBehavior: ServerTimestampBehavior) -> Any? { nil }
}

/// Bridge for pipeline result changes.
public final class __PipelineResultChangeBridge: @unchecked Sendable {
  public var type: DocumentChangeType { .added }
  public var result: __PipelineResultBridge { __PipelineResultBridge() }
  public var oldIndex: UInt { UInt(NSNotFound) }
  public var newIndex: UInt { UInt(NSNotFound) }
}

/// Bridge for pipeline snapshots.
public final class __PipelineSnapshotBridge: @unchecked Sendable {
  public var results: [__PipelineResultBridge] { [] }
  public var execution_time: Timestamp { Timestamp(seconds: 0, nanoseconds: 0) }
}

/// Bridge for realtime pipeline snapshots.
public final class __RealtimePipelineSnapshotBridge: @unchecked Sendable {
  public var results: [__PipelineResultBridge] { [] }
  public var changes: [__PipelineResultChangeBridge] { [] }
  public var metadata: SnapshotMetadata { SnapshotMetadata() }
}

/// Bridge for pipeline listen options.
public final class __PipelineListenOptionsBridge: @unchecked Sendable, Equatable, Hashable {
  public let serverTimestampBehavior: String
  public let includeMetadata: Bool
  public let source: ListenSource

  public init(serverTimestampBehavior: String, includeMetadata: Bool, source: ListenSource) {
    self.serverTimestampBehavior = serverTimestampBehavior
    self.includeMetadata = includeMetadata
    self.source = source
  }

  public static func == (lhs: __PipelineListenOptionsBridge,
                         rhs: __PipelineListenOptionsBridge) -> Bool {
    lhs.serverTimestampBehavior == rhs.serverTimestampBehavior &&
      lhs.includeMetadata == rhs.includeMetadata &&
      lhs.source == rhs.source
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(serverTimestampBehavior)
    hasher.combine(includeMetadata)
    hasher.combine(source)
  }
}

// MARK: - Placeholder for no-op listener registration

private final class _NoOpListenerRegistration: ListenerRegistration {
  func remove() {}
}
