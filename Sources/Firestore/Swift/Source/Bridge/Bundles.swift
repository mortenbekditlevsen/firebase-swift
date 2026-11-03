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

typealias CppLoadBundleTaskBridge = firebase.firestore.swift_bridge.LoadBundleTaskBridge

/// The state of a bundle being loaded.
public enum LoadBundleTaskState: Int, Sendable {
  /// Loading failed.
  case error = 0
  /// Loading is in progress.
  case inProgress = 1
  /// Loading succeeded.
  case success = 2
}

/// The progress of loading a bundle.
public final class LoadBundleTaskProgress: Sendable {
  /// How many documents have been loaded.
  public let documentsLoaded: Int
  /// How many documents the bundle has, or 0 if it couldn't be parsed.
  public let totalDocuments: Int
  /// How many bytes have been loaded.
  public let bytesLoaded: Int
  /// How many bytes the bundle has, or 0 if it couldn't be parsed.
  public let totalBytes: Int
  public let state: LoadBundleTaskState

  init(state: LoadBundleTaskState, documentsLoaded: UInt32, totalDocuments: UInt32,
       bytesLoaded: UInt64, totalBytes: UInt64) {
    self.state = state
    self.documentsLoaded = Int(documentsLoaded)
    self.totalDocuments = Int(totalDocuments)
    self.bytesLoaded = Int(bytesLoaded)
    self.totalBytes = Int(totalBytes)
  }
}

/// Identifies an observer of a `LoadBundleTask`.
public typealias LoadBundleObserverHandle = Int

/// A bundle being loaded, which observers can follow.
public final class LoadBundleTask: @unchecked Sendable {
  // The C++ task is thread-safe.
  private let cppBridge: CppLoadBundleTaskBridge

  init(cppBridge: CppLoadBundleTaskBridge) {
    self.cppBridge = cppBridge
  }

  /// Calls `observer` with each later progress update, until it's removed.
  /// As upstream, updates made before the observer was added aren't repeated.
  @discardableResult
  public func addObserver(_ observer: @escaping (LoadBundleTaskProgress) -> Void)
    -> LoadBundleObserverHandle {
    let handler: ProgressHandler = { progress, _ in observer(progress) }
    return Int(cppBridge.Observe(retainedContext(handler), releaseCallbackBox,
                                 loadBundleProgressTrampoline))
  }

  public func removeObserverWith(handle: LoadBundleObserverHandle) {
    cppBridge.RemoveObserver(Int64(handle))
  }

  public func removeAllObservers() {
    cppBridge.RemoveAllObservers()
  }
}

public extension Firestore {
  /// Loads a bundle into the local cache.
  @discardableResult
  func loadBundle(_ bundleData: Data) -> LoadBundleTask {
    loadBundle(InputStream(data: bundleData), completion: nil)
  }

  /// Loads a bundle from a stream into the local cache. The stream is opened
  /// and read on a background thread.
  @discardableResult
  func loadBundle(_ bundleStream: InputStream) -> LoadBundleTask {
    loadBundle(bundleStream, completion: nil)
  }

  /// The query a loaded bundle saved under `name`, or nil if there's none.
  func getQuery(named name: String) async -> Query? {
    await withCheckedContinuation { continuation in
      let handler: NamedQueryHandler = { [self] query in
        continuation.resume(returning: query.map { Query(cppBridge: $0, firestore: self) })
      }
      cppBridge.GetNamedQuery(std.string(name), retainedContext(handler),
                              namedQueryTrampoline)
    }
  }
}

extension Firestore {
  /// Loads a bundle, then calls `completion` with the final progress and, if
  /// loading failed, the error. Upstream's async `loadBundle(_:)` uses these.
  @discardableResult
  func loadBundle(_ bundleData: Data,
                  completion: ((LoadBundleTaskProgress?, Error?) -> Void)?) -> LoadBundleTask {
    loadBundle(InputStream(data: bundleData), completion: completion)
  }

  @discardableResult
  func loadBundle(_ bundleStream: InputStream,
                  completion: ((LoadBundleTaskProgress?, Error?) -> Void)?) -> LoadBundleTask {
    let completionContext = completion.map { completion in
      let handler: ProgressHandler = { progress, error in
        // As upstream, only the final state completes.
        if progress.state != .inProgress {
          completion(progress, error)
        }
      }
      return retainedContext(handler)
    }
    bundleStream.open()
    let stream = BundleStream(bundleStream)
    let progressCallback: LoadBundleProgressCallback? =
      completion == nil ? nil : loadBundleProgressTrampoline
    let task = cppBridge.LoadBundle(
      Unmanaged.passRetained(stream).toOpaque(), readBundleStream, releaseBundleStream,
      completionContext, releaseCallbackBox, progressCallback
    )
    return LoadBundleTask(cppBridge: task)
  }
}

private typealias ProgressHandler = (LoadBundleTaskProgress, Error?) -> Void
private typealias NamedQueryHandler = (CppQueryBridge?) -> Void

/// The stream of a bundle being loaded. The core reads it from one thread at
/// a time.
private final class BundleStream: @unchecked Sendable {
  let stream: InputStream

  init(_ stream: InputStream) {
    self.stream = stream
  }

  deinit {
    stream.close()
  }
}

private func readBundleStream(
  context: UnsafeMutableRawPointer?,
  buffer: UnsafeMutablePointer<UInt8>?,
  maxLength: Int
) -> Int64 {
  guard let context, let buffer else { return -1 }
  let stream = Unmanaged<BundleStream>.fromOpaque(context).takeUnretainedValue().stream
  return Int64(stream.read(buffer, maxLength: maxLength))
}

private func releaseBundleStream(context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<BundleStream>.fromOpaque(context).release()
}

private func loadBundleProgressTrampoline(
  context: UnsafeMutableRawPointer?,
  state: Int32,
  documentsLoaded: UInt32,
  totalDocuments: UInt32,
  bytesLoaded: UInt64,
  totalBytes: UInt64,
  code: Int32,
  message: UnsafePointer<CChar>?
) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<ProgressHandler>>.fromOpaque(context).takeUnretainedValue()
  let state = LoadBundleTaskState(rawValue: Int(state)) ?? .error
  let progress = LoadBundleTaskProgress(
    state: state, documentsLoaded: documentsLoaded, totalDocuments: totalDocuments,
    bytesLoaded: bytesLoaded, totalBytes: totalBytes
  )
  var error: Error?
  if state == .error {
    error = firestoreError(code: code, message: message)
      ?? FirestoreErrorCode(.unknown, userInfo: [
        NSLocalizedDescriptionKey: "Loading bundle failed with unknown error",
      ])
  }
  box.handler(progress, error)
}

private func namedQueryTrampoline(context: UnsafeMutableRawPointer?,
                                  query: UnsafeMutableRawPointer?) {
  guard let context else { return }
  let box = Unmanaged<CallbackBox<NamedQueryHandler>>.fromOpaque(context).takeRetainedValue()
  box.handler(takeBridge(query, as: CppQueryBridge.self))
}
