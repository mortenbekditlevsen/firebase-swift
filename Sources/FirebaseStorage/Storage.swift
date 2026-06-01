// Copyright 2022 Google LLC
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
import Synchronization

import FirebaseCore

/// Firebase Storage is a service that supports uploading and downloading binary objects,
/// such as images, videos, and other files to Google Cloud Storage. Instances of `Storage`
/// are not thread-safe, but can be accessed from any thread.
///
/// If you call `Storage.storage()`, the instance will initialize with the default `FirebaseApp`,
/// `FirebaseApp.app()`, and the storage location will come from the provided
/// `GoogleService-Info.plist`.
///
/// If you provide a custom instance of `FirebaseApp`,
/// the storage location will be specified via the `FirebaseOptions.storageBucket` property.
public final class Storage: Sendable {
  // MARK: - Mutable State

  private struct MutableState: Sendable {
    var maxUploadRetryTime: TimeInterval = 600.0
    var maxUploadRetryInterval: TimeInterval = computeRetryInterval(fromRetryTime: 600.0)
    var maxDownloadRetryTime: TimeInterval = 600.0
    var maxDownloadRetryInterval: TimeInterval = computeRetryInterval(fromRetryTime: 600.0)
    var maxOperationRetryTime: TimeInterval = 120.0
    var maxOperationRetryInterval: TimeInterval = computeRetryInterval(fromRetryTime: 120.0)
    var uploadChunkSizeBytes: Int64 = .max
    var host: String = "firebasestorage.googleapis.com"
    var scheme: String = "https"
    var port: Int = 443
    var usesEmulator: Bool = false
    var configured: Bool = false
  }

  private let state: Mutex<MutableState>

  // MARK: - Public APIs

  /// The default `Storage` instance.
  /// - Returns: An instance of `Storage`, configured with the default `FirebaseApp`.
  public static func storage() -> Storage {
    return storage(app: FirebaseApp.app()!)
  }

  /// A method used to create `Storage` instances initialized with a custom storage bucket URL.
  ///
  /// Any `StorageReferences` generated from this instance of `Storage` will reference files
  /// and directories within the specified bucket.
  /// - Parameter url: The `gs://` URL to your Firebase Storage bucket.
  /// - Returns: A `Storage` instance, configured with the custom storage bucket.
  public static func storage(url: String) -> Storage {
    return storage(app: FirebaseApp.app()!, url: url)
  }

  /// Creates an instance of `Storage`, configured with a custom `FirebaseApp`. `StorageReference`s
  /// generated from a resulting instance will reference files in the Firebase project
  /// associated with custom `FirebaseApp`.
  /// - Parameter app: The custom `FirebaseApp` used for initialization.
  /// - Returns: A `Storage` instance, configured with the custom `FirebaseApp`.
  public static func storage(app: FirebaseApp) -> Storage {
    return storage(app: app, bucket: Storage.bucket(for: app))
  }

  /// Creates an instance of `Storage`, configured with a custom `FirebaseApp` and a custom storage
  /// bucket URL.
  /// - Parameters:
  ///   - app: The custom `FirebaseApp` used for initialization.
  ///   - url: The `gs://` url to your Firebase Storage bucket.
  /// - Returns: The `Storage` instance, configured with the custom `FirebaseApp` and storage bucket
  /// URL.
  public static func storage(app: FirebaseApp, url: String) -> Storage {
    return storage(app: app, bucket: Storage.bucket(for: app, urlString: url))
  }

  private static func storage(app: FirebaseApp, bucket: String) -> Storage {
    return InstanceCache.shared.storage(app: app, bucket: bucket)
  }

  /// The `FirebaseApp` associated with this Storage instance.
  public let app: FirebaseApp

  /// The maximum time in seconds to retry an upload if a failure occurs.
  /// Defaults to 10 minutes (600 seconds).
  public var maxUploadRetryTime: TimeInterval {
    get { state.withLock { $0.maxUploadRetryTime } }
    set {
      state.withLock {
        $0.maxUploadRetryTime = newValue
        $0.maxUploadRetryInterval = Storage.computeRetryInterval(fromRetryTime: newValue)
      }
    }
  }

  /// The maximum time in seconds to retry a download if a failure occurs.
  /// Defaults to 10 minutes (600 seconds).
  public var maxDownloadRetryTime: TimeInterval {
    get { state.withLock { $0.maxDownloadRetryTime } }
    set {
      state.withLock {
        $0.maxDownloadRetryTime = newValue
        $0.maxDownloadRetryInterval = Storage.computeRetryInterval(fromRetryTime: newValue)
      }
    }
  }

  /// The maximum time in seconds to retry operations other than upload and download if a failure
  /// occurs.
  /// Defaults to 2 minutes (120 seconds).
  public var maxOperationRetryTime: TimeInterval {
    get { state.withLock { $0.maxOperationRetryTime } }
    set {
      state.withLock {
        $0.maxOperationRetryTime = newValue
        $0.maxOperationRetryInterval = Storage.computeRetryInterval(fromRetryTime: newValue)
      }
    }
  }

  /// Specify the maximum upload chunk size. Values less than 256K (262144) will be rounded up to
  /// 256K. Values
  /// above 256K will be rounded down to the nearest 256K multiple. The default is no maximum.
  public var uploadChunkSizeBytes: Int64 {
    get { state.withLock { $0.uploadChunkSizeBytes } }
    set { state.withLock { $0.uploadChunkSizeBytes = newValue } }
  }

  /// Creates a `StorageReference` initialized at the root Firebase Storage location.
  /// - Returns: An instance of `StorageReference` referencing the root of the storage bucket.
  public func reference() -> StorageReference {
    state.withLock { $0.configured = true }
    let path = StoragePath(with: storageBucket)
    return StorageReference(storage: self, path: path)
  }

  /// Creates a StorageReference given a `gs://`, `http://`, or `https://` URL pointing to a
  /// Firebase Storage location.
  ///
  /// For example, you can pass in an `https://` download URL retrieved from
  /// `StorageReference.downloadURL(completion:)` or the `gs://` URL from
  /// `StorageReference.description`.
  /// - Parameter url: A gs:// or https:// URL to initialize the reference with.
  /// - Returns: An instance of StorageReference at the given child path.
  /// - Throws: Throws a fatal error if `url` is not associated with the `FirebaseApp` used to
  /// initialize this Storage instance.
  public func reference(forURL url: String) -> StorageReference {
    state.withLock { $0.configured = true }
    do {
      let path = try StoragePath.path(string: url)

      // If no default bucket exists (empty string), accept anything.
      if storageBucket == "" {
        return StorageReference(storage: self, path: path)
      }
      // If there exists a default bucket, throw if provided a different bucket.
      if path.bucket != storageBucket {
        fatalError("Provided bucket: `\(path.bucket)` does not match the Storage bucket of the current " +
          "instance: `\(storageBucket)`")
      }
      return StorageReference(storage: self, path: path)
    } catch let StoragePathError.storagePathError(message) {
      fatalError(message)
    } catch {
      fatalError("Internal error finding StoragePath: \(error)")
    }
  }

  /// Creates a StorageReference given a `gs://`, `http://`, or `https://` URL pointing to a
  /// Firebase Storage location.
  ///
  /// For example, you can pass in an `https://` download URL retrieved from
  /// `StorageReference.downloadURL(completion:)` or the `gs://` URL from
  /// `StorageReference.description`.
  /// - Parameter url: A gs:// or https:// URL to initialize the reference with.
  /// - Returns: An instance of StorageReference at the given child path.
  /// - Throws: Throws an Error if `url` is not associated with the `FirebaseApp` used to initialize
  ///     this Storage instance.
  public func reference(for url: URL) throws -> StorageReference {
    state.withLock { $0.configured = true }
    var path: StoragePath
    do {
      path = try StoragePath.path(string: url.absoluteString)
    } catch let StoragePathError.storagePathError(message) {
      throw StorageError.pathError(message: message)
    } catch {
      throw StorageError.pathError(message: "Internal error finding StoragePath: \(error)")
    }

    // If no default bucket exists (empty string), accept anything.
    if storageBucket == "" {
      return StorageReference(storage: self, path: path)
    }
    // If there exists a default bucket, throw if provided a different bucket.
    if path.bucket != storageBucket {
      throw StorageError
        .bucketMismatch(message: "Provided bucket: `\(path.bucket)` does not match the Storage " +
          "bucket of the current instance: `\(storageBucket)`")
    }
    return StorageReference(storage: self, path: path)
  }

  /// Creates a `StorageReference` initialized at a location specified by the `path` parameter.
  /// - Parameter path: A relative path from the root of the storage bucket,
  ///     for instance @"path/to/object".
  /// - Returns: An instance of `StorageReference` pointing to the given path.
  public func reference(withPath path: String) -> StorageReference {
    return reference().child(path)
  }

  /// Configures the Storage SDK to use an emulated backend instead of the default remote backend.
  ///
  /// This method should be called before invoking any other methods on a new instance of `Storage`.
  /// - Parameter host: A string specifying the host.
  /// - Parameter port: The port specified as an `Int`.
  public func useEmulator(withHost host: String, port: Int) {
    guard host.count > 0 else {
      fatalError("Invalid host argument: Cannot connect to empty host.")
    }
    guard port >= 0 else {
      fatalError("Invalid port argument: Port must be greater or equal to zero.")
    }
    state.withLock {
      guard $0.configured == false else {
        fatalError("Cannot connect to emulator after Storage SDK initialization. " +
          "Call useEmulator(host:port:) before creating a Storage " +
          "reference or trying to load data.")
      }
      $0.usesEmulator = true
      $0.scheme = "http"
      $0.host = host
      $0.port = port
    }
  }


  // MARK: - Internal and Private APIs

  private final class InstanceCache: Sendable {
    static let shared = InstanceCache()

    /// A map of active instances, grouped by app and bucket. Keys combine the
    /// FirebaseApp name and bucket to ensure each app gets its own Storage
    /// instance, even when multiple apps share the same storage bucket.
    private let instances: Mutex<[String: Storage]> = .init([:])

    private init() {}

    func storage(app: FirebaseApp, bucket: String) -> Storage {
      instances.withLock { instances in
        let key = "\(app.name)|\(bucket)"
        if let instance = instances[key] {
          return instance
        }
        let newInstance = FirebaseStorage.Storage(app: app, bucket: bucket)
        instances[key] = newInstance
        return newInstance
      }
    }
  }

  let dispatchQueue: DispatchQueue

  init(app: FirebaseApp, bucket: String) {
    self.app = app
    auth = app.auth
    appCheck = app.appCheck
    storageBucket = bucket
    // Must be a serial queue.
    dispatchQueue = DispatchQueue(label: "com.google.firebase.storage")
    state = Mutex(MutableState())
  }

  let auth: AuthInterop?
  let appCheck: AppCheckInterop?
  let storageBucket: String

  var usesEmulator: Bool {
    state.withLock { $0.usesEmulator }
  }

  var host: String {
    state.withLock { $0.host }
  }

  var scheme: String {
    state.withLock { $0.scheme }
  }

  var port: Int {
    state.withLock { $0.port }
  }

  var maxDownloadRetryInterval: TimeInterval {
    state.withLock { $0.maxDownloadRetryInterval }
  }

  var maxOperationRetryInterval: TimeInterval {
    state.withLock { $0.maxOperationRetryInterval }
  }

  var maxUploadRetryInterval: TimeInterval {
    state.withLock { $0.maxUploadRetryInterval }
  }

  /// Performs a crude translation of the user provided timeouts to the retry intervals that
  /// GTMSessionFetcher accepts. GTMSessionFetcher times out operations if the time between
  /// individual retry attempts exceed a certain threshold, while our API contract looks at the
  /// total
  /// observed time of the operation (i.e. the sum of all retries).
  /// @param retryTime A timeout that caps the sum of all retry attempts
  /// @return A timeout that caps the timeout of the last retry attempt
  static func computeRetryInterval(fromRetryTime retryTime: TimeInterval) -> TimeInterval {
    // GTMSessionFetcher's retry starts at 1 second and then doubles every time. We use this
    // information to compute a best-effort estimate of what to translate the user provided retry
    // time into.
    // Note that this is the same as 2 << (log2(retryTime) - 1), but deemed more readable.
    var lastInterval = 1.0
    var sumOfAllIntervals = 1.0

    while sumOfAllIntervals < retryTime {
      lastInterval *= 2
      sumOfAllIntervals += lastInterval
    }
    return lastInterval
  }

  private static func bucket(for app: FirebaseApp) -> String {
    guard let bucket = app.options.storageBucket else {
      fatalError("No default Storage bucket found. Did you configure Firebase Storage properly?")
    }
    if bucket == "" {
      return Storage.bucket(for: app, urlString: "")
    } else {
      return Storage.bucket(for: app, urlString: "gs://\(bucket)/")
    }
  }

  private static func bucket(for app: FirebaseApp, urlString: String) -> String {
    if urlString == "" {
      return ""
    } else {
      guard let path = try? StoragePath.path(GSURI: urlString),
            path.object == nil || path.object == "" else {
        fatalError("Internal Error: Storage bucket cannot be initialized with a path")
      }
      return path.bucket
    }
  }
}
