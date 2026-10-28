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

import FirebaseCore
import Foundation
import Synchronization

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
typealias CppWriteBatchBridge = firebase.firestore.swift_bridge.WriteBatchBridge
typealias CppTransactionBridge = firebase.firestore.swift_bridge.TransactionBridge
typealias CppDocumentChangeBridge = firebase.firestore.swift_bridge.DocumentChangeBridge
typealias CppDocumentChangeBridgeVector = firebase.firestore.swift_bridge
  .DocumentChangeBridgeVector

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
    return data.withUnsafeBytes { buffer in
      CppBridgeFieldValue.FromBlob(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
    }
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
/// If a `Firestore` instance is provided, Reference values will be resolved
/// to `DocumentReference` objects; otherwise they return path strings.
func fromBridgeFieldValue(_ value: CppBridgeFieldValue,
                          firestore: Firestore? = nil) -> Any {
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
    return fromBridgeFieldValueVector(value.array_value(), firestore: firestore)
  case .Map:
    return fromBridgeFieldValueMap(value.map_value(), firestore: firestore)
  case .Reference:
    let path = Swift.String(value.string_value())
    if let firestore = firestore {
      return firestore.document(path)
    }
    return path
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
func fromBridgeFieldValueMap(_ map: CppBridgeFieldValueMap,
                             firestore: Firestore? = nil) -> [String: Any] {
  var result: [String: Any] = [:]
  for i in 0 ..< map.size() {
    let entry = map[i]
    let key = Swift.String(entry.first)
    result[key] = fromBridgeFieldValue(entry.second, firestore: firestore)
  }
  return result
}

/// Convert a C++ `BridgeFieldValueVector` to a Swift array.
func fromBridgeFieldValueVector(_ vec: CppBridgeFieldValueVector,
                                firestore: Firestore? = nil) -> [Any] {
  var result: [Any] = []
  for i in 0 ..< vec.size() {
    result.append(fromBridgeFieldValue(vec[i], firestore: firestore))
  }
  return result
}

// MARK: - C Callback Bridging Helpers

/// Wraps a Swift closure into a C-compatible void* context + function pointer pair.
/// The context is a retained `Unmanaged` reference to a box holding the closure.
/// The callback function casts the context back and invokes the closure.

private final class DocumentSnapshotCallbackBox {
  let handler: (DocumentSnapshot?, Error?) -> Void
  init(_ handler: @escaping (DocumentSnapshot?, Error?) -> Void) {
    self.handler = handler
  }
}

private final class QuerySnapshotCallbackBox {
  let handler: (QuerySnapshot?, Error?) -> Void
  init(_ handler: @escaping (QuerySnapshot?, Error?) -> Void) {
    self.handler = handler
  }
}

private final class ErrorCallbackBox {
  let handler: (Error?) -> Void
  init(_ handler: @escaping (Error?) -> Void) {
    self.handler = handler
  }
}

/// C-compatible callback for document snapshot results (one-shot).
/// snapshot: heap-allocated DocumentSnapshotBridge* (caller takes ownership).
/// error: C string, empty means no error.
private func documentSnapshotCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  error: UnsafePointer<CChar>?
) {
  guard let context = context else { return }
  let box = Unmanaged<DocumentSnapshotCallbackBox>.fromOpaque(context)
    .takeRetainedValue()
  let errorStr = error.map { String(cString: $0) } ?? ""
  if errorStr.isEmpty, let snapshot = snapshot {
    let bridge = snapshot.assumingMemoryBound(to: CppDocumentSnapshotBridge.self)
    let swiftSnapshot = DocumentSnapshot(cppBridge: bridge.pointee)
    bridge.deinitialize(count: 1)
    bridge.deallocate()
    box.handler(swiftSnapshot, nil)
  } else {
    box.handler(nil, NSError(domain: "FirebaseFirestore", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: errorStr]))
  }
}

/// C-compatible callback for query snapshot results (one-shot).
private func querySnapshotCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  error: UnsafePointer<CChar>?
) {
  guard let context = context else { return }
  let box = Unmanaged<QuerySnapshotCallbackBox>.fromOpaque(context)
    .takeRetainedValue()
  let errorStr = error.map { String(cString: $0) } ?? ""
  if errorStr.isEmpty, let snapshot = snapshot {
    let bridge = snapshot.assumingMemoryBound(to: CppQuerySnapshotBridge.self)
    let swiftSnapshot = QuerySnapshot(cppBridge: bridge.pointee)
    bridge.deinitialize(count: 1)
    bridge.deallocate()
    box.handler(swiftSnapshot, nil)
  } else {
    box.handler(nil, NSError(domain: "FirebaseFirestore", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: errorStr]))
  }
}

/// C-compatible callback for error-only results (one-shot).
private func errorCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  error: UnsafePointer<CChar>?
) {
  guard let context = context else { return }
  let box = Unmanaged<ErrorCallbackBox>.fromOpaque(context)
    .takeRetainedValue()
  let errorStr = error.map { String(cString: $0) } ?? ""
  if errorStr.isEmpty {
    box.handler(nil)
  } else {
    box.handler(NSError(domain: "FirebaseFirestore", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errorStr]))
  }
}

/// Variant for document snapshot listeners (persistent, NOT released per call).
private func documentSnapshotListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  error: UnsafePointer<CChar>?
) {
  guard let context = context else { return }
  let box = Unmanaged<DocumentSnapshotCallbackBox>.fromOpaque(context)
    .takeUnretainedValue()
  let errorStr = error.map { String(cString: $0) } ?? ""
  if errorStr.isEmpty, let snapshot = snapshot {
    let bridge = snapshot.assumingMemoryBound(to: CppDocumentSnapshotBridge.self)
    let swiftSnapshot = DocumentSnapshot(cppBridge: bridge.pointee)
    bridge.deinitialize(count: 1)
    bridge.deallocate()
    box.handler(swiftSnapshot, nil)
  } else {
    box.handler(nil, NSError(domain: "FirebaseFirestore", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: errorStr]))
  }
}

/// Variant for query snapshot listeners (persistent).
private func querySnapshotListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  error: UnsafePointer<CChar>?
) {
  guard let context = context else { return }
  let box = Unmanaged<QuerySnapshotCallbackBox>.fromOpaque(context)
    .takeUnretainedValue()
  let errorStr = error.map { String(cString: $0) } ?? ""
  if errorStr.isEmpty, let snapshot = snapshot {
    let bridge = snapshot.assumingMemoryBound(to: CppQuerySnapshotBridge.self)
    let swiftSnapshot = QuerySnapshot(cppBridge: bridge.pointee)
    bridge.deinitialize(count: 1)
    bridge.deallocate()
    box.handler(swiftSnapshot, nil)
  } else {
    box.handler(nil, NSError(domain: "FirebaseFirestore", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: errorStr]))
  }
}

// MARK: - Core Firestore Types

/// The main Firestore database instance.
// MARK: - Credentials

/// Supplies Auth and App Check tokens to the C++ credentials providers. Each
/// context handed to C++ holds one retain, released by `releaseCredentialsSource`.
private final class CredentialsSource: Sendable {
  let auth: AuthInterop?
  let appCheck: AppCheckInterop?

  init(auth: AuthInterop?, appCheck: AppCheckInterop?) {
    self.auth = auth
    self.appCheck = appCheck
  }
}

/// Lets a pending C++ token request cross into a Task. C++ owns it until the
/// matching `Complete…TokenRequest` call, which must happen exactly once.
private struct PendingTokenRequest: @unchecked Sendable {
  let pointer: UnsafeMutableRawPointer
}

private func requestAuthToken(
  context: UnsafeMutableRawPointer?,
  forceRefresh: Bool,
  request: UnsafeMutableRawPointer?
) {
  guard let context, let request else { return }
  let source = Unmanaged<CredentialsSource>.fromOpaque(context).takeUnretainedValue()
  let pending = PendingTokenRequest(pointer: request)
  Task {
    do {
      let token = try await source.auth?.getToken(forcingRefresh: forceRefresh)
      firebase.firestore.swift_bridge.CompleteAuthTokenRequest(
        pending.pointer, std.string(token ?? ""), std.string()
      )
    } catch {
      firebase.firestore.swift_bridge.CompleteAuthTokenRequest(
        pending.pointer, std.string(), std.string(error.localizedDescription)
      )
    }
  }
}

private func requestAppCheckToken(
  context: UnsafeMutableRawPointer?,
  forceRefresh: Bool,
  request: UnsafeMutableRawPointer?
) {
  guard let context, let request else { return }
  let source = Unmanaged<CredentialsSource>.fromOpaque(context).takeUnretainedValue()
  let pending = PendingTokenRequest(pointer: request)
  Task {
    do {
      let token = try await source.appCheck?.getToken(forcingRefresh: forceRefresh)
      firebase.firestore.swift_bridge.CompleteAppCheckTokenRequest(
        pending.pointer, std.string(token ?? ""), std.string()
      )
    } catch {
      firebase.firestore.swift_bridge.CompleteAppCheckTokenRequest(
        pending.pointer, std.string(), std.string(error.localizedDescription)
      )
    }
  }
}

private func releaseCredentialsSource(context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<CredentialsSource>.fromOpaque(context).release()
}

public final class Firestore: @unchecked Sendable {
  var cppBridge: CppFirestoreBridge?

  /// Observes Auth's internal state notification to keep the C++ credentials
  /// provider's current user up to date.
  private var authObserver: (any NSObjectProtocol)?

  deinit {
    if let authObserver {
      NotificationCenter.default.removeObserver(authObserver)
    }
  }

  /// Cache of Firestore instances keyed by "appName/databaseId".
  private nonisolated(unsafe) static let _instances = Mutex<[String: Firestore]>([:])

  init() {
    cppBridge = nil
  }

  init(cppBridge: CppFirestoreBridge) {
    self.cppBridge = cppBridge
  }

  /// Returns the default Firestore instance for the default FirebaseApp.
  public static func firestore() -> Firestore {
    guard let app = FirebaseApp.app() else {
      fatalError(
        "FirebaseApp has not been configured. Call FirebaseApp.configure() before using Firestore."
      )
    }
    return firestore(app: app)
  }

  /// Returns a Firestore instance for the given app and database.
  public static func firestore(app: FirebaseApp, database: String = "(default)") -> Firestore {
    let key = "\(app.name)/\(database)"
    return _instances.withLock { instances in
      if let existing = instances[key] {
        return existing
      }
      let projectID = app.options.projectID ?? ""
      let auth = app.auth
      let appCheck = app.appCheck
      let source = CredentialsSource(auth: auth, appCheck: appCheck)
      let authContext = auth.map { _ in Unmanaged.passRetained(source).toOpaque() }
      let appCheckContext = appCheck.map { _ in Unmanaged.passRetained(source).toOpaque() }
      let authCallback: TokenRequestCallback? = auth == nil ? nil : requestAuthToken
      let appCheckCallback: TokenRequestCallback? = appCheck == nil ? nil : requestAppCheckToken
      let bridge = CppFirestoreBridge.Create(
        std.string(projectID),
        std.string(database),
        std.string(app.name),
        authContext,
        authCallback,
        std.string(auth?.getUserID() ?? ""),
        appCheckContext,
        appCheckCallback,
        releaseCredentialsSource
      )
      let instance = Firestore(cppBridge: bridge)
      if let auth {
        // swift-corelibs-foundation never matches an `object:` filter that is a
        // pure Swift class, so filter by identity in the block instead.
        instance.authObserver = NotificationCenter.default.addObserver(
          forName: .FIRAuthStateDidChangeInternalNotification,
          object: nil,
          queue: nil
        ) { [weak instance, weak auth] notification in
          guard let auth, (notification.object as AnyObject?) === auth else { return }
          let uid = notification.userInfo?[FIRAuthStateDidChangeInternalNotificationUIDKey]
            as? String
          instance?.cppBridge?.SetAuthUser(std.string(uid ?? ""))
        }
        // The user may have changed between reading the initial UID and
        // registering the observer.
        bridge.SetAuthUser(std.string(auth.getUserID() ?? ""))
      }
      instances[key] = instance
      return instance
    }
  }

  public func collection(_ collectionPath: String) -> CollectionReference {
    guard let bridge = cppBridge else { return CollectionReference() }
    let cppRef = bridge.GetCollection(std.string(collectionPath))
    return CollectionReference(cppBridge: cppRef, firestore: self)
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

  public func collectionGroup(_ collectionID: String) -> Query {
    guard let bridge = cppBridge else { return Query(cppBridge: CppQueryBridge(), firestore: self) }
    let cppQuery = bridge.GetCollectionGroup(std.string(collectionID))
    return Query(cppBridge: cppQuery, firestore: self)
  }

  /// Connects to the emulated Firestore at `host:port` instead of the real
  /// backend. Call it before using this instance. As upstream, this only sets
  /// the host; the emulator doesn't use TLS, so also set
  /// `settings.isSSLEnabled = false`.
  public func useEmulator(withHost host: String, port: Int) {
    precondition(!host.isEmpty, "Host cannot be nil or empty.")
    let newSettings = settings
    newSettings.host = "\(host):\(port)"
    settings = newSettings
  }

  public var settings: FirestoreSettings {
    get {
      let s = FirestoreSettings()
      if let bridge = cppBridge {
        s.host = String(bridge.settings_host())
        s.isPersistenceEnabled = bridge.settings_persistence_enabled()
        s.isSSLEnabled = bridge.settings_ssl_enabled()
        s.cacheSizeBytes = Int(bridge.settings_cache_size_bytes())
      }
      return s
    }
    set {
      guard let bridge = cppBridge else { return }
      var mutBridge = bridge
      mutBridge.set_settings_host(std.string(newValue.host))
      mutBridge.set_settings_persistence_enabled(newValue.isPersistenceEnabled)
      mutBridge.set_settings_ssl_enabled(newValue.isSSLEnabled)
      mutBridge.set_settings_cache_size_bytes(Int64(newValue.cacheSizeBytes))
      cppBridge = mutBridge
    }
  }

  public func terminate() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let bridge = cppBridge else {
        continuation.resume()
        return
      }
      let box = ErrorCallbackBox { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.Terminate(context, errorCallbackTrampoline)
    }
  }

  public func clearPersistence() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let bridge = cppBridge else {
        continuation.resume()
        return
      }
      let box = ErrorCallbackBox { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.ClearPersistence(context, errorCallbackTrampoline)
    }
  }

  public func waitForPendingWrites() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let bridge = cppBridge else {
        continuation.resume()
        return
      }
      let box = ErrorCallbackBox { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.WaitForPendingWrites(context, errorCallbackTrampoline)
    }
  }

  public func enableNetwork() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let bridge = cppBridge else {
        continuation.resume()
        return
      }
      let box = ErrorCallbackBox { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.EnableNetwork(context, errorCallbackTrampoline)
    }
  }

  public func disableNetwork() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let bridge = cppBridge else {
        continuation.resume()
        return
      }
      let box = ErrorCallbackBox { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.DisableNetwork(context, errorCallbackTrampoline)
    }
  }

  public func batch() -> WriteBatch {
    guard let bridge = cppBridge else { return WriteBatch() }
    return WriteBatch(cppBridge: bridge.GetBatch())
  }

  #if canImport(Darwin)
    /// Upstream's form, kept for source compatibility on Apple platforms. Setting
    /// the error pointer aborts the transaction with that error.
    public func runTransaction(_ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?,
                               completion: @escaping (Any?, Error?) -> Void) {
      runTransaction({ transaction in
        var error: NSError?
        let result = updateBlock(transaction, &error)
        if let error { throw error }
        return result
      }, completion: completion)
    }
  #endif

  /// Runs `updateBlock` in a transaction, retrying it if the documents it read
  /// change before it commits. Throwing from `updateBlock` aborts the
  /// transaction, and the thrown error is passed to `completion`.
  public func runTransaction(_ updateBlock: @escaping (Transaction) throws -> Any?,
                             completion: @escaping (Any?, Error?) -> Void) {
    guard let bridge = cppBridge else {
      completion(nil, NSError(domain: "FirebaseFirestore", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Firestore not initialized"]))
      return
    }

    // Box to hold the update block and its result for the C callback.
    final class TransactionContext {
      let updateBlock: (Transaction) throws -> Any?
      let completion: (Any?, Error?) -> Void
      var result: Any?
      /// The error thrown by the last attempt of `updateBlock`, if any.
      var updateError: Error?

      init(updateBlock: @escaping (Transaction) throws -> Any?,
           completion: @escaping (Any?, Error?) -> Void) {
        self.updateBlock = updateBlock
        self.completion = completion
      }
    }

    let ctx = TransactionContext(updateBlock: updateBlock, completion: completion)
    let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

    // The update callback invoked by C++ for each transaction attempt.
    let updateCB:
      @convention(c) (
        UnsafeMutableRawPointer?,     // context
        UnsafeMutableRawPointer?,     // transaction_ptr
        ErrorCallback?,               // completion callback
        UnsafeMutableRawPointer?      // completion context
      ) -> Void = { context, transactionPtr, completionCB, completionCtx in
      guard let context = context, let transactionPtr = transactionPtr else { return }
      let txCtx = Unmanaged<TransactionContext>.fromOpaque(context).takeUnretainedValue()

      let cppTxn = transactionPtr.assumingMemoryBound(to: CppTransactionBridge.self)
      let transaction = Transaction(cppBridge: cppTxn.pointee)

      var error: Error?
      do {
        txCtx.result = try txCtx.updateBlock(transaction)
        txCtx.updateError = nil
      } catch let thrown {
        error = thrown
        txCtx.updateError = thrown
      }

      // Clean up the heap-allocated TransactionBridge.
      cppTxn.deinitialize(count: 1)
      cppTxn.deallocate()

      if let error = error {
        let msg = error.localizedDescription
        msg.withCString { cStr in
          completionCB?(completionCtx, cStr)
        }
      } else {
        completionCB?(completionCtx, "")
      }
    }

    // The result callback invoked when the transaction completes.
    let resultCB:
      @convention(c) (
        UnsafeMutableRawPointer?,     // context
        UnsafePointer<CChar>?         // error
      ) -> Void = { context, error in
      guard let context = context else { return }
      let txCtx = Unmanaged<TransactionContext>.fromOpaque(context).takeRetainedValue()
      let errorStr = error.map { String(cString: $0) } ?? ""
      if errorStr.isEmpty {
        txCtx.completion(txCtx.result, nil)
      } else if let updateError = txCtx.updateError {
        // Report the caller's own error rather than its string form.
        txCtx.completion(nil, updateError)
      } else {
        txCtx.completion(nil, NSError(domain: "FirebaseFirestore", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: errorStr]))
      }
    }

    bridge.RunTransaction(ctxPtr, updateCB, ctxPtr, resultCB, 5)
  }
}

/// A reference to a Firestore document.
public final class DocumentReference: Hashable, @unchecked Sendable {
  var cppBridge: CppDocumentReferenceBridge

  public static func == (lhs: DocumentReference, rhs: DocumentReference) -> Bool {
    lhs.cppBridge.IsEqual(rhs.cppBridge)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cppBridge.Hash())
  }

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

  /// A subcollection of this document. `collectionPath` is relative to the
  /// document, e.g. `"messages"`.
  public func collection(_ collectionPath: String) -> CollectionReference {
    CollectionReference(cppBridge: cppBridge.Collection(std.string(collectionPath)))
  }

  public func setData(_ documentData: [String: Any],
                      completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(documentData)
    if let completion = completion {
      let box = ErrorCallbackBox(completion)
      let context = Unmanaged.passRetained(box).toOpaque()
      let parseError = String(cppBridge.SetDataC(map, context, errorCallbackTrampoline))
      if !parseError.isEmpty {
        // Parse error — release the retained box and report immediately
        _ = Unmanaged<ErrorCallbackBox>.fromOpaque(context).takeRetainedValue()
        completion(NSError(domain: "FirebaseFirestore", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: parseError]))
      }
    } else {
      _ = cppBridge.SetData(map)
    }
  }

  public func setData(_ documentData: [String: Any],
                      merge: Bool,
                      completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(documentData)
    if let completion = completion {
      let box = ErrorCallbackBox(completion)
      let context = Unmanaged.passRetained(box).toOpaque()
      let parseError: String
      if merge {
        parseError = String(cppBridge.SetDataMergeC(map, context, errorCallbackTrampoline))
      } else {
        parseError = String(cppBridge.SetDataC(map, context, errorCallbackTrampoline))
      }
      if !parseError.isEmpty {
        _ = Unmanaged<ErrorCallbackBox>.fromOpaque(context).takeRetainedValue()
        completion(NSError(domain: "FirebaseFirestore", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: parseError]))
      }
    } else {
      if merge {
        _ = cppBridge.SetDataMerge(map)
      } else {
        _ = cppBridge.SetData(map)
      }
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
        fields.push_back(std.string(fp.dotSeparatedString))
      }
    }
    if let completion = completion {
      // SetDataMergeFields doesn't have a C-callback variant yet, use fire-and-forget
      let error = String(cppBridge.SetDataMergeFields(map, fields))
      if error.isEmpty {
        completion(nil)
      } else {
        completion(NSError(domain: "FirebaseFirestore", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: error]))
      }
    } else {
      _ = cppBridge.SetDataMergeFields(map, fields)
    }
  }

  public func updateData(_ fields: [String: Any],
                         completion: ((Error?) -> Void)? = nil) {
    let map = toBridgeFieldValueMap(fields)
    if let completion = completion {
      let box = ErrorCallbackBox(completion)
      let context = Unmanaged.passRetained(box).toOpaque()
      let parseError = String(cppBridge.UpdateDataC(map, context, errorCallbackTrampoline))
      if !parseError.isEmpty {
        _ = Unmanaged<ErrorCallbackBox>.fromOpaque(context).takeRetainedValue()
        completion(NSError(domain: "FirebaseFirestore", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: parseError]))
      }
    } else {
      _ = cppBridge.UpdateData(map)
    }
  }

  public func delete(completion: ((Error?) -> Void)? = nil) {
    if let completion = completion {
      let box = ErrorCallbackBox(completion)
      let context = Unmanaged.passRetained(box).toOpaque()
      cppBridge.DeleteDocumentC(context, errorCallbackTrampoline)
    } else {
      cppBridge.DeleteDocumentNoCallback()
    }
  }

  public func getDocument(source: FirestoreSource = .default,
                          completion: @escaping (DocumentSnapshot?, Error?) -> Void) {
    let firestore = self.parent.firestore
    let wrappedCompletion: (DocumentSnapshot?, Error?) -> Void = { snapshot, error in
      snapshot?._firestore = firestore
      completion(snapshot, error)
    }
    let box = DocumentSnapshotCallbackBox(wrappedCompletion)
    let context = Unmanaged.passRetained(box).toOpaque()
    cppBridge.GetDocumentC(source.cppSource, context, documentSnapshotCallbackTrampoline)
  }

  public func getDocument(source: FirestoreSource = .default) async throws -> DocumentSnapshot {
    try await withCheckedThrowingContinuation { continuation in
      getDocument(source: source) { snapshot, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else if let snapshot = snapshot {
          continuation.resume(returning: snapshot)
        } else {
          continuation.resume(throwing: NSError(
            domain: "FirebaseFirestore", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
        }
      }
    }
  }

  public func addSnapshotListener(includeMetadataChanges: Bool = false,
                                  listener: @escaping (DocumentSnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    let firestore = self.parent.firestore
    let wrappedListener: (DocumentSnapshot?, Error?) -> Void = { snapshot, error in
      snapshot?._firestore = firestore
      listener(snapshot, error)
    }
    let box = DocumentSnapshotCallbackBox(wrappedListener)
    let context = Unmanaged.passUnretained(box).toOpaque()
    let registration = cppBridge.AddSnapshotListener(
      includeMetadataChanges, context, documentSnapshotListenerTrampoline)
    return BridgeListenerRegistration(cppBridge: registration, retainedContext: box)
  }
}

/// A reference to a Firestore collection.
public final class CollectionReference: Query, @unchecked Sendable {
  private var _collectionBridge: CppCollectionReferenceBridge?

  init() {
    _collectionBridge = nil
    super.init(cppBridge: CppQueryBridge(), firestore: nil)
  }

  init(cppBridge: CppCollectionReferenceBridge, firestore: Firestore? = nil) {
    _collectionBridge = cppBridge
    // Use as_query() to get the QueryBridge base from the CollectionReferenceBridge.
    // Swift C++ interop doesn't expose C++ base class members directly.
    super.init(cppBridge: cppBridge.as_query(), firestore: firestore)
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
  private weak var _firestore: Firestore?

  init(cppBridge: CppQueryBridge, firestore: Firestore? = nil) {
    cppQueryBridge = cppBridge
    _firestore = firestore
  }

  public var firestore: Firestore { _firestore ?? Firestore() }

  public func getDocuments(source: FirestoreSource = .default,
                           completion: @escaping (QuerySnapshot?, Error?) -> Void) {
    let firestore = self._firestore
    let wrappedCompletion: (QuerySnapshot?, Error?) -> Void = { snapshot, error in
      snapshot?._firestore = firestore
      completion(snapshot, error)
    }
    let box = QuerySnapshotCallbackBox(wrappedCompletion)
    let context = Unmanaged.passRetained(box).toOpaque()
    cppQueryBridge.GetDocumentsC(source.cppSource, context, querySnapshotCallbackTrampoline)
  }

  public func getDocuments(source: FirestoreSource = .default) async throws -> QuerySnapshot {
    try await withCheckedThrowingContinuation { continuation in
      getDocuments(source: source) { snapshot, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else if let snapshot = snapshot {
          continuation.resume(returning: snapshot)
        } else {
          continuation.resume(throwing: NSError(
            domain: "FirebaseFirestore", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
        }
      }
    }
  }

  public func addSnapshotListener(includeMetadataChanges: Bool = false,
                                  listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    let firestore = self._firestore
    let wrappedListener: (QuerySnapshot?, Error?) -> Void = { snapshot, error in
      snapshot?._firestore = firestore
      listener(snapshot, error)
    }
    let box = QuerySnapshotCallbackBox(wrappedListener)
    let context = Unmanaged.passUnretained(box).toOpaque()
    let registration = cppQueryBridge.AddSnapshotListener(
      includeMetadataChanges, context, querySnapshotListenerTrampoline)
    return BridgeListenerRegistration(cppBridge: registration, retainedContext: box)
  }

  public func addSnapshotListener(_ listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    return addSnapshotListener(includeMetadataChanges: false, listener: listener)
  }

  // MARK: - Query modifiers

  public func whereField(_ field: String, isEqualTo value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereEqualTo(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, isNotEqualTo value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereNotEqualTo(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, isLessThan value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereLessThan(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, isGreaterThan value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereGreaterThan(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereLessThanOrEqual(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, isGreaterThanOrEqualTo value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereGreaterThanOrEqual(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, in values: [Any]) -> Query {
    var cppValues = CppBridgeFieldValueVector()
    for v in values { cppValues.push_back(toBridgeFieldValue(v)) }
    return Query(cppBridge: cppQueryBridge.WhereIn(std.string(field), cppValues), firestore: _firestore)
  }
  public func whereField(_ field: String, notIn values: [Any]) -> Query {
    var cppValues = CppBridgeFieldValueVector()
    for v in values { cppValues.push_back(toBridgeFieldValue(v)) }
    return Query(cppBridge: cppQueryBridge.WhereNotIn(std.string(field), cppValues), firestore: _firestore)
  }
  public func whereField(_ field: String, arrayContains value: Any) -> Query {
    Query(cppBridge: cppQueryBridge.WhereArrayContains(std.string(field), toBridgeFieldValue(value)), firestore: _firestore)
  }
  public func whereField(_ field: String, arrayContainsAny values: [Any]) -> Query {
    var cppValues = CppBridgeFieldValueVector()
    for v in values { cppValues.push_back(toBridgeFieldValue(v)) }
    return Query(cppBridge: cppQueryBridge.WhereArrayContainsAny(std.string(field), cppValues), firestore: _firestore)
  }

  public func order(by field: String, descending: Bool = false) -> Query {
    let newBridge = cppQueryBridge.OrderBy(std.string(field), descending)
    return Query(cppBridge: newBridge, firestore: _firestore)
  }

  public func limit(to limit: Int) -> Query {
    let newBridge = cppQueryBridge.LimitToFirst(Int32(limit))
    return Query(cppBridge: newBridge, firestore: _firestore)
  }

  public func limit(toLast limit: Int) -> Query {
    let newBridge = cppQueryBridge.LimitToLast(Int32(limit))
    return Query(cppBridge: newBridge, firestore: _firestore)
  }

  public func start(atDocument document: DocumentSnapshot) -> Query {
    Query(cppBridge: cppQueryBridge.StartAtDocument(document.cppBridge), firestore: _firestore)
  }
  public func start(afterDocument document: DocumentSnapshot) -> Query {
    Query(cppBridge: cppQueryBridge.StartAfterDocument(document.cppBridge), firestore: _firestore)
  }
  public func end(atDocument document: DocumentSnapshot) -> Query {
    Query(cppBridge: cppQueryBridge.EndAtDocument(document.cppBridge), firestore: _firestore)
  }
  public func end(beforeDocument document: DocumentSnapshot) -> Query {
    Query(cppBridge: cppQueryBridge.EndBeforeDocument(document.cppBridge), firestore: _firestore)
  }
}

/// A snapshot of a document.
public final class DocumentSnapshot: @unchecked Sendable {
  fileprivate var cppBridge: CppDocumentSnapshotBridge
  fileprivate weak var _firestore: Firestore?

  init() {
    cppBridge = CppDocumentSnapshotBridge()
  }

  init(cppBridge: CppDocumentSnapshotBridge, firestore: Firestore? = nil) {
    self.cppBridge = cppBridge
    self._firestore = firestore
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
    return fromBridgeFieldValueMap(cppMap, firestore: _firestore)
  }

  public var reference: DocumentReference {
    DocumentReference(cppBridge: cppBridge.create_reference())
  }

  public var documentID: String {
    String(cppBridge.document_id())
  }

  public func data(with serverTimestampBehavior: ServerTimestampBehavior) -> [String: Any]? {
    guard cppBridge.exists() else { return nil }
    let cppMap = cppBridge.data_with_server_timestamps(Int32(serverTimestampBehavior.rawValue))
    return fromBridgeFieldValueMap(cppMap, firestore: _firestore)
  }

  public func get(_ field: String) -> Any? {
    guard cppBridge.exists() else { return nil }
    let value = cppBridge.get_field(std.string(field))
    if value.tag() == .Null {
      return nil
    }
    return fromBridgeFieldValue(value, firestore: _firestore)
  }

  public func get(_ field: String,
                  serverTimestampBehavior: ServerTimestampBehavior) -> Any? {
    guard cppBridge.exists() else { return nil }
    let value = cppBridge.get_field_with_server_timestamps(
      std.string(field), Int32(serverTimestampBehavior.rawValue))
    if value.tag() == .Null {
      return nil
    }
    return fromBridgeFieldValue(value, firestore: _firestore)
  }
}

/// A snapshot of a query result.
public final class QuerySnapshot: @unchecked Sendable {
  private var cppBridge: CppQuerySnapshotBridge
  fileprivate weak var _firestore: Firestore?

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
      result.append(DocumentSnapshot(cppBridge: cppDocs[i], firestore: _firestore))
    }
    return result
  }

  public var isEmpty: Bool {
    cppBridge.empty()
  }

  public var count: Int {
    Int(cppBridge.size())
  }

  public var documentChanges: [DocumentChange] {
    documentChanges(includeMetadataChanges: false)
  }

  public func documentChanges(includeMetadataChanges: Bool) -> [DocumentChange] {
    let cppChanges = cppBridge.document_changes(includeMetadataChanges)
    var result: [DocumentChange] = []
    for i in 0 ..< cppChanges.size() {
      result.append(DocumentChange(cppBridge: cppChanges[i], firestore: _firestore))
    }
    return result
  }

  public var metadata: SnapshotMetadata {
    SnapshotMetadata(cppMetadata: cppBridge.metadata())
  }
}

/// A change to a document in a query result.
public final class DocumentChange: @unchecked Sendable {
  private var cppBridge: CppDocumentChangeBridge
  private weak var _firestore: Firestore?

  init(cppBridge: CppDocumentChangeBridge, firestore: Firestore? = nil) {
    self.cppBridge = cppBridge
    self._firestore = firestore
  }

  public var type: DocumentChangeType {
    switch cppBridge.type() {
    case .Added: return .added
    case .Modified: return .modified
    case .Removed: return .removed
    default: return .added
    }
  }

  public var document: DocumentSnapshot {
    DocumentSnapshot(cppBridge: cppBridge.document(), firestore: _firestore)
  }

  public var oldIndex: UInt {
    let idx = cppBridge.old_index()
    return idx < 0 ? UInt(NSNotFound) : UInt(idx)
  }

  public var newIndex: UInt {
    let idx = cppBridge.new_index()
    return idx < 0 ? UInt(NSNotFound) : UInt(idx)
  }
}

/// The type of document change.
public enum DocumentChangeType: Int, Sendable {
  case added = 0
  case modified = 1
  case removed = 2
}

/// A batch of write operations.
public final class WriteBatch: @unchecked Sendable {
  private var cppBridge: CppWriteBatchBridge?

  init() {
    cppBridge = nil
  }

  init(cppBridge: CppWriteBatchBridge) {
    self.cppBridge = cppBridge
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference) -> WriteBatch {
    guard var bridge = cppBridge else { return self }
    let map = toBridgeFieldValueMap(data)
    _ = bridge.SetData(doc.cppBridge, map)
    cppBridge = bridge
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> WriteBatch {
    guard var bridge = cppBridge else { return self }
    let map = toBridgeFieldValueMap(data)
    if merge {
      _ = bridge.SetDataMerge(doc.cppBridge, map)
    } else {
      _ = bridge.SetData(doc.cppBridge, map)
    }
    cppBridge = bridge
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> WriteBatch {
    // mergeFields variant not yet in C++ bridge — fall back to merge
    return setData(data, forDocument: doc, merge: true)
  }

  @discardableResult
  public func updateData(_ fields: [String: Any],
                         forDocument doc: DocumentReference) -> WriteBatch {
    guard var bridge = cppBridge else { return self }
    let map = toBridgeFieldValueMap(fields)
    _ = bridge.UpdateData(doc.cppBridge, map)
    cppBridge = bridge
    return self
  }

  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> WriteBatch {
    guard var bridge = cppBridge else { return self }
    bridge.DeleteData(doc.cppBridge)
    cppBridge = bridge
    return self
  }

  public func commit(completion: ((Error?) -> Void)? = nil) {
    guard var bridge = cppBridge else {
      completion?(nil)
      return
    }
    if let completion = completion {
      let box = ErrorCallbackBox(completion)
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.Commit(context, errorCallbackTrampoline)
      cppBridge = bridge
    } else {
      // Fire-and-forget: commit with no-op callback
      let box = ErrorCallbackBox { _ in }
      let context = Unmanaged.passRetained(box).toOpaque()
      bridge.Commit(context, errorCallbackTrampoline)
      cppBridge = bridge
    }
  }

  public func commit() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      commit { error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}

/// A Firestore transaction.
public final class Transaction: @unchecked Sendable {
  private var cppBridge: CppTransactionBridge

  init(cppBridge: CppTransactionBridge) {
    self.cppBridge = cppBridge
  }

  @discardableResult
  public func setData(_ data: [String: Any],
                      forDocument doc: DocumentReference) -> Transaction {
    let map = toBridgeFieldValueMap(data)
    _ = cppBridge.SetData(doc.cppBridge, map)
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> Transaction {
    let map = toBridgeFieldValueMap(data)
    if merge {
      _ = cppBridge.SetDataMerge(doc.cppBridge, map)
    } else {
      _ = cppBridge.SetData(doc.cppBridge, map)
    }
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> Transaction {
    // mergeFields variant not yet in C++ bridge — fall back to merge
    return setData(data, forDocument: doc, merge: true)
  }

  @discardableResult
  public func updateData(_ fields: [String: Any],
                         forDocument doc: DocumentReference) -> Transaction {
    let map = toBridgeFieldValueMap(fields)
    _ = cppBridge.UpdateData(doc.cppBridge, map)
    return self
  }

  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> Transaction {
    cppBridge.DeleteData(doc.cppBridge)
    return self
  }

  public func getDocument(_ doc: DocumentReference) throws -> DocumentSnapshot {
    var errorStr = std.string()
    let snapshot = cppBridge.GetDocument(doc.cppBridge, &errorStr)
    let error = String(errorStr)
    if !error.isEmpty {
      throw NSError(domain: "FirebaseFirestore", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: error])
    }
    return DocumentSnapshot(cppBridge: snapshot)
  }
}

/// A path to a field in a Firestore document.
public final class FieldPath: @unchecked Sendable {
  let fieldNames: [String]

  public init(_ fieldNames: [String]) {
    self.fieldNames = fieldNames
  }

  public init(_ fieldName: String) {
    self.fieldNames = [fieldName]
  }

  /// Returns the dot-separated string representation of this field path.
  var dotSeparatedString: String {
    fieldNames.joined(separator: ".")
  }

  /// The special sentinel FieldPath to refer to the document ID.
  public static func documentID() -> FieldPath { FieldPath(["__name__"]) }
}

/// Sentinel values for field operations.
public final class FieldValue: Hashable, @unchecked Sendable {
  let sentinel: FieldValueSentinel

  private init(_ sentinel: FieldValueSentinel) {
    self.sentinel = sentinel
  }

  /// Matches upstream `isEqual:`: sentinels of the same kind are equal, and
  /// array transforms also compare their elements.
  public static func == (lhs: FieldValue, rhs: FieldValue) -> Bool {
    switch (lhs.sentinel, rhs.sentinel) {
    case (.delete_, .delete_), (.serverTimestamp, .serverTimestamp):
      return true
    case let (.arrayUnion(a), .arrayUnion(b)), let (.arrayRemove(a), .arrayRemove(b)):
      return NSArray(array: a).isEqual(to: b)
    case let (.incrementInt(a), .incrementInt(b)):
      return a == b
    case let (.incrementDouble(a), .incrementDouble(b)):
      return a == b
    default:
      return false
    }
  }

  /// Consistent with `==`. Array elements are `Any`, so only their count is
  /// hashed. Hashable (not just Equatable) also makes `NSDictionary` equality
  /// work on Linux, where swift-corelibs-foundation compares boxed Swift values
  /// through `AnyHashable`.
  public func hash(into hasher: inout Hasher) {
    switch sentinel {
    case .delete_:
      hasher.combine(0)
    case .serverTimestamp:
      hasher.combine(1)
    case let .arrayUnion(elements):
      hasher.combine(2)
      hasher.combine(elements.count)
    case let .arrayRemove(elements):
      hasher.combine(3)
      hasher.combine(elements.count)
    case let .incrementInt(value):
      hasher.combine(4)
      hasher.combine(value)
    case let .incrementDouble(value):
      hasher.combine(5)
      hasher.combine(value)
    }
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
  public var isSSLEnabled: Bool = true
  public var cacheSizeBytes: Int = 100 * 1024 * 1024  // 100 MB default

  public init() {}
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

/// Listener registration backed by the C++ bridge.
/// Holds a retained reference to the callback box and releases it on removal.
final class BridgeListenerRegistration: ListenerRegistration, @unchecked Sendable {
  private var cppBridge: CppListenerRegistrationBridge
  private var retainedContext: AnyObject?
  private var removed = false

  init(cppBridge: CppListenerRegistrationBridge, retainedContext: AnyObject?) {
    self.cppBridge = cppBridge
    self.retainedContext = retainedContext
  }

  func remove() {
    guard !removed else { return }
    removed = true
    cppBridge.Remove()
    // Release the retained callback box by dropping our strong reference.
    retainedContext = nil
  }

  deinit {
    if !removed {
      cppBridge.Remove()
    }
  }
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
public struct GeoPoint: Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}
