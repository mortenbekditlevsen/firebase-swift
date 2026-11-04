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
typealias CppBridgeUpdateData = firebase.firestore.swift_bridge.BridgeUpdateData
typealias CppBridgeUpdateEntry = firebase.firestore.swift_bridge.BridgeUpdateEntry
typealias CppFieldPathVector = firebase.firestore.swift_bridge.FieldPathVector
typealias CppSetOption = firebase.firestore.swift_bridge.SetOption
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
  case increment(Any)
  case minimum(Any)
  case maximum(Any)
}

/// The value inside an `Optional` boxed in `Any`, or nil for `.none`, so a
/// nil in `[String: Any]` is stored as null, as it is upstream.
private func unwrappingOptional(_ value: Any) -> Any? {
  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else { return value }
  return mirror.children.first.flatMap { unwrappingOptional($0.value) }
}

/// Converts an `NSNumber` by its Objective-C type, as upstream does.
private func toBridgeFieldValue(_ number: NSNumber) -> CppBridgeFieldValue {
  switch String(cString: number.objCType).first {
  case "c", "B", "C":
    return CppBridgeFieldValue.FromBool(number.boolValue)
  case "f", "d":
    return CppBridgeFieldValue.FromDouble(number.doubleValue)
  case "L", "Q":
    let value = number.uint64Value
    if value > UInt64(Int64.max) {
      invalidArgument("NSNumber (\(value)) is too large")
    }
    return CppBridgeFieldValue.FromInt64(Int64(value))
  default:
    return CppBridgeFieldValue.FromInt64(number.int64Value)
  }
}

/// Converts a Swift value to a C++ `BridgeFieldValue`. Values Firestore can't
/// store are passed as `Unsupported`, which fails with upstream's message when
/// the data is parsed.
func toBridgeFieldValue(_ value: Any) -> CppBridgeFieldValue {
  guard let value = unwrappingOptional(value) else {
    return CppBridgeFieldValue.Null()
  }

  switch value {
  case let fieldValue as FieldValue:
    return fieldValue.toBridgeFieldValue()
  case is NSNull:
    return CppBridgeFieldValue.Null()
  // A real NSNumber (from JSON, say), not a Swift number bridged to one.
  case let number as NSNumber where type(of: value) is NSNumber.Type:
    return toBridgeFieldValue(number)
  case let bool as Bool:
    return CppBridgeFieldValue.FromBool(bool)
  case let int as Int:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int64:
    return CppBridgeFieldValue.FromInt64(int)
  case let int as Int32:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int16:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let int as Int8:
    return CppBridgeFieldValue.FromInt64(Int64(int))
  case let uint as UInt:
    return toBridgeFieldValue(NSNumber(value: uint))
  case let uint as UInt64:
    return toBridgeFieldValue(NSNumber(value: uint))
  case let uint as UInt32:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let uint as UInt16:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let uint as UInt8:
    return CppBridgeFieldValue.FromInt64(Int64(uint))
  case let double as Double:
    return CppBridgeFieldValue.FromDouble(double)
  case let float as Float:
    return CppBridgeFieldValue.FromDouble(Double(float))
  case let string as String:
    return CppBridgeFieldValue.FromString(std.string(string))
  // Upstream gets substrings as NSStrings.
  case let substring as Substring:
    return CppBridgeFieldValue.FromString(std.string(String(substring)))
  case let data as Data:
    return data.withUnsafeBytes { buffer in
      CppBridgeFieldValue.FromBlob(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
    }
  case let timestamp as Timestamp:
    return CppBridgeFieldValue.FromTimestamp(timestamp.seconds, timestamp.nanoseconds)
  case let date as Date:
    let timestamp = Timestamp(date: date)
    return CppBridgeFieldValue.FromTimestamp(timestamp.seconds, timestamp.nanoseconds)
  case let geoPoint as GeoPoint:
    return CppBridgeFieldValue.FromGeoPoint(geoPoint.latitude, geoPoint.longitude)
  case let vector as VectorValue:
    var doubles = CppDoubleVector()
    for d in vector.array {
      doubles.push_back(d)
    }
    return CppBridgeFieldValue.FromVector(doubles)
  case let reference as DocumentReference:
    return CppBridgeFieldValue.FromReference(reference.cppBridge)
  case is MinKey:
    return CppBridgeFieldValue.MinKey()
  case is MaxKey:
    return CppBridgeFieldValue.MaxKey()
  case let regex as RegexValue:
    return CppBridgeFieldValue.FromRegex(std.string(regex.pattern), std.string(regex.options))
  case let int32 as Int32Value:
    return CppBridgeFieldValue.FromInt32(int32.value)
  case let decimal as Decimal128Value:
    return CppBridgeFieldValue.FromDecimal128(std.string(decimal.value))
  case let objectId as BSONObjectId:
    return CppBridgeFieldValue.FromBsonObjectId(std.string(objectId.value))
  case let timestamp as BSONTimestamp:
    return CppBridgeFieldValue.FromBsonTimestamp(timestamp.seconds, timestamp.increment)
  case let blob as Blob:
    return blob.bytes.withUnsafeBytes { buffer in
      CppBridgeFieldValue.FromBsonBinaryData(
        buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, blob.subtype
      )
    }
  case let array as [Any]:
    var cppArray = CppBridgeFieldValueVector()
    for element in array {
      cppArray.push_back(toBridgeFieldValue(element))
    }
    return CppBridgeFieldValue.FromArray(cppArray)
  case let dictionary as [String: Any]:
    return CppBridgeFieldValue.FromMap(toBridgeFieldValueMap(dictionary))
  default:
    return CppBridgeFieldValue.Unsupported(std.string(String(describing: type(of: value))))
  }
}

/// Convert a Swift dictionary to a C++ `BridgeFieldValueMap`.
func toBridgeFieldValueMap(_ dict: [String: Any]) -> CppBridgeFieldValueMap {
  var map = CppBridgeFieldValueMap()
  for (key, value) in dict {
    map.push_back(CppBridgeFieldValueMapEntry(first: std.string(key), second: toBridgeFieldValue(value)))
  }
  return map
}

/// The data of an `updateData` call, whose keys are dot-separated strings or
/// `FieldPath`s.
func toBridgeUpdateData(_ fields: [AnyHashable: Any]) -> CppBridgeUpdateData {
  var data = CppBridgeUpdateData()
  for (key, value) in fields {
    let path = FieldPath.from(
      key.base,
      invalidMessage: "Dictionary keys in updateData: must be NSStrings or FIRFieldPaths."
    )
    data.push_back(CppBridgeUpdateEntry(first: path.cppSegments, second: toBridgeFieldValue(value)))
  }
  return data
}

/// The `mergeFields` of a `setData` call: dot-separated strings or `FieldPath`s.
func toCppFieldPaths(mergeFields: [Any]) -> CppFieldPathVector {
  var paths = CppFieldPathVector()
  for field in mergeFields {
    let path = FieldPath.from(
      field,
      invalidMessage: "All elements in mergeFields: must be NSStrings or FIRFieldPaths."
    )
    paths.push_back(path.cppSegments)
  }
  return paths
}

/// Convert a C++ `BridgeFieldValue` back to a Swift `Any`. Numbers are
/// `NSNumber`s, as upstream, so they cast to any numeric type.
func fromBridgeFieldValue(_ value: CppBridgeFieldValue, firestore: Firestore) -> Any {
  switch value.tag() {
  case .Null:
    return NSNull()
  case .Boolean:
    return value.bool_value()
  case .Integer:
    return NSNumber(value: value.int64_value())
  case .Double:
    return NSNumber(value: value.double_value())
  case .String:
    return Swift.String(value.string_value())
  case .Blob:
    return blobData(value)
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
    return firestore.document(Swift.String(value.string_value()))
  case .Vector:
    let doubles = value.vector_value()
    var arr: [Double] = []
    for i in 0 ..< doubles.size() {
      arr.append(doubles[i])
    }
    return VectorValue(arr)
  case .MinKey:
    return MinKey.shared
  case .MaxKey:
    return MaxKey.shared
  case .Regex:
    return RegexValue(pattern: Swift.String(value.string_value()),
                      options: Swift.String(value.string2_value()))
  case .Int32:
    return Int32Value(Int32(truncatingIfNeeded: value.int64_value()))
  case .Decimal128:
    return Decimal128Value(Swift.String(value.string_value()))
  case .BsonObjectId:
    return BSONObjectId(Swift.String(value.string_value()))
  case .BsonTimestamp:
    return BSONTimestamp(seconds: value.bson_timestamp_seconds(),
                         increment: value.bson_timestamp_increment())
  case .BsonBinaryData:
    return Blob(bsonBinary: blobData(value), subtype: value.bson_subtype())
  default:
    return NSNull()
  }
}

private func blobData(_ value: CppBridgeFieldValue) -> Data {
  let bytes = value.blob_bytes()
  var data = Data(count: bytes.size())
  for i in 0 ..< bytes.size() {
    data[i] = bytes[i]
  }
  return data
}

/// Convert a C++ `BridgeFieldValueMap` to a Swift dictionary.
func fromBridgeFieldValueMap(_ map: CppBridgeFieldValueMap,
                             firestore: Firestore) -> [String: Any] {
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
                                firestore: Firestore) -> [Any] {
  var result: [Any] = []
  for i in 0 ..< vec.size() {
    result.append(fromBridgeFieldValue(vec[i], firestore: firestore))
  }
  return result
}

// MARK: - C Callback Bridging Helpers

// Swift closures cross into C++ as a retained box (`void* context`) plus a C
// trampoline that unboxes it. One-shot callbacks release the box when they
// run; listener boxes are released by C++ (`releaseCallbackBox`) once the
// listener is gone.

final class CallbackBox<Handler>: @unchecked Sendable {
  let handler: Handler
  init(_ handler: Handler) {
    self.handler = handler
  }
}

private typealias DocumentSnapshotHandler = (CppDocumentSnapshotBridge?, Error?) -> Void
private typealias QuerySnapshotHandler = (CppQuerySnapshotBridge?, Error?) -> Void
private typealias ErrorHandler = (Error?) -> Void

func retainedContext<Handler>(_ handler: Handler) -> UnsafeMutableRawPointer {
  Unmanaged.passRetained(CallbackBox(handler)).toOpaque()
}

func releaseCallbackBox(context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<AnyObject>.fromOpaque(context).release()
}

/// Takes ownership of a heap-allocated bridge object that C++ passed to Swift.
func takeBridge<Bridge>(_ pointer: UnsafeMutableRawPointer?, as _: Bridge.Type) -> Bridge? {
  guard let pointer else { return nil }
  let bridge = pointer.assumingMemoryBound(to: Bridge.self)
  defer {
    bridge.deinitialize(count: 1)
    bridge.deallocate()
  }
  return bridge.pointee
}

/// One-shot document snapshot callback.
private func documentSnapshotCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<DocumentSnapshotHandler>>.fromOpaque(context)
    .takeRetainedValue()
  box.handler(takeBridge(snapshot, as: CppDocumentSnapshotBridge.self),
              firestoreError(code: code, message: message))
}

/// One-shot query snapshot callback.
private func querySnapshotCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<QuerySnapshotHandler>>.fromOpaque(context)
    .takeRetainedValue()
  box.handler(takeBridge(snapshot, as: CppQuerySnapshotBridge.self),
              firestoreError(code: code, message: message))
}

/// One-shot callback for error-only results.
private func errorCallbackTrampoline(
  context: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<ErrorHandler>>.fromOpaque(context).takeRetainedValue()
  box.handler(firestoreError(code: code, message: message))
}

/// Document snapshot listener; C++ releases the box.
private func documentSnapshotListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<DocumentSnapshotHandler>>.fromOpaque(context)
    .takeUnretainedValue()
  box.handler(takeBridge(snapshot, as: CppDocumentSnapshotBridge.self),
              firestoreError(code: code, message: message))
}

/// Query snapshot listener; C++ releases the box.
private func querySnapshotListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  snapshot: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<QuerySnapshotHandler>>.fromOpaque(context)
    .takeUnretainedValue()
  box.handler(takeBridge(snapshot, as: CppQuerySnapshotBridge.self),
              firestoreError(code: code, message: message))
}

/// Snapshots-in-sync listener; C++ releases the box.
private func eventListenerTrampoline(
  context: UnsafeMutableRawPointer?,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<() -> Void>>.fromOpaque(context).takeUnretainedValue()
  box.handler()
}

/// The context and callback for a write: nil for fire-and-forget.
private func writeCallback(_ completion: ((Error?) -> Void)?)
  -> (UnsafeMutableRawPointer?, ErrorCallback?) {
  guard let completion else { return (nil, nil) }
  return (retainedContext(completion as ErrorHandler), errorCallbackTrampoline)
}

/// Runs a bridge operation that reports through an `ErrorCallback`.
private func withErrorCallback(
  _ operation: (UnsafeMutableRawPointer, ErrorCallback) -> Void
) async throws {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    let handler: ErrorHandler = { error in
      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
    operation(retainedContext(handler), errorCallbackTrampoline)
  }
}

private func validate(_ document: DocumentReference, belongsTo firestore: Firestore) {
  if document.firestore !== firestore {
    invalidArgument("Provided document reference is from a different Firestore instance.")
  }
}

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
    // As upstream, the token is used even when getting it failed: it's then the placeholder.
    let result = await source.appCheck?.getToken(forcingRefresh: forceRefresh)
    firebase.firestore.swift_bridge.CompleteAppCheckTokenRequest(
      pending.pointer, std.string(result?.token ?? ""),
      std.string(result?.error?.localizedDescription ?? "")
    )
  }
}

private func releaseCredentialsSource(context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<CredentialsSource>.fromOpaque(context).release()
}

// MARK: - Firestore

/// Firestore's state for an app: its instances by database ID, as upstream's
/// `FSTFirestoreComponent`.
final class FirestoreComponent: FirebaseAppComponent {
  let instances = Mutex<[String: Firestore]>([:])

  init() {}

  func appWillBeDeleted(_ app: FirebaseApp) async {
    let firestores = instances.withLock { instances in
      defer { instances.removeAll() }
      return Array(instances.values)
    }
    for firestore in firestores {
      try? await firestore.terminate()
    }
  }
}

/// A Firestore database.
public final class Firestore: @unchecked Sendable {
  var cppBridge: CppFirestoreBridge

  /// The app this database belongs to.
  public let app: FirebaseApp

  /// Observes Auth's internal state notification to keep the C++ credentials
  /// provider's current user up to date.
  private var authObserver: (any NSObjectProtocol)?

  /// Observes App Check's token notification, as upstream's App Check credentials provider does.
  private var appCheckObserver: (any NSObjectProtocol)?

  private let _settings = Mutex(FirestoreSettings())

  private let _indexManager = Mutex<PersistentCacheIndexManager?>(nil)

  deinit {
    if let authObserver {
      NotificationCenter.default.removeObserver(authObserver)
    }
    if let appCheckObserver {
      NotificationCenter.default.removeObserver(appCheckObserver)
    }
  }

  /// The app's component, which holds this instance until it's terminated.
  private let component: FirestoreComponent

  /// The database ID, this instance's key in `component`.
  private let databaseID: String

  private init(app: FirebaseApp, cppBridge: CppFirestoreBridge,
               component: FirestoreComponent, databaseID: String) {
    self.app = app
    self.cppBridge = cppBridge
    self.component = component
    self.databaseID = databaseID
  }

  private static var defaultApp: FirebaseApp {
    guard let app = FirebaseApp.app() else {
      fatalError(
        "FirebaseApp has not been configured. Call FirebaseApp.configure() before using Firestore."
      )
    }
    return app
  }

  /// Returns the default database of the default `FirebaseApp`.
  public static func firestore() -> Firestore {
    firestore(app: defaultApp)
  }

  /// Returns the named database of the default `FirebaseApp`.
  public static func firestore(database: String) -> Firestore {
    firestore(app: defaultApp, database: database)
  }

  /// Returns a database of `app`.
  public static func firestore(app: FirebaseApp, database: String = "(default)") -> Firestore {
    let component = app.component(FirestoreComponent.self)
    return component.instances.withLock { instances in
      if let existing = instances[database] {
        return existing
      }
      let projectID = app.options.projectID ?? ""
      // Auth may not exist yet (it's created by the first `Auth.auth(app:)`), so tokens and
      // user changes come from whichever Auth the app has.
      let auth = app.lazyAuth
      let appCheck = app.appCheck
      let source = CredentialsSource(auth: auth, appCheck: appCheck)
      let authContext = Unmanaged.passRetained(source).toOpaque()
      let appCheckContext = appCheck.map { _ in Unmanaged.passRetained(source).toOpaque() }
      let appCheckCallback: TokenRequestCallback? = appCheck == nil ? nil : requestAppCheckToken
      let bridge = CppFirestoreBridge.Create(
        std.string(projectID),
        std.string(database),
        std.string(app.name),
        authContext,
        requestAuthToken,
        std.string(auth.getUserID() ?? ""),
        appCheckContext,
        appCheckCallback,
        releaseCredentialsSource
      )
      let instance = Firestore(app: app, cppBridge: bridge, component: component,
                               databaseID: database)
      // swift-corelibs-foundation never matches an `object:` filter that is a
      // pure Swift class, so filter by app in the block instead.
      instance.authObserver = NotificationCenter.default.addObserver(
        forName: .FIRAuthStateDidChangeInternalNotification,
        object: nil,
        queue: nil
      ) { [weak instance, weak app] notification in
        let userInfo = notification.userInfo
        guard let app,
              userInfo?[FIRAuthStateDidChangeInternalNotificationAppKey] as? FirebaseApp === app
        else { return }
        let uid = userInfo?[FIRAuthStateDidChangeInternalNotificationUIDKey] as? String
        instance?.cppBridge.SetAuthUser(std.string(uid ?? ""))
      }
      // The user may have changed between reading the initial UID and
      // registering the observer.
      bridge.SetAuthUser(std.string(auth.getUserID() ?? ""))
      if let appCheck {
        let appName = app.name
        let tokenKey = appCheck.notificationTokenKey
        let appNameKey = appCheck.notificationAppNameKey
        instance.appCheckObserver = NotificationCenter.default.addObserver(
          forName: Notification.Name(appCheck.tokenDidChangeNotificationName),
          object: nil,
          queue: nil
        ) { [weak instance] notification in
          // Only notify for this app, as upstream.
          let userInfo = notification.userInfo
          guard userInfo?[appNameKey] as? String == appName,
                let token = userInfo?[tokenKey] as? String else { return }
          instance?.cppBridge.SetAppCheckToken(std.string(token))
        }
      }
      instances[database] = instance
      return instance
    }
  }

  public func collection(_ collectionPath: String) -> CollectionReference {
    CollectionReference(cppBridge: cppBridge.GetCollection(std.string(collectionPath)),
                        firestore: self)
  }

  public func document(_ documentPath: String) -> DocumentReference {
    DocumentReference(cppBridge: cppBridge.GetDocument(std.string(documentPath)), firestore: self)
  }

  public func collectionGroup(_ collectionID: String) -> Query {
    Query(cppBridge: cppBridge.GetCollectionGroup(std.string(collectionID)), firestore: self)
  }

  /// Connects to the emulated Firestore at `host:port` instead of the real
  /// backend. Call it before using this instance. As upstream, this only sets
  /// the host; the emulator doesn't use TLS, so also set
  /// `settings.isSSLEnabled = false`.
  public func useEmulator(withHost host: String, port: Int) {
    if host.isEmpty {
      invalidArgument("Host cannot be nil or empty.")
    }
    let newSettings = settings
    newSettings.host = "\(host):\(port)"
    settings = newSettings
  }

  /// The settings, as a copy: change it and assign it back. Settings can
  /// only change before the instance is first used.
  public var settings: FirestoreSettings {
    get { _settings.withLock { $0.copy() } }
    set {
      let newSettings = newValue.copy()
      let changed = _settings.withLock { settings in
        guard settings != newSettings else { return false }
        settings = newSettings
        return true
      }
      if changed {
        // The bridge shares its core instance between copies.
        var bridge = cppBridge
        newSettings.apply(to: &bridge)
      }
    }
  }

  /// The index manager of the cache, or nil if the cache isn't persistent.
  /// Like other operations, this starts the instance, so settings can't
  /// change afterwards.
  public var persistentCacheIndexManager: PersistentCacheIndexManager? {
    _indexManager.withLock { manager in
      if manager == nil {
        var cppManager = CppPersistentCacheIndexManagerBridge()
        if cppBridge.GetPersistentCacheIndexManager(&cppManager) {
          manager = PersistentCacheIndexManager(cppBridge: cppManager)
        }
      }
      return manager
    }
  }

  /// Stops this instance. As upstream, `Firestore.firestore(app:database:)`
  /// returns a new instance afterwards.
  public func terminate() async throws {
    component.instances.withLock { instances in
      if instances[databaseID] === self {
        instances[databaseID] = nil
      }
    }
    try await withErrorCallback { cppBridge.Terminate($0, $1) }
  }

  public func clearPersistence() async throws {
    try await withErrorCallback { cppBridge.ClearPersistence($0, $1) }
  }

  public func waitForPendingWrites() async throws {
    try await withErrorCallback { cppBridge.WaitForPendingWrites($0, $1) }
  }

  public func enableNetwork() async throws {
    try await withErrorCallback { cppBridge.EnableNetwork($0, $1) }
  }

  public func disableNetwork() async throws {
    try await withErrorCallback { cppBridge.DisableNetwork($0, $1) }
  }

  /// Calls `listener` whenever all active snapshot listeners are in sync with
  /// each other, i.e. after a change has been delivered to all of them.
  public func addSnapshotsInSyncListener(_ listener: @escaping () -> Void)
    -> any ListenerRegistration {
    let registration = cppBridge.AddSnapshotsInSyncListener(
      retainedContext(listener), releaseCallbackBox, eventListenerTrampoline
    )
    return BridgeListenerRegistration(cppBridge: registration)
  }

  public func batch() -> WriteBatch {
    WriteBatch(cppBridge: cppBridge.GetBatch(), firestore: self)
  }

  #if canImport(Darwin)
    /// Upstream's form, kept for source compatibility on Apple platforms. Setting
    /// the error pointer aborts the transaction with that error.
    public func runTransaction(_ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?,
                               completion: @escaping (Any?, Error?) -> Void) {
      runTransaction(with: nil, block: updateBlock, completion: completion)
    }

    /// Like `runTransaction(_:completion:)`, with options such as the number of
    /// attempts.
    public func runTransaction(with options: TransactionOptions?,
                               block updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?,
                               completion: @escaping (Any?, Error?) -> Void) {
      runTransaction(with: options, block: { (transaction: Transaction) throws -> Any? in
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
    runTransaction(with: nil, block: updateBlock, completion: completion)
  }

  /// Like `runTransaction(_:completion:)`, with options such as the number of
  /// attempts.
  public func runTransaction(with options: TransactionOptions?,
                             block updateBlock: @escaping (Transaction) throws -> Any?,
                             completion: @escaping (Any?, Error?) -> Void) {
    // Holds the update block and its result for the C callbacks.
    final class TransactionContext {
      let firestore: Firestore
      let updateBlock: (Transaction) throws -> Any?
      let completion: (Any?, Error?) -> Void
      var result: Any?
      /// The error thrown by the last attempt of `updateBlock`, if any.
      var updateError: Error?

      init(firestore: Firestore,
           updateBlock: @escaping (Transaction) throws -> Any?,
           completion: @escaping (Any?, Error?) -> Void) {
        self.firestore = firestore
        self.updateBlock = updateBlock
        self.completion = completion
      }
    }

    let ctx = TransactionContext(firestore: self, updateBlock: updateBlock,
                                 completion: completion)
    let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

    // Called by C++ for each attempt, off the Firestore worker queue.
    let updateCB:
      @convention(c) (
        UnsafeMutableRawPointer?,     // context
        UnsafeMutableRawPointer?,     // transaction_ptr
        ErrorCallback?,               // completion callback
        UnsafeMutableRawPointer?      // completion context
      ) -> Void = { context, transactionPtr, completionCB, completionCtx in
      guard let context, let cppTransaction = takeBridge(transactionPtr,
                                                          as: CppTransactionBridge.self)
      else { return }
      let txCtx = Unmanaged<TransactionContext>.fromOpaque(context).takeUnretainedValue()
      let transaction = Transaction(cppBridge: cppTransaction, firestore: txCtx.firestore)

      do {
        txCtx.result = try txCtx.updateBlock(transaction)
        txCtx.updateError = nil
        completionCB?(completionCtx, 0, "")
      } catch {
        txCtx.updateError = error
        // Any non-zero code aborts without retrying; the caller gets `error`.
        let nsError = error as NSError
        let code = nsError.domain == FirestoreErrorDomain && nsError.code != 0
          ? Int32(nsError.code) : Int32(FirestoreErrorCode.Code.unknown.rawValue)
        error.localizedDescription.withCString { completionCB?(completionCtx, code, $0) }
      }
    }

    // Called by C++ once, with the outcome.
    let resultCB:
      @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void = {
        context, code, message in
        guard let context else { return }
        let txCtx = Unmanaged<TransactionContext>.fromOpaque(context).takeRetainedValue()
        if let error = firestoreError(code: code, message: message) {
          // Report the caller's own error rather than its string form.
          txCtx.completion(nil, txCtx.updateError ?? error)
        } else {
          txCtx.completion(txCtx.result, nil)
        }
      }

    cppBridge.RunTransaction(ctxPtr, updateCB, ctxPtr, resultCB,
                             Int32(options?.maxAttempts ?? TransactionOptions.defaultMaxAttempts))
  }
}

/// Options for `Firestore.runTransaction(with:block:completion:)`.
public final class TransactionOptions: Sendable {
  static let defaultMaxAttempts = 5

  private let _maxAttempts = Mutex(TransactionOptions.defaultMaxAttempts)

  public init() {}

  /// How many times to run the update block before failing. Default: 5.
  public var maxAttempts: Int {
    get { _maxAttempts.withLock { $0 } }
    set {
      if newValue <= 0 || newValue > Int(Int32.max) {
        invalidArgument("Invalid maxAttempts: \(newValue)")
      }
      _maxAttempts.withLock { $0 = newValue }
    }
  }
}

// MARK: - References

/// A reference to a Firestore document.
public final class DocumentReference: Hashable, @unchecked Sendable {
  let cppBridge: CppDocumentReferenceBridge

  /// The database this document belongs to.
  public let firestore: Firestore

  public static func == (lhs: DocumentReference, rhs: DocumentReference) -> Bool {
    lhs.cppBridge.IsEqual(rhs.cppBridge)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cppBridge.Hash())
  }

  init(cppBridge: CppDocumentReferenceBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  public var path: String {
    String(cppBridge.path())
  }

  public var documentID: String {
    String(cppBridge.document_id())
  }

  public var parent: CollectionReference {
    CollectionReference(cppBridge: cppBridge.parent(), firestore: firestore)
  }

  /// A subcollection of this document. `collectionPath` is relative to the
  /// document, e.g. `"messages"`.
  public func collection(_ collectionPath: String) -> CollectionReference {
    CollectionReference(cppBridge: cppBridge.Collection(std.string(collectionPath)),
                        firestore: firestore)
  }

  private func setData(_ documentData: [String: Any], option: CppSetOption,
                       mergeFields: CppFieldPathVector, completion: ((Error?) -> Void)?) {
    var bridge = cppBridge
    let (context, callback) = writeCallback(completion)
    bridge.SetData(toBridgeFieldValueMap(documentData), option, mergeFields, context, callback)
  }

  /// Overwrites the document, creating it if it doesn't exist.
  public func setData(_ documentData: [String: Any], completion: ((Error?) -> Void)? = nil) {
    setData(documentData, option: .Overwrite, mergeFields: CppFieldPathVector(),
            completion: completion)
  }

  /// Writes the document; with `merge`, fields not in `documentData` are kept.
  public func setData(_ documentData: [String: Any], merge: Bool,
                      completion: ((Error?) -> Void)? = nil) {
    setData(documentData, option: merge ? .Merge : .Overwrite,
            mergeFields: CppFieldPathVector(), completion: completion)
  }

  /// Writes only `mergeFields` (`String`s or `FieldPath`s) from `documentData`.
  public func setData(_ documentData: [String: Any], mergeFields: [Any],
                      completion: ((Error?) -> Void)? = nil) {
    setData(documentData, option: .MergeFields,
            mergeFields: toCppFieldPaths(mergeFields: mergeFields), completion: completion)
  }

  /// Updates fields of an existing document. Keys are dot-separated `String`s
  /// or `FieldPath`s.
  public func updateData(_ fields: [AnyHashable: Any], completion: ((Error?) -> Void)? = nil) {
    var bridge = cppBridge
    let (context, callback) = writeCallback(completion)
    bridge.UpdateData(toBridgeUpdateData(fields), context, callback)
  }

  public func delete(completion: ((Error?) -> Void)? = nil) {
    let (context, callback) = writeCallback(completion)
    cppBridge.DeleteDocument(context, callback)
  }

  public func getDocument(source: FirestoreSource = .default,
                          completion: @escaping (DocumentSnapshot?, Error?) -> Void) {
    let firestore = firestore
    let handler: DocumentSnapshotHandler = { snapshot, error in
      completion(snapshot.map { DocumentSnapshot(cppBridge: $0, firestore: firestore) }, error)
    }
    cppBridge.GetDocument(source.cppSource, retainedContext(handler),
                          documentSnapshotCallbackTrampoline)
  }

  public func getDocument(source: FirestoreSource = .default) async throws -> DocumentSnapshot {
    try await withCheckedThrowingContinuation { continuation in
      getDocument(source: source) { snapshot, error in
        if let snapshot {
          continuation.resume(returning: snapshot)
        } else {
          continuation.resume(throwing: error ?? FirestoreErrorCode(.unknown))
        }
      }
    }
  }

  public func addSnapshotListener(_ listener: @escaping (DocumentSnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    addSnapshotListener(options: SnapshotListenOptions(), listener: listener)
  }

  public func addSnapshotListener(includeMetadataChanges: Bool,
                                  listener: @escaping (DocumentSnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    addSnapshotListener(
      options: SnapshotListenOptions().withIncludeMetadataChanges(includeMetadataChanges),
      listener: listener
    )
  }

  public func addSnapshotListener(options: SnapshotListenOptions,
                                  listener: @escaping (DocumentSnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    let firestore = firestore
    let handler: DocumentSnapshotHandler = { snapshot, error in
      listener(snapshot.map { DocumentSnapshot(cppBridge: $0, firestore: firestore) }, error)
    }
    let registration = cppBridge.AddSnapshotListener(
      options.includeMetadataChanges, Int32(options.source.rawValue),
      retainedContext(handler), releaseCallbackBox, documentSnapshotListenerTrampoline
    )
    return BridgeListenerRegistration(cppBridge: registration)
  }
}

/// A reference to a Firestore collection.
public final class CollectionReference: Query, @unchecked Sendable {
  let collectionBridge: CppCollectionReferenceBridge

  init(cppBridge: CppCollectionReferenceBridge, firestore: Firestore) {
    collectionBridge = cppBridge
    // Swift C++ interop doesn't expose C++ base class members directly.
    super.init(cppBridge: cppBridge.as_query(), firestore: firestore)
  }

  public var collectionID: String {
    String(collectionBridge.collection_id())
  }

  /// The collection's path, e.g. `"users/alice/posts"`.
  public var path: String {
    String(collectionBridge.path())
  }

  /// The document containing this collection, or nil for a root collection.
  public var parent: DocumentReference? {
    var parent = CppDocumentReferenceBridge()
    guard collectionBridge.GetParent(&parent) else { return nil }
    return DocumentReference(cppBridge: parent, firestore: firestore)
  }

  /// A reference to a new document with an automatically generated ID.
  public func document() -> DocumentReference {
    DocumentReference(cppBridge: collectionBridge.Document(), firestore: firestore)
  }

  public func document(_ path: String) -> DocumentReference {
    DocumentReference(cppBridge: collectionBridge.Document(std.string(path)), firestore: firestore)
  }

  @discardableResult
  public func addDocument(data: [String: Any],
                          completion: ((Error?) -> Void)? = nil) -> DocumentReference {
    let docRef = document()
    docRef.setData(data, completion: completion)
    return docRef
  }
}

// MARK: - Queries

/// A Firestore query.
public class Query: Hashable, @unchecked Sendable {
  let cppQueryBridge: CppQueryBridge

  /// The database this query belongs to.
  public let firestore: Firestore

  init(cppBridge: CppQueryBridge, firestore: Firestore) {
    cppQueryBridge = cppBridge
    self.firestore = firestore
  }

  public static func == (lhs: Query, rhs: Query) -> Bool {
    lhs.cppQueryBridge.IsEqual(rhs.cppQueryBridge)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cppQueryBridge.Hash())
  }

  private func query(_ cppBridge: CppQueryBridge) -> Query {
    Query(cppBridge: cppBridge, firestore: firestore)
  }

  public func getDocuments(source: FirestoreSource = .default,
                           completion: @escaping (QuerySnapshot?, Error?) -> Void) {
    let handler: QuerySnapshotHandler = { [self] snapshot, error in
      completion(snapshot.map { QuerySnapshot(cppBridge: $0, query: self) }, error)
    }
    cppQueryBridge.GetDocuments(source.cppSource, retainedContext(handler),
                                querySnapshotCallbackTrampoline)
  }

  public func getDocuments(source: FirestoreSource = .default) async throws -> QuerySnapshot {
    try await withCheckedThrowingContinuation { continuation in
      getDocuments(source: source) { snapshot, error in
        if let snapshot {
          continuation.resume(returning: snapshot)
        } else {
          continuation.resume(throwing: error ?? FirestoreErrorCode(.unknown))
        }
      }
    }
  }

  public func addSnapshotListener(_ listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    addSnapshotListener(options: SnapshotListenOptions(), listener: listener)
  }

  public func addSnapshotListener(includeMetadataChanges: Bool,
                                  listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    addSnapshotListener(
      options: SnapshotListenOptions().withIncludeMetadataChanges(includeMetadataChanges),
      listener: listener
    )
  }

  public func addSnapshotListener(options: SnapshotListenOptions,
                                  listener: @escaping (QuerySnapshot?, Error?) -> Void)
    -> any ListenerRegistration {
    let handler: QuerySnapshotHandler = { [self] snapshot, error in
      listener(snapshot.map { QuerySnapshot(cppBridge: $0, query: self) }, error)
    }
    let registration = cppQueryBridge.AddSnapshotListener(
      options.includeMetadataChanges, Int32(options.source.rawValue),
      retainedContext(handler), releaseCallbackBox, querySnapshotListenerTrampoline
    )
    return BridgeListenerRegistration(cppBridge: registration)
  }

  // MARK: Filters

  /// A query with `filter` added, which may combine others with
  /// `Filter.andFilter(_:)` and `Filter.orFilter(_:)`.
  public func whereFilter(_ filter: Filter) -> Query {
    query(cppQueryBridge.Where(filter.cppBridge))
  }

  public func whereField(_ field: String, isEqualTo value: Any) -> Query {
    whereFilter(.whereField(field, isEqualTo: value))
  }

  public func whereField(_ path: FieldPath, isEqualTo value: Any) -> Query {
    whereFilter(.whereField(path, isEqualTo: value))
  }

  public func whereField(_ field: String, isNotEqualTo value: Any) -> Query {
    whereFilter(.whereField(field, isNotEqualTo: value))
  }

  public func whereField(_ path: FieldPath, isNotEqualTo value: Any) -> Query {
    whereFilter(.whereField(path, isNotEqualTo: value))
  }

  public func whereField(_ field: String, isLessThan value: Any) -> Query {
    whereFilter(.whereField(field, isLessThan: value))
  }

  public func whereField(_ path: FieldPath, isLessThan value: Any) -> Query {
    whereFilter(.whereField(path, isLessThan: value))
  }

  public func whereField(_ field: String, isLessThanOrEqualTo value: Any) -> Query {
    whereFilter(.whereField(field, isLessThanOrEqualTo: value))
  }

  public func whereField(_ path: FieldPath, isLessThanOrEqualTo value: Any) -> Query {
    whereFilter(.whereField(path, isLessThanOrEqualTo: value))
  }

  public func whereField(_ field: String, isGreaterThan value: Any) -> Query {
    whereFilter(.whereField(field, isGreaterThan: value))
  }

  public func whereField(_ path: FieldPath, isGreaterThan value: Any) -> Query {
    whereFilter(.whereField(path, isGreaterThan: value))
  }

  public func whereField(_ field: String, isGreaterThanOrEqualTo value: Any) -> Query {
    whereFilter(.whereField(field, isGreaterOrEqualTo: value))
  }

  public func whereField(_ path: FieldPath, isGreaterThanOrEqualTo value: Any) -> Query {
    whereFilter(.whereField(path, isGreaterOrEqualTo: value))
  }

  public func whereField(_ field: String, arrayContains value: Any) -> Query {
    whereFilter(.whereField(field, arrayContains: value))
  }

  public func whereField(_ path: FieldPath, arrayContains value: Any) -> Query {
    whereFilter(.whereField(path, arrayContains: value))
  }

  public func whereField(_ field: String, arrayContainsAny values: [Any]) -> Query {
    whereFilter(.whereField(field, arrayContainsAny: values))
  }

  public func whereField(_ path: FieldPath, arrayContainsAny values: [Any]) -> Query {
    whereFilter(.whereField(path, arrayContainsAny: values))
  }

  public func whereField(_ field: String, in values: [Any]) -> Query {
    whereFilter(.whereField(field, in: values))
  }

  public func whereField(_ path: FieldPath, in values: [Any]) -> Query {
    whereFilter(.whereField(path, in: values))
  }

  public func whereField(_ field: String, notIn values: [Any]) -> Query {
    whereFilter(.whereField(field, notIn: values))
  }

  public func whereField(_ path: FieldPath, notIn values: [Any]) -> Query {
    whereFilter(.whereField(path, notIn: values))
  }

  // MARK: Order and limits

  public func order(by field: String, descending: Bool = false) -> Query {
    order(by: FieldPath(dotSeparated: field), descending: descending)
  }

  public func order(by path: FieldPath, descending: Bool = false) -> Query {
    query(cppQueryBridge.OrderBy(path.cppSegments, descending))
  }

  public func limit(to limit: Int) -> Query {
    query(cppQueryBridge.LimitToFirst(Int32(clamping: limit)))
  }

  public func limit(toLast limit: Int) -> Query {
    query(cppQueryBridge.LimitToLast(Int32(clamping: limit)))
  }

  // MARK: Cursors

  private static func cppValues(_ values: [Any]) -> CppBridgeFieldValueVector {
    var vector = CppBridgeFieldValueVector()
    for value in values {
      vector.push_back(toBridgeFieldValue(value))
    }
    return vector
  }

  /// Starts at the document with these values of the order-by fields.
  public func start(at fieldValues: [Any]) -> Query {
    query(cppQueryBridge.StartAt(Self.cppValues(fieldValues), true))
  }

  /// Starts after the document with these values of the order-by fields.
  public func start(after fieldValues: [Any]) -> Query {
    query(cppQueryBridge.StartAt(Self.cppValues(fieldValues), false))
  }

  /// Ends at the document with these values of the order-by fields.
  public func end(at fieldValues: [Any]) -> Query {
    query(cppQueryBridge.EndAt(Self.cppValues(fieldValues), true))
  }

  /// Ends before the document with these values of the order-by fields.
  public func end(before fieldValues: [Any]) -> Query {
    query(cppQueryBridge.EndAt(Self.cppValues(fieldValues), false))
  }

  public func start(atDocument document: DocumentSnapshot) -> Query {
    query(cppQueryBridge.StartAtDocument(document.cppBridge, true))
  }

  public func start(afterDocument document: DocumentSnapshot) -> Query {
    query(cppQueryBridge.StartAtDocument(document.cppBridge, false))
  }

  public func end(atDocument document: DocumentSnapshot) -> Query {
    query(cppQueryBridge.EndAtDocument(document.cppBridge, true))
  }

  public func end(beforeDocument document: DocumentSnapshot) -> Query {
    query(cppQueryBridge.EndAtDocument(document.cppBridge, false))
  }
}

// MARK: - Snapshots

/// A snapshot of a document, which may not exist.
public class DocumentSnapshot: Hashable, @unchecked Sendable {
  let cppBridge: CppDocumentSnapshotBridge
  let firestore: Firestore

  required init(cppBridge: CppDocumentSnapshotBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  public static func == (lhs: DocumentSnapshot, rhs: DocumentSnapshot) -> Bool {
    lhs.cppBridge.IsEqual(rhs.cppBridge)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cppBridge.Hash())
  }

  public var exists: Bool {
    cppBridge.exists()
  }

  public var reference: DocumentReference {
    DocumentReference(cppBridge: cppBridge.create_reference(), firestore: firestore)
  }

  public var documentID: String {
    String(cppBridge.document_id())
  }

  public var metadata: SnapshotMetadata {
    SnapshotMetadata(cppMetadata: cppBridge.metadata())
  }

  /// The document's fields, or nil if it doesn't exist. Server timestamps that
  /// haven't been set yet are null.
  public func data() -> [String: Any]? {
    data(with: .none)
  }

  public func data(with serverTimestampBehavior: ServerTimestampBehavior) -> [String: Any]? {
    guard exists else { return nil }
    return fromBridgeFieldValueMap(
      cppBridge.data(Int32(serverTimestampBehavior.rawValue)), firestore: firestore
    )
  }

  /// The value of `field`, a dot-separated `String` or a `FieldPath`, or nil
  /// if the document or field doesn't exist.
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

  public subscript(key: Any) -> Any? {
    self.get(key)
  }
}

/// A snapshot of a document in a query result, which always exists.
public final class QueryDocumentSnapshot: DocumentSnapshot, @unchecked Sendable {
  override public func data() -> [String: Any] {
    data(with: .none)
  }

  override public func data(with serverTimestampBehavior: ServerTimestampBehavior)
    -> [String: Any] {
    fromBridgeFieldValueMap(
      cppBridge.data(Int32(serverTimestampBehavior.rawValue)), firestore: firestore
    )
  }
}

/// A snapshot of a query result.
public final class QuerySnapshot: @unchecked Sendable {
  private let cppBridge: CppQuerySnapshotBridge

  /// The query this is a result of.
  public let query: Query

  init(cppBridge: CppQuerySnapshotBridge, query: Query) {
    self.cppBridge = cppBridge
    self.query = query
  }

  public var documents: [QueryDocumentSnapshot] {
    let cppDocs = cppBridge.documents()
    var result: [QueryDocumentSnapshot] = []
    for i in 0 ..< cppDocs.size() {
      result.append(QueryDocumentSnapshot(cppBridge: cppDocs[i], firestore: query.firestore))
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
      result.append(DocumentChange(cppBridge: cppChanges[i], firestore: query.firestore))
    }
    return result
  }

  public var metadata: SnapshotMetadata {
    SnapshotMetadata(cppMetadata: cppBridge.metadata())
  }
}

/// A change to a document in a query result.
public final class DocumentChange: @unchecked Sendable {
  private let cppBridge: CppDocumentChangeBridge
  private let firestore: Firestore

  init(cppBridge: CppDocumentChangeBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  public var type: DocumentChangeType {
    switch cppBridge.type() {
    case .Added: return .added
    case .Modified: return .modified
    case .Removed: return .removed
    default: return .added
    }
  }

  public var document: QueryDocumentSnapshot {
    QueryDocumentSnapshot(cppBridge: cppBridge.document(), firestore: firestore)
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

// MARK: - Writes

/// A batch of writes, applied atomically by `commit()`.
public final class WriteBatch: @unchecked Sendable {
  private var cppBridge: CppWriteBatchBridge
  private let firestore: Firestore

  init(cppBridge: CppWriteBatchBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference) -> WriteBatch {
    setData(data, forDocument: doc, merge: false)
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> WriteBatch {
    validate(doc, belongsTo: firestore)
    cppBridge.SetData(doc.cppBridge, toBridgeFieldValueMap(data), merge ? .Merge : .Overwrite,
                      CppFieldPathVector())
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> WriteBatch {
    validate(doc, belongsTo: firestore)
    cppBridge.SetData(doc.cppBridge, toBridgeFieldValueMap(data), .MergeFields,
                      toCppFieldPaths(mergeFields: mergeFields))
    return self
  }

  @discardableResult
  public func updateData(_ fields: [AnyHashable: Any],
                         forDocument doc: DocumentReference) -> WriteBatch {
    validate(doc, belongsTo: firestore)
    cppBridge.UpdateData(doc.cppBridge, toBridgeUpdateData(fields))
    return self
  }

  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> WriteBatch {
    validate(doc, belongsTo: firestore)
    cppBridge.DeleteData(doc.cppBridge)
    return self
  }

  public func commit(completion: ((Error?) -> Void)? = nil) {
    let (context, callback) = writeCallback(completion)
    cppBridge.Commit(context, callback)
  }

  public func commit() async throws {
    try await withErrorCallback { cppBridge.Commit($0, $1) }
  }
}

/// A transaction, passed to the update block of `Firestore.runTransaction`.
/// All reads must come before any writes.
public final class Transaction: @unchecked Sendable {
  private var cppBridge: CppTransactionBridge
  private let firestore: Firestore

  init(cppBridge: CppTransactionBridge, firestore: Firestore) {
    self.cppBridge = cppBridge
    self.firestore = firestore
  }

  @discardableResult
  public func setData(_ data: [String: Any],
                      forDocument doc: DocumentReference) -> Transaction {
    setData(data, forDocument: doc, merge: false)
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      merge: Bool) -> Transaction {
    validate(doc, belongsTo: firestore)
    cppBridge.SetData(doc.cppBridge, toBridgeFieldValueMap(data), merge ? .Merge : .Overwrite,
                      CppFieldPathVector())
    return self
  }

  @discardableResult
  public func setData(_ data: [String: Any], forDocument doc: DocumentReference,
                      mergeFields: [Any]) -> Transaction {
    validate(doc, belongsTo: firestore)
    cppBridge.SetData(doc.cppBridge, toBridgeFieldValueMap(data), .MergeFields,
                      toCppFieldPaths(mergeFields: mergeFields))
    return self
  }

  @discardableResult
  public func updateData(_ fields: [AnyHashable: Any],
                         forDocument doc: DocumentReference) -> Transaction {
    validate(doc, belongsTo: firestore)
    cppBridge.UpdateData(doc.cppBridge, toBridgeUpdateData(fields))
    return self
  }

  @discardableResult
  public func deleteDocument(_ doc: DocumentReference) -> Transaction {
    validate(doc, belongsTo: firestore)
    cppBridge.DeleteData(doc.cppBridge)
    return self
  }

  /// Reads a document as part of the transaction. Blocks until it's read.
  public func getDocument(_ doc: DocumentReference) throws -> DocumentSnapshot {
    validate(doc, belongsTo: firestore)
    var code: Int32 = 0
    var message = std.string()
    let snapshot = cppBridge.GetDocument(doc.cppBridge, &code, &message)
    if code != 0 {
      throw FirestoreErrorCode(FirestoreErrorCode.Code(rawValue: Int(code)) ?? .unknown,
                               userInfo: [NSLocalizedDescriptionKey: String(message)])
    }
    return DocumentSnapshot(cppBridge: snapshot, firestore: firestore)
  }
}

/// Sentinel values for field operations.
public final class FieldValue: Hashable, @unchecked Sendable {
  let sentinel: FieldValueSentinel

  private init(_ sentinel: FieldValueSentinel) {
    self.sentinel = sentinel
  }

  /// The API call that created this sentinel, for error messages, as
  /// upstream's `methodName`.
  var methodName: String {
    switch sentinel {
    case .delete_: "FieldValue.delete()"
    case .serverTimestamp: "FieldValue.serverTimestamp()"
    case .arrayUnion: "FieldValue.arrayUnion()"
    case .arrayRemove: "FieldValue.arrayRemove()"
    case .increment: "FieldValue.increment()"
    case .minimum: "FieldValue.minimum()"
    case .maximum: "FieldValue.maximum()"
    }
  }

  /// Matches upstream `isEqual:`: sentinels of the same kind are equal, and
  /// array and numeric transforms also compare their operands.
  public static func == (lhs: FieldValue, rhs: FieldValue) -> Bool {
    switch (lhs.sentinel, rhs.sentinel) {
    case (.delete_, .delete_), (.serverTimestamp, .serverTimestamp):
      return true
    case let (.arrayUnion(a), .arrayUnion(b)), let (.arrayRemove(a), .arrayRemove(b)):
      return NSArray(array: a).isEqual(to: b)
    case let (.increment(a), .increment(b)), let (.minimum(a), .minimum(b)),
         let (.maximum(a), .maximum(b)):
      return (a as? NSNumber) == (b as? NSNumber)
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
    case let .increment(operand):
      hasher.combine(4)
      hasher.combine(operand as? NSNumber)
    case let .minimum(operand):
      hasher.combine(5)
      hasher.combine(operand as? NSNumber)
    case let .maximum(operand):
      hasher.combine(6)
      hasher.combine(operand as? NSNumber)
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
    FieldValue(.increment(n))
  }

  public static func increment(_ n: Double) -> FieldValue {
    FieldValue(.increment(n))
  }

  /// Sets the field to the smaller of its current value and `n`.
  public static func minimum(_ n: Int64) -> FieldValue {
    FieldValue(.minimum(n))
  }

  public static func minimum(_ n: Double) -> FieldValue {
    FieldValue(.minimum(n))
  }

  /// Sets the field to the larger of its current value and `n`.
  public static func maximum(_ n: Int64) -> FieldValue {
    FieldValue(.maximum(n))
  }

  public static func maximum(_ n: Double) -> FieldValue {
    FieldValue(.maximum(n))
  }

  /// Creates a VectorValue from an array of NSNumbers.
  /// This is the ObjC-compatible factory method used by FieldValue+Swift.swift.
  public static func __vector(with array: [NSNumber]) -> VectorValue {
    return VectorValue(array.map { $0.doubleValue })
  }

  /// Convert this sentinel to a C++ BridgeFieldValue.
  func toBridgeFieldValue() -> CppBridgeFieldValue {
    func elements(_ values: [Any]) -> CppBridgeFieldValueVector {
      var vector = CppBridgeFieldValueVector()
      for value in values {
        vector.push_back(FirebaseFirestore.toBridgeFieldValue(value))
      }
      return vector
    }
    switch sentinel {
    case .delete_:
      return CppBridgeFieldValue.Delete()
    case .serverTimestamp:
      return CppBridgeFieldValue.ServerTimestamp()
    case let .arrayUnion(values):
      return CppBridgeFieldValue.ArrayUnion(elements(values))
    case let .arrayRemove(values):
      return CppBridgeFieldValue.ArrayRemove(elements(values))
    case let .increment(operand):
      return CppBridgeFieldValue.Increment(FirebaseFirestore.toBridgeFieldValue(operand))
    case let .minimum(operand):
      return CppBridgeFieldValue.Minimum(FirebaseFirestore.toBridgeFieldValue(operand))
    case let .maximum(operand):
      return CppBridgeFieldValue.Maximum(FirebaseFirestore.toBridgeFieldValue(operand))
    }
  }
}

/// Vector value for vector search.
public final class VectorValue: Hashable, Sendable {
  private let _array: [Double]

  public var array: [Double] { _array }

  /// Equal when the numbers are, as upstream.
  public static func == (lhs: VectorValue, rhs: VectorValue) -> Bool {
    lhs._array == rhs._array
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(_array)
  }

  public init(_ array: [Double]) {
    self._array = array
  }

  public init(__array: [NSNumber]) {
    self._array = __array.map { $0.doubleValue }
  }
}

/// Metadata about a snapshot.
public final class SnapshotMetadata: @unchecked Sendable {
  private let cppMetadata: CppSnapshotMetadata

  init(cppMetadata: CppSnapshotMetadata) {
    self.cppMetadata = cppMetadata
  }

  public var isFromCache: Bool {
    cppMetadata.from_cache()
  }

  public var hasPendingWrites: Bool {
    cppMetadata.pending_writes()
  }
}

/// A registration for a snapshot listener.
public protocol ListenerRegistration: Sendable {
  /// Stops the listener. Until then it stays active, even if the registration
  /// itself is released, as upstream.
  func remove()
}

/// Listener registration backed by the C++ bridge. C++ owns the listener's
/// callback and releases it once the listener is gone.
final class BridgeListenerRegistration: ListenerRegistration {
  private let cppBridge: Mutex<CppListenerRegistrationBridge?>

  init(cppBridge: CppListenerRegistrationBridge) {
    self.cppBridge = Mutex(cppBridge)
  }

  func remove() {
    guard var bridge = cppBridge.withLock({ $0.take() }) else { return }
    bridge.Remove()
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
  /// The server and the local cache, as other listeners.
  case `default` = 0
  /// Only the local cache: no network traffic, and no server-side results.
  case cache = 1
}

/// Options for `addSnapshotListener(options:listener:)`.
public final class SnapshotListenOptions: Sendable {
  public let includeMetadataChanges: Bool
  public let source: ListenSource

  public convenience init() {
    self.init(includeMetadataChanges: false, source: .default)
  }

  private init(includeMetadataChanges: Bool, source: ListenSource) {
    self.includeMetadataChanges = includeMetadataChanges
    self.source = source
  }

  /// A copy that also delivers snapshots for metadata-only changes.
  public func withIncludeMetadataChanges(_ includeMetadataChanges: Bool) -> SnapshotListenOptions {
    SnapshotListenOptions(includeMetadataChanges: includeMetadataChanges, source: source)
  }

  /// A copy that listens to `source`.
  public func withSource(_ source: ListenSource) -> SnapshotListenOptions {
    SnapshotListenOptions(includeMetadataChanges: includeMetadataChanges, source: source)
  }
}

/// An immutable object representing a geographical point in Firestore. The point is represented
/// as a latitude/longitude pair.
///
/// Latitude values are in the range of [-90, 90].
/// Longitude values are in the range of [-180, 180].
///
/// A value type here; upstream's `GeoPoint` is a class. Equality compares the coordinates with
/// `==`, so 0 and -0 are equal, where upstream compares their bits.
public struct GeoPoint: Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  /// Creates a point. Stops the process if a coordinate is out of range or not finite, as
  /// upstream throws an exception.
  public init(latitude: Double, longitude: Double) {
    precondition(Self.isValidLatitude(latitude),
                 "GeoPoint requires a latitude value in the range of [-90, 90], but was \(latitude)")
    precondition(Self.isValidLongitude(longitude),
                 "GeoPoint requires a longitude value in the range of [-180, 180], but was \(longitude)")
    self.latitude = latitude
    self.longitude = longitude
  }

  /// Whether `latitude` is in [-90, 90]; NaN and infinities aren't.
  static func isValidLatitude(_ latitude: Double) -> Bool {
    (-90 ... 90).contains(latitude)
  }

  /// Whether `longitude` is in [-180, 180]; NaN and infinities aren't.
  static func isValidLongitude(_ longitude: Double) -> Bool {
    (-180 ... 180).contains(longitude)
  }
}
