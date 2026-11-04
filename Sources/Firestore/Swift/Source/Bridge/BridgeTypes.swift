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

// The pipeline bridge: the `__`-prefixed classes upstream defines in
// Objective-C++ (FIRPipelineBridge.h/.mm), which upstream's Swift pipeline API
// is written against. As upstream, expressions and stages are only turned into
// the core's C++ objects (through PipelineBridge.h) when a pipeline runs, with
// the pipeline's database parsing the constants.

typealias CppExprBridge = firebase.firestore.swift_bridge.ExprBridge
typealias CppExprBridgeVector = firebase.firestore.swift_bridge.ExprBridgeVector
typealias CppNamedExprBridge = firebase.firestore.swift_bridge.NamedExprBridge
typealias CppNamedExprBridges = firebase.firestore.swift_bridge.NamedExprBridges
typealias CppNamedExprBridgesVector = firebase.firestore.swift_bridge.NamedExprBridgesVector
typealias CppAggregateFunctionBridge = firebase.firestore.swift_bridge.AggregateFunctionBridge
typealias CppNamedAggregateFunctionBridge = firebase.firestore.swift_bridge
  .NamedAggregateFunctionBridge
typealias CppNamedAggregateFunctionBridges = firebase.firestore.swift_bridge
  .NamedAggregateFunctionBridges
typealias CppOrderingBridge = firebase.firestore.swift_bridge.OrderingBridge
typealias CppOrderingBridgeVector = firebase.firestore.swift_bridge.OrderingBridgeVector
typealias CppRawStageParamBridge = firebase.firestore.swift_bridge.RawStageParamBridge
typealias CppRawStageParamBridgeVector = firebase.firestore.swift_bridge
  .RawStageParamBridgeVector
typealias CppStageBridge = firebase.firestore.swift_bridge.StageBridge
typealias CppStageBridgeVector = firebase.firestore.swift_bridge.StageBridgeVector
typealias CppDocumentReferenceBridgeVector = firebase.firestore.swift_bridge
  .DocumentReferenceBridgeVector
typealias CppPipelineBridge = firebase.firestore.swift_bridge.PipelineBridge
typealias CppPipelineResultBridge = firebase.firestore.swift_bridge.PipelineResultBridge
typealias CppPipelineResultChangeBridge = firebase.firestore.swift_bridge
  .PipelineResultChangeBridge
typealias CppPipelineSnapshotBridge = firebase.firestore.swift_bridge.PipelineSnapshotBridge
typealias CppRealtimePipelineSnapshotBridge = firebase.firestore.swift_bridge
  .RealtimePipelineSnapshotBridge

// MARK: - Expression Bridges

/// Base bridge type for all expression types.
public class __ExprBridge: @unchecked Sendable {
  /// Builds the C++ expression for a pipeline of `db`.
  let makeCpp: (Firestore) -> CppExprBridge

  init(makeCpp: @escaping (Firestore) -> CppExprBridge) {
    self.makeCpp = makeCpp
  }
}

/// Bridge for field expressions.
public final class __FieldBridge: __ExprBridge {
  private let fieldPath: FieldPath

  public convenience init(name: String) {
    self.init(path: FieldPath(dotSeparated: name))
  }

  public init(path: FieldPath) {
    fieldPath = path
    let segments = path.cppSegments
    super.init { _ in CppExprBridge.Field(segments) }
  }

  public func field_name() -> String {
    String(CppExprBridge.CanonicalFieldPath(fieldPath.cppSegments))
  }
}

/// Bridge for variable expressions.
public final class __VariableBridge: __ExprBridge {
  public init(name: String) {
    super.init { _ in CppExprBridge.Variable(std.string(name)) }
  }
}

/// Bridge for constant expressions.
public final class __ConstantBridge: __ExprBridge {
  public init(_ input: Any) {
    // Validated when the pipeline runs, as upstream.
    super.init { db in CppExprBridge.Constant(toBridgeFieldValue(input), db.cppBridge) }
  }
}

/// Bridge for function expressions.
public final class __FunctionExprBridge: __ExprBridge {
  public init(name: String, args: [__ExprBridge], options: [String: __ExprBridge]? = nil) {
    super.init { db in
      CppExprBridge.Function(std.string(name), cppExprs(args, db), cppNamed(options ?? [:], db))
    }
  }
}

/// Bridge for pipeline expressions.
public final class __PipelineExprBridge: __ExprBridge {
  public init(stages: [__StageBridge]) {
    super.init { db in CppExprBridge.Pipeline(cppStages(stages, db)) }
  }
}

// MARK: - Aggregate Function Bridge

/// Bridge for aggregate function expressions.
public final class __AggregateFunctionBridge: @unchecked Sendable {
  private let name: String
  private let args: [__ExprBridge]

  public init(name: String, args: [__ExprBridge]) {
    self.name = name
    self.args = args
  }

  func makeCpp(_ db: Firestore) -> CppAggregateFunctionBridge {
    CppAggregateFunctionBridge.Create(std.string(name), cppExprs(args, db))
  }
}

// MARK: - Ordering Bridge

/// Bridge for sort orderings.
public final class __OrderingBridge: @unchecked Sendable {
  private let expr: __ExprBridge
  private let direction: String

  public init(expr: __ExprBridge, direction: String) {
    self.expr = expr
    self.direction = direction
  }

  func makeCpp(_ db: Firestore) -> CppOrderingBridge {
    CppOrderingBridge.Create(expr.makeCpp(db), std.string(direction))
  }
}

// MARK: - Stage Bridges

/// Base bridge type for all stage types.
public class __StageBridge: @unchecked Sendable {
  /// Builds the C++ stage for a pipeline of `db`.
  let makeCpp: (Firestore) -> CppStageBridge

  init(makeCpp: @escaping (Firestore) -> CppStageBridge) {
    self.makeCpp = makeCpp
  }

  /// A stage the C++ core made, from a query.
  init(prebuilt stage: CppStageBridge) {
    makeCpp = { _ in stage }
  }

  public var name: String { "" }
}

public final class __CollectionSourceStageBridge: __StageBridge {
  public init(ref: CollectionReference, firestore: Firestore, forceIndex: String?) {
    let collection = ref.collectionBridge
    super.init { _ in
      CppStageBridge.Collection(collection, firestore.cppBridge, std.string(forceIndex ?? ""))
    }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "collection" }
}

public final class __SubcollectionSourceStageBridge: __StageBridge {
  public init(path: String) {
    super.init { _ in CppStageBridge.Subcollection(std.string(path)) }
  }

  override public var name: String { "subcollection" }
}

public final class __DatabaseSourceStageBridge: __StageBridge {
  public init() {
    super.init { _ in CppStageBridge.Database() }
  }

  override public var name: String { "database" }
}

public final class __CollectionGroupSourceStageBridge: __StageBridge {
  public init(collectionId: String, forceIndex: String?) {
    super.init { _ in
      CppStageBridge.CollectionGroup(std.string(collectionId), std.string(forceIndex ?? ""))
    }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "collection_group" }
}

public final class __DocumentsSourceStageBridge: __StageBridge {
  public init(documents: [DocumentReference], firestore: Firestore) {
    var references = CppDocumentReferenceBridgeVector()
    for document in documents {
      references.push_back(document.cppBridge)
    }
    super.init { _ in CppStageBridge.Documents(references, firestore.cppBridge) }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "documents" }
}

public final class __WhereStageBridge: __StageBridge {
  public init(expr: __ExprBridge) {
    super.init { db in CppStageBridge.Where(expr.makeCpp(db)) }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "where" }
}

public final class __LimitStageBridge: __StageBridge {
  public init(limit: Int) {
    super.init { _ in CppStageBridge.Limit(Int32(truncatingIfNeeded: limit)) }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "limit" }
}

public final class __OffsetStageBridge: __StageBridge {
  public init(offset: Int) {
    super.init { _ in CppStageBridge.Offset(Int32(truncatingIfNeeded: offset)) }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "offset" }
}

public final class __AddFieldsStageBridge: __StageBridge {
  public init(fields: [String: __ExprBridge]) {
    super.init { db in CppStageBridge.AddFields(cppNamed(fields, db)) }
  }

  override public var name: String { "add_fields" }
}

public final class __LiteralsSourceStageBridge: __StageBridge {
  public init(data: [[String: __ExprBridge]]) {
    super.init { db in
      var documents = CppNamedExprBridgesVector()
      for document in data {
        documents.push_back(cppNamed(document, db))
      }
      return CppStageBridge.Literals(documents)
    }
  }

  override public var name: String { "literals" }
}

public final class __DeleteStageBridge: __StageBridge {
  public init() {
    super.init { _ in CppStageBridge.Delete() }
  }

  override public var name: String { "delete" }
}

public final class __UpdateStageBridge: __StageBridge {
  public init(fields: [String: __ExprBridge]) {
    super.init { db in CppStageBridge.Update(cppNamed(fields, db)) }
  }

  override public var name: String { "update" }
}

public final class __InsertStageBridge: __StageBridge {
  public init(collectionPath: String?, documentIdExpression: __ExprBridge?) {
    super.init { db in
      CppStageBridge.Insert(std.string(collectionPath ?? ""),
                            documentIdExpression != nil,
                            documentIdExpression?.makeCpp(db) ?? CppExprBridge())
    }
  }

  override public var name: String { "insert" }
}

public final class __UpsertStageBridge: __StageBridge {
  public init(additionalFields: [String: __ExprBridge], collectionPath: String?,
              documentIdExpression: __ExprBridge?) {
    super.init { db in
      CppStageBridge.Upsert(cppNamed(additionalFields, db),
                            std.string(collectionPath ?? ""),
                            documentIdExpression != nil,
                            documentIdExpression?.makeCpp(db) ?? CppExprBridge())
    }
  }

  override public var name: String { "upsert" }
}

public final class __RemoveFieldsStageBridge: __StageBridge {
  public init(fields: [String]) {
    var paths = CppFieldPathVector()
    for field in fields {
      paths.push_back(FieldPath(dotSeparated: field).cppSegments)
    }
    super.init { _ in CppStageBridge.RemoveFields(paths) }
  }

  override public var name: String { "remove_fields" }
}

public final class __SelectStageBridge: __StageBridge {
  public init(selections: [String: __ExprBridge]) {
    super.init { db in CppStageBridge.Select(cppNamed(selections, db)) }
  }

  override public var name: String { "select" }
}

public final class __DefineStageBridge: __StageBridge {
  public init(variables: [String: __ExprBridge]) {
    super.init { db in CppStageBridge.Define(cppNamed(variables, db)) }
  }

  override public var name: String { "let" }
}

public final class __DistinctStageBridge: __StageBridge {
  public init(groups: [String: __ExprBridge]) {
    super.init { db in CppStageBridge.Distinct(cppNamed(groups, db)) }
  }

  override public var name: String { "distinct" }
}

public final class __AggregateStageBridge: __StageBridge {
  public init(accumulators: [String: __AggregateFunctionBridge], groups: [String: __ExprBridge]) {
    super.init { db in
      var cppAccumulators = CppNamedAggregateFunctionBridges()
      for (alias, accumulator) in accumulators {
        cppAccumulators.push_back(
          CppNamedAggregateFunctionBridge(first: std.string(alias),
                                          second: accumulator.makeCpp(db))
        )
      }
      return CppStageBridge.Aggregate(cppAccumulators, cppNamed(groups, db))
    }
  }

  override public var name: String { "aggregate" }
}

public final class __FindNearestStageBridge: __StageBridge {
  public init(field: __FieldBridge, vectorValue: VectorValue, distanceMeasure: String,
              limit: NSNumber?, distanceField: __ExprBridge?) {
    let limit = limit?.int64Value
    super.init { db in
      CppStageBridge.FindNearest(field.makeCpp(db),
                                 toBridgeFieldValue(vectorValue),
                                 std.string(distanceMeasure),
                                 limit != nil,
                                 limit ?? 0,
                                 distanceField != nil,
                                 distanceField?.makeCpp(db) ?? CppExprBridge(),
                                 db.cppBridge)
    }
  }

  override public var name: String { "find_nearest" }
}

public final class __SearchStageBridge: __StageBridge {
  public init(options: [String: __ExprBridge], addFields: [String: __ExprBridge],
              select: [String: __ExprBridge], sort: [__OrderingBridge]) {
    super.init { db in
      CppStageBridge.Search(cppNamed(options, db), cppNamed(addFields, db),
                            cppNamed(select, db), cppOrderings(sort, db))
    }
  }

  override public var name: String { "search" }
}

public final class __SortStageBridge: __StageBridge {
  public init(orderings: [Any]) {
    let orderings = orderings.map { ordering in
      guard let ordering = ordering as? __OrderingBridge else {
        fatalError("Sort orderings must be __OrderingBridge instances.")
      }
      return ordering
    }
    super.init { db in CppStageBridge.Sort(cppOrderings(orderings, db)) }
  }

  override init(prebuilt stage: CppStageBridge) {
    super.init(prebuilt: stage)
  }

  override public var name: String { "sort" }
}

public final class __ReplaceWithStageBridge: __StageBridge {
  public init(expr: __ExprBridge) {
    super.init { db in CppStageBridge.ReplaceWith(expr.makeCpp(db)) }
  }

  override public var name: String { "replace_with" }
}

public final class __SampleStageBridge: __StageBridge {
  public init(count: Int64) {
    super.init { _ in CppStageBridge.SampleCount(count) }
  }

  public init(percentage: Double) {
    super.init { _ in CppStageBridge.SamplePercentage(percentage) }
  }

  override public var name: String { "sample" }
}

public final class __UnionStageBridge: __StageBridge {
  public init(other: __PipelineBridge) {
    super.init { _ in CppStageBridge.Union(other.makeCpp()) }
  }

  override public var name: String { "union" }
}

public final class __UnnestStageBridge: __StageBridge {
  public init(field: __ExprBridge, alias: __ExprBridge, indexField: __ExprBridge?) {
    super.init { db in
      CppStageBridge.Unnest(field.makeCpp(db), alias.makeCpp(db), indexField != nil,
                            indexField?.makeCpp(db) ?? CppExprBridge())
    }
  }

  override public var name: String { "unnest" }
}

public final class __RawStageBridge: __StageBridge {
  private let _name: String

  public init(name: String, params: [AnyObject], options: [String: __ExprBridge]?) {
    _name = name
    super.init { db in
      var cppParams = CppRawStageParamBridgeVector()
      for param in params {
        cppParams.push_back(rawStageParam(param, db))
      }
      return CppStageBridge.Raw(std.string(name), cppParams, cppNamed(options ?? [:], db))
    }
  }

  override public var name: String { _name }
}

/// A raw stage's parameter: an expression, an aggregate function, or a
/// dictionary of them (as `Helper.sendableToAnyObjectForRawStage` makes).
private func rawStageParam(_ param: Any, _ db: Firestore) -> CppRawStageParamBridge {
  switch param {
  case let expr as __ExprBridge:
    return CppRawStageParamBridge.Expr(expr.makeCpp(db))
  case let aggregate as __AggregateFunctionBridge:
    return CppRawStageParamBridge.Aggregate(aggregate.makeCpp(db))
  case let dictionary as [String: Any]:
    var keys = CppStringVector()
    var values = CppRawStageParamBridgeVector()
    for (key, value) in dictionary {
      guard value is __ExprBridge || value is __AggregateFunctionBridge else {
        invalidArgument(
          "Dictionary value must be an __FIRExprBridge or __FIRAggregateFunctionBridge."
        )
      }
      keys.push_back(std.string(key))
      values.push_back(rawStageParam(value, db))
    }
    return CppRawStageParamBridge.Map(keys, values)
  case let dictionary as NSDictionary:
    var swiftDictionary: [String: Any] = [:]
    for (key, value) in dictionary {
      guard let key = key as? String else {
        invalidArgument("Invalid value to convert to google_firestore_v1_Value.")
      }
      swiftDictionary[key] = value
    }
    return rawStageParam(swiftDictionary, db)
  default:
    invalidArgument("Invalid value to convert to google_firestore_v1_Value.")
  }
}

// MARK: - Pipeline Bridges

/// Bridge for pipeline execution.
public final class __PipelineBridge: @unchecked Sendable {
  private let stages: [__StageBridge]
  private let db: Firestore
  private let atomic: Bool

  public init(stages: [__StageBridge], db: Firestore, atomic: Bool = false) {
    self.stages = stages
    self.db = db
    self.atomic = atomic
  }

  func makeCpp() -> CppPipelineBridge {
    CppPipelineBridge.Create(cppStages(stages, db), db.cppBridge, atomic)
  }

  public func execute(completion: @escaping (__PipelineSnapshotBridge?, Error?) -> Void) {
    let db = self.db
    let handler: PipelineSnapshotHandler = { snapshot, error in
      completion(takeBridge(snapshot, as: CppPipelineSnapshotBridge.self).map {
        __PipelineSnapshotBridge(cppBridge: $0, firestore: db)
      }, error)
    }
    makeCpp().Execute(retainedContext(handler), pipelineSnapshotCallbackTrampoline)
  }

  public static func createStageBridges(from query: Query) -> [__StageBridge] {
    let stages = CppStageBridge.FromQuery(query.cppQueryBridge)
    var result: [__StageBridge] = []
    for i in 0 ..< stages.size() {
      let stage = stages[i]
      switch String(stage.name()) {
      case "collection": result.append(__CollectionSourceStageBridge(prebuilt: stage))
      case "collection_group": result.append(__CollectionGroupSourceStageBridge(prebuilt: stage))
      case "documents": result.append(__DocumentsSourceStageBridge(prebuilt: stage))
      case "where": result.append(__WhereStageBridge(prebuilt: stage))
      case "limit": result.append(__LimitStageBridge(prebuilt: stage))
      case "sort": result.append(__SortStageBridge(prebuilt: stage))
      case "offset": result.append(__OffsetStageBridge(prebuilt: stage))
      // C++ refuses other stages.
      default: fatalError("Unknown stage type \(String(stage.name()))")
      }
    }
    return result
  }
}

/// Bridge for realtime pipeline listeners.
public final class __RealtimePipelineBridge: @unchecked Sendable {
  private let stages: [__StageBridge]
  private let db: Firestore

  public init(stages: [__StageBridge], db: Firestore) {
    self.stages = stages
    self.db = db
  }

  public func addSnapshotListener(
    options: __PipelineListenOptionsBridge,
    listener: @escaping (__RealtimePipelineSnapshotBridge?, Error?) -> Void
  ) -> ListenerRegistration {
    let db = self.db
    let handler: PipelineSnapshotHandler = { snapshot, error in
      listener(takeBridge(snapshot, as: CppRealtimePipelineSnapshotBridge.self).map {
        __RealtimePipelineSnapshotBridge(cppBridge: $0, firestore: db)
      }, error)
    }
    let serverTimestampBehavior: ServerTimestampBehavior =
      switch options.serverTimestampBehavior {
      case "estimate": .estimate
      case "previous": .previous
      default: .none
      }
    let registration = CppPipelineBridge.AddRealtimeSnapshotListener(
      cppStages(stages, db),
      db.cppBridge,
      options.includeMetadata,
      Int32(options.source.rawValue),
      Int32(serverTimestampBehavior.rawValue),
      retainedContext(handler),
      releaseCallbackBox,
      pipelineSnapshotListenerTrampoline
    )
    return BridgeListenerRegistration(cppBridge: registration)
  }
}

// MARK: - Result Bridges

/// Bridge for individual pipeline results.
public final class __PipelineResultBridge: @unchecked Sendable {
  private let cppBridge: CppPipelineResultBridge
  private let firestore: Firestore

  init(cppBridge: CppPipelineResultBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  public var reference: DocumentReference? {
    var reference = CppDocumentReferenceBridge()
    guard cppBridge.GetReference(&reference) else { return nil }
    return DocumentReference(cppBridge: reference, firestore: firestore)
  }

  public var documentID: String? {
    cppBridge.has_document_id() ? String(cppBridge.document_id()) : nil
  }

  public var create_time: Timestamp? {
    guard cppBridge.has_create_time() else { return nil }
    return Timestamp(seconds: cppBridge.create_time_seconds(),
                     nanoseconds: cppBridge.create_time_nanos())
  }

  public var update_time: Timestamp? {
    guard cppBridge.has_update_time() else { return nil }
    return Timestamp(seconds: cppBridge.update_time_seconds(),
                     nanoseconds: cppBridge.update_time_nanos())
  }

  public func data() -> [String: Any] {
    data(with: .none)
  }

  public func data(with serverTimestampBehavior: ServerTimestampBehavior) -> [String: Any] {
    fromBridgeFieldValueMap(cppBridge.data(Int32(serverTimestampBehavior.rawValue)),
                            firestore: firestore)
  }

  public func get(_ field: Any) -> Any? {
    get(field, serverTimestampBehavior: .none)
  }

  public func get(_ field: Any, serverTimestampBehavior: ServerTimestampBehavior) -> Any? {
    let path = FieldPath.from(field,
                              invalidMessage: "Subscript key must be an NSString or FIRFieldPath.")
    var value = CppBridgeFieldValue()
    guard cppBridge.GetField(path.cppSegments, Int32(serverTimestampBehavior.rawValue), &value)
    else { return nil }
    return fromBridgeFieldValue(value, firestore: firestore)
  }
}

/// Bridge for pipeline result changes.
public final class __PipelineResultChangeBridge: @unchecked Sendable {
  private let cppBridge: CppPipelineResultChangeBridge
  private let firestore: Firestore

  init(cppBridge: CppPipelineResultChangeBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  public var type: DocumentChangeType {
    DocumentChangeType(rawValue: Int(cppBridge.type().rawValue)) ?? .added
  }

  public var result: __PipelineResultBridge {
    __PipelineResultBridge(cppBridge: cppBridge.result(), firestore: firestore)
  }

  public var oldIndex: UInt {
    let index = cppBridge.old_index()
    return index < 0 ? UInt(NSNotFound) : UInt(index)
  }

  public var newIndex: UInt {
    let index = cppBridge.new_index()
    return index < 0 ? UInt(NSNotFound) : UInt(index)
  }
}

/// Bridge for pipeline snapshots.
public final class __PipelineSnapshotBridge: @unchecked Sendable {
  public let results: [__PipelineResultBridge]
  public let execution_time: Timestamp

  init(cppBridge: CppPipelineSnapshotBridge, firestore: Firestore) {
    let cppResults = cppBridge.results()
    var results: [__PipelineResultBridge] = []
    for i in 0 ..< cppResults.size() {
      results.append(__PipelineResultBridge(cppBridge: cppResults[i], firestore: firestore))
    }
    self.results = results
    execution_time = Timestamp(seconds: cppBridge.execution_time_seconds(),
                               nanoseconds: cppBridge.execution_time_nanos())
  }
}

/// Bridge for realtime pipeline snapshots.
public final class __RealtimePipelineSnapshotBridge: @unchecked Sendable {
  public let results: [__PipelineResultBridge]
  public let changes: [__PipelineResultChangeBridge]
  public let metadata: SnapshotMetadata

  init(cppBridge: CppRealtimePipelineSnapshotBridge, firestore: Firestore) {
    let cppResults = cppBridge.results()
    var results: [__PipelineResultBridge] = []
    for i in 0 ..< cppResults.size() {
      results.append(__PipelineResultBridge(cppBridge: cppResults[i], firestore: firestore))
    }
    let cppChanges = cppBridge.changes()
    var changes: [__PipelineResultChangeBridge] = []
    for i in 0 ..< cppChanges.size() {
      changes.append(__PipelineResultChangeBridge(cppBridge: cppChanges[i], firestore: firestore))
    }
    self.results = results
    self.changes = changes
    metadata = SnapshotMetadata(cppMetadata: cppBridge.metadata())
  }
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

// MARK: - Helpers

private func cppExprs(_ exprs: [__ExprBridge], _ db: Firestore) -> CppExprBridgeVector {
  var result = CppExprBridgeVector()
  for expr in exprs {
    result.push_back(expr.makeCpp(db))
  }
  return result
}

private func cppNamed(_ exprs: [String: __ExprBridge], _ db: Firestore) -> CppNamedExprBridges {
  var result = CppNamedExprBridges()
  for (name, expr) in exprs {
    result.push_back(CppNamedExprBridge(first: std.string(name), second: expr.makeCpp(db)))
  }
  return result
}

private func cppOrderings(_ orderings: [__OrderingBridge],
                          _ db: Firestore) -> CppOrderingBridgeVector {
  var result = CppOrderingBridgeVector()
  for ordering in orderings {
    result.push_back(ordering.makeCpp(db))
  }
  return result
}

private func cppStages(_ stages: [__StageBridge], _ db: Firestore) -> CppStageBridgeVector {
  var result = CppStageBridgeVector()
  for stage in stages {
    result.push_back(stage.makeCpp(db))
  }
  return result
}

/// Gets the snapshot that C++ allocated (or nil) and the error.
private typealias PipelineSnapshotHandler = (UnsafeMutableRawPointer?, Error?) -> Void

/// One-shot pipeline result callback.
private func pipelineSnapshotCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<PipelineSnapshotHandler>>.fromOpaque(context)
    .takeRetainedValue()
  box.handler(snapshot, firestoreError(code: code, message: message))
}

/// Realtime pipeline listener; C++ releases the box.
private func pipelineSnapshotListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<PipelineSnapshotHandler>>.fromOpaque(context)
    .takeUnretainedValue()
  box.handler(snapshot, firestoreError(code: code, message: message))
}
