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

#if SWIFT_PACKAGE
  @_exported import FirebaseFirestoreInternalWrapper
#else
  @_exported import FirebaseFirestoreInternal
#endif

// C++ bridge type aliases for convenience.
typealias CppFirestoreBridge = firebase.firestore.swift_bridge.FirestoreBridge
typealias CppDocumentReferenceBridge = firebase.firestore.swift_bridge
  .DocumentReferenceBridge
typealias CppCollectionReferenceBridge = firebase.firestore.swift_bridge
  .CollectionReferenceBridge
typealias CppQueryBridge = firebase.firestore.swift_bridge.QueryBridge
typealias CppDocumentSnapshotBridge = firebase.firestore.swift_bridge
  .DocumentSnapshotBridge
typealias CppQuerySnapshotBridge = firebase.firestore.swift_bridge.QuerySnapshotBridge
typealias CppListenerRegistrationBridge = firebase.firestore.swift_bridge
  .ListenerRegistrationBridge
typealias CppSource = firebase.firestore.api.Source
typealias CppSnapshotMetadata = firebase.firestore.api.SnapshotMetadata

// Bridge field value types
typealias CppBridgeFieldValue = firebase.firestore.swift_bridge.BridgeFieldValue
typealias CppBridgeFieldValueMap = firebase.firestore.swift_bridge.BridgeFieldValueMap
typealias CppBridgeFieldValueMapEntry = firebase.firestore.swift_bridge
  .BridgeFieldValueMapEntry
typealias CppBridgeFieldValueVector = firebase.firestore.swift_bridge
  .BridgeFieldValueVector
typealias CppDoubleVector = firebase.firestore.swift_bridge.DoubleVector
typealias CppStringVector = firebase.firestore.swift_bridge.StringVector

// MARK: - Source Conversion

extension FirestoreSource {
  /// Convert to the C++ `api::Source` enum.
  var cppSource: CppSource {
    switch self {
    case .default: return .Default
    case .server: return .Server
    case .cache: return .Cache
    }
  }
}

// MARK: - Swift ↔ BridgeFieldValue Conversion

/// Internal tag for FieldValue sentinels.
enum FieldValueSentinel {
  case delete_
  case serverTimestamp
  case arrayUnion([Any])
  case arrayRemove([Any])
  case incrementInt(Int64)
  case incrementDouble(Double)
}

/// Convert a Swift `Any` value to a C++ `BridgeFieldValue`.
func toBridgeFieldValue(_ value: Any) -> CppBridgeFieldValue {
  // Handle FieldValue sentinels
  if let fv = value as? FieldValue {
    return fv.toBridgeFieldValue()
  }

  // Handle nil / NSNull
  if value is NSNull {
    return CppBridgeFieldValue.Null()
  }

  // Handle Bool (must check before NSNumber since Bool bridges to NSNumber)
  if let b = value as? Bool {
    return CppBridgeFieldValue.FromBool(b)
  }

  // Handle numeric types via NSNumber
  if let n = value as? NSNumber {
    let objCType = String(cString: n.objCType)
    // 'f' = float, 'd' = double
    if objCType == "f" || objCType == "d" {
      return CppBridgeFieldValue.FromDouble(n.doubleValue)
    }
    return CppBridgeFieldValue.FromInt64(n.int64Value)
  }

  // Handle String
  if let s = value as? String {
    return CppBridgeFieldValue.FromString(std.string(s))
  }

  // Handle Data (blob)
  if let data = value as? Data {
    var blob = std.string()
    data.withUnsafeBytes { buffer in
      if let ptr = buffer.baseAddress {
        blob = std.string(ptr.assumingMemoryBound(to: CChar.self), buffer.count)
      }
    }
    return CppBridgeFieldValue.FromBlob(blob)
  }

  // Handle Timestamp
  if let ts = value as? Timestamp {
    return CppBridgeFieldValue.FromTimestamp(ts.seconds, ts.nanoseconds)
  }

  // Handle GeoPoint
  if let geo = value as? GeoPoint {
    return CppBridgeFieldValue.FromGeoPoint(geo.latitude, geo.longitude)
  }

  // Handle VectorValue
  if let vec = value as? VectorValue {
    var doubles = CppDoubleVector()
    for d in vec.array {
      doubles.push_back(d)
    }
    return CppBridgeFieldValue.FromVector(doubles)
  }

  // Handle DocumentReference
  if let ref = value as? DocumentReference {
    return CppBridgeFieldValue.FromReference(std.string(ref.path))
  }

  // Handle Array
  if let arr = value as? [Any] {
    var cppArr = CppBridgeFieldValueVector()
    for element in arr {
      cppArr.push_back(toBridgeFieldValue(element))
    }
    return CppBridgeFieldValue.FromArray(cppArr)
  }

  // Handle Dictionary
  if let dict = value as? [String: Any] {
    return CppBridgeFieldValue.FromMap(toBridgeFieldValueMap(dict))
  }

  // Fallback: treat as null
  return CppBridgeFieldValue.Null()
}

/// Convert a Swift dictionary to a C++ `BridgeFieldValueMap`.
func toBridgeFieldValueMap(_ dict: [String: Any]) -> CppBridgeFieldValueMap {
  var map = CppBridgeFieldValueMap()
  for (key, value) in dict {
    map.push_back(CppBridgeFieldValueMapEntry(first: std.string(key), second: toBridgeFieldValue(value)))
  }
  return map
}

/// Convert a C++ `BridgeFieldValue` back to a Swift `Any`.
func fromBridgeFieldValue(_ value: CppBridgeFieldValue) -> Any {
  switch value.tag() {
  case .Null:
    return NSNull()
  case .Boolean:
    return value.bool_value()
  case .Integer:
    return value.int64_value()
  case .Double:
    return value.double_value()
  case .String:
    return Swift.String(value.string_value())
  case .Blob:
    let bytes = value.blob_bytes()
    var data = Data(count: bytes.size())
    for i in 0 ..< bytes.size() {
      data[i] = bytes[i]
    }
    return data
  case .Timestamp:
    return Timestamp(
      seconds: value.timestamp_seconds(),
      nanoseconds: value.timestamp_nanos()
    )
  case .GeoPoint:
    return GeoPoint(
      latitude: value.geo_latitude(),
      longitude: value.geo_longitude()
    )
  case .Array:
    return fromBridgeFieldValueVector(value.array_value())
  case .Map:
    return fromBridgeFieldValueMap(value.map_value())
  case .Reference:
    // Return the path string — callers who need a DocumentReference
    // will need to resolve it against a Firestore instance.
    return Swift.String(value.string_value())
  case .Vector:
    let doubles = value.vector_value()
    var arr: [Double] = []
    for i in 0 ..< doubles.size() {
      arr.append(doubles[i])
    }
    return VectorValue(arr)
  default:
    return NSNull()
  }
}

/// Convert a C++ `BridgeFieldValueMap` to a Swift dictionary.
func fromBridgeFieldValueMap(_ map: CppBridgeFieldValueMap) -> [String: Any] {
  var result: [String: Any] = [:]
  for i in 0 ..< map.size() {
    let entry = map[i]
    let key = Swift.String(entry.first)
    result[key] = fromBridgeFieldValue(entry.second)
  }
  return result
}

/// Convert a C++ `BridgeFieldValueVector` to a Swift array.
func fromBridgeFieldValueVector(_ vec: CppBridgeFieldValueVector) -> [Any] {
  var result: [Any] = []
  for i in 0 ..< vec.size() {
    result.append(fromBridgeFieldValue(vec[i]))
  }
  return result
}

// MARK: - Core Firestore Types

/// The main Firestore database instance.
public final class Firestore: @unchecked Sendable {
  var cppBridge: CppFirestoreBridge?

  init() {
    cppBridge = nil
  }

  init(cppBridge: CppFirestoreBridge) {
    self.cppBridge = cppBridge
  }

  public static func firestore() -> Firestore {
    // TODO: Implement via C++ interop - construct a real Firestore instance
    // This requires Firebase app initialization which is a separate concern.
    return Firestore()
  }

  public func collection(_ collectionPath: String) -> CollectionReference {
    guard let bridge = cppBridge else { return CollectionReference() }
    let cppRef = bridge.GetCollection(std.string(collectionPath))
    return CollectionReference(cppBridge: cppRef)
  }

  public func document(_ documentPath: String) -> DocumentReference {
    guard let bridge = cppBridge else { return DocumentReference() }
    let cppRef = bridge.GetDocument(std.string(documentPath))
    return DocumentReference(cppBridge: cppRef)
  }

  public func loadBundle(_ bundleData: Data,
                         completion: @escaping (LoadBundleTaskProgress?, Error?) -> Void) {
    // TODO: Implement via C++ interop
  }

  public func loadBundle(_ bundleStream: InputStream,
                         completion: @escaping (LoadBundleTaskProgress?, Error?) -> Void) {
    // TODO: Implement via C++ interop
  }

  public func runTransaction(_ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?,
                             completion: @escaping (Any?, Error?) -> Void) {
    // TODO: Implement via C++ interop
  }
}

/// A reference to a Firestore document.
public final class DocumentReference: @unchecked Sendable {
  var cppBridge: CppDocumentReferenceBridge

  init() {
    cppBridge = CppDocumentReferenceBridge()
  }

  init(cppBridge: CppDocumentReferenceBridge) {
    self.cppBridge = cppBridge
  }

  public var path: String {
    String(cppBridge.path())
  }

  public var documentID: String {
    String(cppBridge.document_id())
  }

  public var parent: CollectionReference {
    CollectionReference(cppBridge: cppBridge.parent())
  }

  public func setData(_ documentData: [String: Any],
                      completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(documentData)
    let error = String(cppBridge.SetData(map))
    if error.isEmpty {
      completion?(nil)
    } else {
      completion?(NSError(domain: "FirebaseFirestore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: error]))
    }
  }

  public func setData(_ documentData: [String: Any],
                      merge: Bool,
                      completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(documentData)
    let error: String
    if merge {
      error = String(cppBridge.SetDataMerge(map))
    } else {
      error = String(cppBridge.SetData(map))
    }
    if error.isEmpty {
      completion?(nil)
    } else {
      completion?(NSError(domain: "FirebaseFirestore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: error]))
    }
  }

  public func setData(_ documentData: [String: Any],
                      mergeFields: [Any],
                      completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(documentData)
    var fields = CppStringVector()
    for field in mergeFields {
      if let s = field as? String {
        fields.push_back(std.string(s))
      } else if let fp = field as? FieldPath {
        // FieldPath doesn't expose its string yet — use empty for now
        fields.push_back(std.string(""))
      }
    }
    let error = String(cppBridge.SetDataMergeFields(map, fields))
    if error.isEmpty {
      completion?(nil)
    } else {
      completion?(NSError(domain: "FirebaseFirestore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: error]))
    }
  }

  public func updateData(_ fields: [String: Any],
                         completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(fields)
    let error = String(cppBridge.UpdateData(map))
    if error.isEmpty {
      completion?(nil)
    } else {
      completion?(NSError(domain: "FirebaseFirestore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: error]))
    }
  }

  public func delete(completion: ((Error?) -> Void)? = nil) {
    cppBridge.DeleteDocumentNoCallback()
    completion?(nil)
  }

  public func getDocument(source: FirestoreSource = .default,
                          completion: @escaping (DocumentSnapshot?, Error?) -> Void) {
    // TODO: Implement via C++ interop (requires async callback bridging)
    completion(nil, nil)
  }

  public func getDocument(source: FirestoreSource = .default) async throws -> DocumentSnapshot {
    // TODO: Implement via C++ interop (requires async callback bridging)
    return DocumentSnapshot()
  }

  public func addSnapshotListener(includeMetadataChanges: Bool = false,
                                  listener: @escaping (DocumentSnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    // TODO: Implement via C++ interop (requires AddSnapshotListener bridge)
    return NoOpListenerRegistration()
  }
}

/// A reference to a Firestore collection.
public final class CollectionReference: Query, @unchecked Sendable {
  private var _collectionBridge: CppCollectionReferenceBridge?

  init() {
    _collectionBridge = nil
    super.init(cppBridge: CppQueryBridge())
  }

  init(cppBridge: CppCollectionReferenceBridge) {
    _collectionBridge = cppBridge
    // We need to get the QueryBridge base from the CollectionReferenceBridge.
    // Since C++ inheritance isn't directly visible in Swift, we pass it as-is
    // and keep a separate reference.
    super.init(cppBridge: CppQueryBridge())
  }

  public var collectionID: String {
    guard let bridge = _collectionBridge else { return "" }
    return String(bridge.collection_id())
  }

  public func document() -> DocumentReference {
    guard let bridge = _collectionBridge else { return DocumentReference() }
    return DocumentReference(cppBridge: bridge.Document())
  }

  public func document(_ path: String) -> DocumentReference {
    guard let bridge = _collectionBridge else { return DocumentReference() }
    return DocumentReference(cppBridge: bridge.Document(std.string(path)))
  }

  public func addDocument(data: [String: Any],
                          completion: ((Error?) -> Void)? = nil) -> DocumentReference {
    let docRef = document()
    docRef.setData(data, completion: completion)
    return docRef
  }
}

/// A Firestore query.
public class Query: @unchecked Sendable {
  var cppQueryBridge: CppQueryBridge

  init(cppBridge: CppQueryBridge) {
    cppQueryBridge = cppBridge
  }

  public var firestore: Firestore { Firestore() }

  public func addSnapshotListener(includeMetadataChanges: Bool = false,
                                  listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    // TODO: Implement via C++ interop (requires AddSnapshotListener bridge)
    return NoOpListenerRegistration()
  }

  public func addSnapshotListener(_ listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    return addSnapshotListener(includeMetadataChanges: false, listener: listener)
  }

  // MARK: - Query modifiers

  public func whereField(_ field: String, isEqualTo value: Any) -> Query { self }
  public func whereField(_ field: String, isNotEqualTo value: Any) -> Query { self }
  public func whereField(_ field: String, isLessThan value: Any) -> Query { self }
  public func whereField(_ field: String, isGreaterThan value: Any) -> Query { self }
  public func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Query { self }
  public func whereField(_ field: String, isGreaterThanOrEqualTo value: Any) -> Query { self }
  public func whereField(_ field: String, in values: [Any]) -> Query { self }
  public func whereField(_ field: String, notIn values: [Any]) -> Query { self }
  public func whereField(_ field: String, arrayContains value: Any) -> Query { self }
  public func whereField(_ field: String, arrayContainsAny values: [Any]) -> Query { self }

  public func order(by field: String, descending: Bool = false) -> Query {
    let newBridge = cppQueryBridge.OrderBy(std.string(field), descending)
    return Query(cppBridge: newBridge)
  }

  public func limit(to limit: Int) -> Query {
    let newBridge = cppQueryBridge.LimitToFirst(Int32(limit))
    return Query(cppBridge: newBridge)
  }

  public func limit(toLast limit: Int) -> Query {
    let newBridge = cppQueryBridge.LimitToLast(Int32(limit))
    return Query(cppBridge: newBridge)
  }

  public func start(atDocument document: DocumentSnapshot) -> Query { self }
  public func start(afterDocument document: DocumentSnapshot) -> Query { self }
  public func end(atDocument document: DocumentSnapshot) -> Query { self }
  public func end(beforeDocument document: DocumentSnapshot) -> Query { self }
}

/// A snapshot of a document.
public final class DocumentSnapshot: @unchecked Sendable {
  private var cppBridge: CppDocumentSnapshotBridge

  init() {
    cppBridge = CppDocumentSnapshotBridge()
  }

  init(cppBridge: CppDocumentSnapshotBridge) {
    self.cppBridge = cppBridge
  }

  public var exists: Bool {
    cppBridge.exists()
  }

  public var data: [String: Any]? {
    guard cppBridge.exists() else { return nil }
    let cppMap = cppBridge.data()
    if cppMap.size() == 0 && !cppBridge.exists() {
      return nil
    }
    return fromBridgeFieldValueMap(cppMap)
  }

  public var reference: DocumentReference {
    DocumentReference(cppBridge: cppBridge.create_reference())
  }

  public var documentID: String {
    String(cppBridge.document_id())
  }

  public func data(with serverTimestampBehavior: ServerTimestampBehavior) -> [String: Any]? { nil }
  public func get(_ field: String) -> Any? { nil }
  public func get(_ field: String,
                  serverTimestampBehavior: ServerTimestampBehavior) -> Any? { nil }
}

/// A snapshot of a query result.
public final class QuerySnapshot: @unchecked Sendable {
  private var cppBridge: CppQuerySnapshotBridge

  init() {
    cppBridge = CppQuerySnapshotBridge()
  }

  init(cppBridge: CppQuerySnapshotBridge) {
    self.cppBridge = cppBridge
  }

  public var documents: [DocumentSnapshot] {
    let cppDocs = cppBridge.documents()
    var result: [DocumentSnapshot] = []
    for i in 0 ..< cppDocs.size() {
      result.append(DocumentSnapshot(cppBridge: cppDocs[i]))
    }
    return result
  }

  public var isEmpty: Bool {
    cppBridge.empty()
  }

  public var count: Int {
    Int(cppBridge.size())
  }

  public var documentChanges: [DocumentChange] { [] }

  public var metadata: SnapshotMetadata {
    SnapshotMetadata(cppMetadata: cppBridge.metadata())
  }
}

/// A change to a document in a query result.
public final class DocumentChange: @unchecked Sendable {
  public var type: DocumentChangeType { .added }
  public var document: DocumentSnapshot { DocumentSnapshot() }
  public var oldIndex: UInt { 0 }
  public var newIndex: UInt { 0 }
}

/// The type of document change.
public enum DocumentChangeType: Int, Sendable {
  case added = 0
  case modified = 1
  case removed = 2
}

/// A batch of write operations.
public final class WriteBatch: @unchecked Sendable {
  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference) -> WriteBatch {
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> WriteBatch { self }
  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> WriteBatch { self }
  @discardableResult
  public func updateData(_ fields: [String: Any],
                         forDocument doc: DocumentReference) -> WriteBatch { self }
  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> WriteBatch { self }
  public func commit(completion: ((Error?) -> Void)?) {}
}

/// A Firestore transaction.
public final class Transaction: @unchecked Sendable {
  @discardableResult
  public func setData(_ data: [String: Any],
                      forDocument doc: DocumentReference) -> Transaction { self }
  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> Transaction { self }
  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> Transaction { self }
  @discardableResult
  public func updateData(_ fields: [String: Any],
                         forDocument doc: DocumentReference) -> Transaction { self }
  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> Transaction { self }
  public func getDocument(_ doc: DocumentReference) throws -> DocumentSnapshot {
    DocumentSnapshot()
  }
}

/// A path to a field in a Firestore document.
public final class FieldPath: @unchecked Sendable {
  public init(_ fieldNames: [String]) {}
  public init(_ fieldName: String) {}
  public static func documentID() -> FieldPath { FieldPath([]) }
}

/// Sentinel values for field operations.
public final class FieldValue: @unchecked Sendable {
  let sentinel: FieldValueSentinel

  private init(_ sentinel: FieldValueSentinel) {
    self.sentinel = sentinel
  }

  public static func serverTimestamp() -> FieldValue {
    FieldValue(.serverTimestamp)
  }

  public static func arrayUnion(_ elements: [Any]) -> FieldValue {
    FieldValue(.arrayUnion(elements))
  }

  public static func arrayRemove(_ elements: [Any]) -> FieldValue {
    FieldValue(.arrayRemove(elements))
  }

  public static func delete() -> FieldValue {
    FieldValue(.delete_)
  }

  public static func increment(_ n: Int64) -> FieldValue {
    FieldValue(.incrementInt(n))
  }

  public static func increment(_ n: Double) -> FieldValue {
    FieldValue(.incrementDouble(n))
  }

  /// Creates a VectorValue from an array of NSNumbers.
  /// This is the ObjC-compatible factory method used by FieldValue+Swift.swift.
  public static func __vector(with array: [NSNumber]) -> VectorValue {
    return VectorValue(array.map { $0.doubleValue })
  }

  /// Convert this sentinel to a C++ BridgeFieldValue.
  func toBridgeFieldValue() -> CppBridgeFieldValue {
    switch sentinel {
    case .delete_:
      return CppBridgeFieldValue.Delete()
    case .serverTimestamp:
      return CppBridgeFieldValue.ServerTimestamp()
    case .arrayUnion(let elements):
      var cppArr = CppBridgeFieldValueVector()
      for e in elements {
        cppArr.push_back(FirebaseFirestore.toBridgeFieldValue(e))
      }
      return CppBridgeFieldValue.ArrayUnion(cppArr)
    case .arrayRemove(let elements):
      var cppArr = CppBridgeFieldValueVector()
      for e in elements {
        cppArr.push_back(FirebaseFirestore.toBridgeFieldValue(e))
      }
      return CppBridgeFieldValue.ArrayRemove(cppArr)
    case .incrementInt(let n):
      return CppBridgeFieldValue.IncrementInt(n)
    case .incrementDouble(let n):
      return CppBridgeFieldValue.IncrementDouble(n)
    }
  }
}

/// Vector value for vector search.
public final class VectorValue: @unchecked Sendable {
  private var _array: [Double]

  public var array: [Double] { _array }

  public init(_ array: [Double]) {
    self._array = array
  }

  public init(__array: [NSNumber]) {
    self._array = __array.map { $0.doubleValue }
  }
}

/// Firestore settings.
public final class FirestoreSettings: @unchecked Sendable {
  public var host: String = "firestore.googleapis.com"
  public var isPersistenceEnabled: Bool = true
}

/// Metadata about a snapshot.
public final class SnapshotMetadata: @unchecked Sendable {
  private var cppMetadata: CppSnapshotMetadata?

  init() {
    cppMetadata = nil
  }

  init(cppMetadata: CppSnapshotMetadata) {
    self.cppMetadata = cppMetadata
  }

  public var isFromCache: Bool {
    cppMetadata?.from_cache() ?? false
  }

  public var hasPendingWrites: Bool {
    cppMetadata?.pending_writes() ?? false
  }
}

/// A registration for a snapshot listener.
public protocol ListenerRegistration: Sendable {
  func remove()
}

/// Internal no-op listener registration for placeholder implementations.
struct NoOpListenerRegistration: ListenerRegistration {
  func remove() {}
}

/// Server timestamp behavior for decoding.
public enum ServerTimestampBehavior: Int, Sendable {
  case none = 0
  case estimate = 1
  case previous = 2
}

/// The source for data fetching.
public enum FirestoreSource: Int, Sendable {
  case `default` = 0
  case server = 1
  case cache = 2
}

/// The source for snapshot listeners.
public enum ListenSource: Int, Sendable {
  case `default` = 0
  case cache = 1
}

/// Snapshot listen options.
public final class SnapshotListenOptions: @unchecked Sendable {
  public var includeMetadataChanges: Bool = false
  public var source: ListenSource = .default
}

/// Progress of bundle loading.
public final class LoadBundleTaskProgress: @unchecked Sendable {
  public var totalDocuments: Int { 0 }
  public var documentsLoaded: Int { 0 }
  public var totalBytes: Int { 0 }
  public var bytesLoaded: Int { 0 }
}

/// GeoPoint for geographic data.
/// This wraps the C++ firebase::firestore::GeoPoint.
public struct GeoPoint: Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}
