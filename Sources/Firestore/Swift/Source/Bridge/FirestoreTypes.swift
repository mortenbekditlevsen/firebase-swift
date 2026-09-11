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
    // TODO: Implement via C++ interop (requires user data reader)
    completion?(nil)
  }

  public func setData(_ documentData: [String: Any],
                      merge: Bool,
                      completion: ((Error?) -> Void)? = nil) {
    // TODO: Implement via C++ interop (requires user data reader)
    completion?(nil)
  }

  public func setData(_ documentData: [String: Any],
                      mergeFields: [Any],
                      completion: ((Error?) -> Void)? = nil) {
    // TODO: Implement via C++ interop (requires user data reader)
    completion?(nil)
  }

  public func updateData(_ fields: [String: Any],
                         completion: ((Error?) -> Void)? = nil) {
    // TODO: Implement via C++ interop (requires user data reader)
    completion?(nil)
  }

  public func delete(completion: ((Error?) -> Void)? = nil) {
    // TODO: Implement via C++ interop (requires async callback bridging)
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
    // TODO: Implement via C++ interop (requires user data reader)
    return DocumentReference()
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
    // TODO: Implement via C++ data conversion
    nil
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
  public static func serverTimestamp() -> FieldValue { FieldValue() }
  public static func arrayUnion(_ elements: [Any]) -> FieldValue { FieldValue() }
  public static func arrayRemove(_ elements: [Any]) -> FieldValue { FieldValue() }
  public static func delete() -> FieldValue { FieldValue() }
  public static func increment(_ n: Int64) -> FieldValue { FieldValue() }
  public static func increment(_ n: Double) -> FieldValue { FieldValue() }

  /// Creates a VectorValue from an array of NSNumbers.
  /// This is the ObjC-compatible factory method used by FieldValue+Swift.swift.
  public static func __vector(with array: [NSNumber]) -> VectorValue {
    return VectorValue(array.map { $0.doubleValue })
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
