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
import Synchronization

typealias CppCacheKind = firebase.firestore.swift_bridge.CacheKind

/// Used to set the on-disk cache size to unlimited. Garbage collection will not run.
public let FirestoreCacheSizeUnlimited: Int64 = -1

let defaultCacheSizeBytes: Int64 = 100 * 1024 * 1024
let minimumCacheSizeBytes: Int64 = 1024 * 1024

/// Settings for a Firestore instance.
///
/// As upstream, `Firestore.settings` returns a copy: change it and assign it
/// back. Settings can only change before the instance is first used.
public final class FirestoreSettings: Hashable, Sendable {
  private struct State {
    var host = "firestore.googleapis.com"
    var isSSLEnabled = true
    var cacheSettings: any LocalCacheSettings = PersistentCacheSettings()
  }

  private let state: Mutex<State>

  public init() {
    state = Mutex(State())
  }

  private init(state: State) {
    self.state = Mutex(state)
  }

  /// The host to connect to.
  public var host: String {
    get { state.withLock { $0.host } }
    set { state.withLock { $0.host = newValue } }
  }

  /// Whether to use SSL when connecting.
  public var isSSLEnabled: Bool {
    get { state.withLock { $0.isSSLEnabled } }
    set { state.withLock { $0.isSSLEnabled = newValue } }
  }

  /// The local cache: `PersistentCacheSettings` (the default) or
  /// `MemoryCacheSettings`.
  public var cacheSettings: any LocalCacheSettings {
    get { state.withLock { $0.cacheSettings } }
    set { state.withLock { $0.cacheSettings = newValue } }
  }

  func copy() -> FirestoreSettings {
    FirestoreSettings(state: state.withLock { $0 })
  }

  var isUsingDefaultHost: Bool {
    host == "firestore.googleapis.com"
  }

  private var key: Key {
    state.withLock { Key(host: $0.host, isSSLEnabled: $0.isSSLEnabled,
                         cache: CacheKey($0.cacheSettings)) }
  }

  public static func == (lhs: FirestoreSettings, rhs: FirestoreSettings) -> Bool {
    lhs.key == rhs.key
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
  }

  /// Applies these settings to the core.
  func apply(to bridge: inout CppFirestoreBridge) {
    let state = state.withLock { $0 }
    let (kind, sizeBytes): (CppCacheKind, Int64) = switch CacheKey(state.cacheSettings) {
    case let .persistent(sizeBytes): (.Persistent, sizeBytes)
    case .memoryEager: (.MemoryEager, 0)
    case let .memoryLRU(sizeBytes): (.MemoryLru, sizeBytes)
    }
    bridge.SetSettings(std.string(state.host), state.isSSLEnabled, kind, sizeBytes)
  }

  private struct Key: Hashable {
    let host: String
    let isSSLEnabled: Bool
    let cache: CacheKey
  }
}

/// What a `LocalCacheSettings` amounts to, for comparing and for the core.
enum CacheKey: Hashable {
  case persistent(sizeBytes: Int64)
  case memoryEager
  case memoryLRU(sizeBytes: Int64)

  init(_ settings: any LocalCacheSettings) {
    switch settings {
    case let settings as PersistentCacheSettings:
      self = .persistent(sizeBytes: settings.sizeBytes)
    case let settings as MemoryCacheSettings:
      switch settings.garbageCollectorSettings {
      case let gc as MemoryLRUGCSettings: self = .memoryLRU(sizeBytes: gc.sizeBytes)
      case is MemoryEagerGCSetting: self = .memoryEager
      case let gc: invalidArgument("Unsupported garbage collector settings: \(type(of: gc))")
      }
    default:
      invalidArgument("Unsupported cache settings: \(type(of: settings))")
    }
  }
}

/// The local cache of a Firestore instance: `PersistentCacheSettings` or
/// `MemoryCacheSettings`.
public protocol LocalCacheSettings: Sendable {}

/// A cache on disk, which survives restarts.
public final class PersistentCacheSettings: LocalCacheSettings, Hashable {
  let sizeBytes: Int64

  /// A cache of the default size, 100 MB.
  public init() {
    sizeBytes = defaultCacheSizeBytes
  }

  /// A cache of `size` bytes, at least 1 MB, or `FirestoreCacheSizeUnlimited`.
  /// Above that size, the SDK removes the least recently used documents.
  public init(sizeBytes size: NSNumber) {
    let size = size.int64Value
    if size != FirestoreCacheSizeUnlimited, size < minimumCacheSizeBytes {
      invalidArgument("Cache size must be set to at least \(minimumCacheSizeBytes) bytes")
    }
    sizeBytes = size
  }

  public static func == (lhs: PersistentCacheSettings, rhs: PersistentCacheSettings) -> Bool {
    lhs.sizeBytes == rhs.sizeBytes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(sizeBytes)
  }
}

/// How an in-memory cache removes documents.
public protocol MemoryGarbageCollectorSettings: Sendable {}

/// Removes documents as soon as no query uses them. The name is upstream's.
public final class MemoryEagerGCSetting: MemoryGarbageCollectorSettings, Hashable {
  public init() {}

  public static func == (lhs: MemoryEagerGCSetting, rhs: MemoryEagerGCSetting) -> Bool {
    true
  }

  public func hash(into hasher: inout Hasher) {}
}

/// Removes the least recently used documents once the cache is above a size.
public final class MemoryLRUGCSettings: MemoryGarbageCollectorSettings, Hashable {
  let sizeBytes: Int64

  /// Collects above the default size, 100 MB.
  public init() {
    sizeBytes = defaultCacheSizeBytes
  }

  /// Collects above `size` bytes.
  public init(sizeBytes size: NSNumber) {
    sizeBytes = size.int64Value
  }

  public static func == (lhs: MemoryLRUGCSettings, rhs: MemoryLRUGCSettings) -> Bool {
    lhs.sizeBytes == rhs.sizeBytes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(sizeBytes)
  }
}

/// A cache in memory, which is gone when the app stops.
public final class MemoryCacheSettings: LocalCacheSettings, Hashable {
  let garbageCollectorSettings: any MemoryGarbageCollectorSettings

  /// A cache with LRU garbage collection of the default size, as upstream.
  public init() {
    garbageCollectorSettings = MemoryLRUGCSettings()
  }

  public init(garbageCollectorSettings settings: any MemoryGarbageCollectorSettings) {
    garbageCollectorSettings = settings
  }

  public static func == (lhs: MemoryCacheSettings, rhs: MemoryCacheSettings) -> Bool {
    CacheKey(lhs) == CacheKey(rhs)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(CacheKey(self))
  }
}

typealias CppPersistentCacheIndexManagerBridge =
  firebase.firestore.swift_bridge.PersistentCacheIndexManagerBridge

/// The indexes of a persistent cache, which speed up local queries.
public final class PersistentCacheIndexManager: @unchecked Sendable {
  // The C++ manager is thread-safe.
  private let cppBridge: CppPersistentCacheIndexManagerBridge

  init(cppBridge: CppPersistentCacheIndexManagerBridge) {
    self.cppBridge = cppBridge
  }

  /// Lets the SDK create indexes for queries that would run faster with one.
  /// Off by default.
  public func enableIndexAutoCreation() {
    cppBridge.EnableIndexAutoCreation()
  }

  /// Stops creating indexes; existing ones stay.
  public func disableIndexAutoCreation() {
    cppBridge.DisableIndexAutoCreation()
  }

  /// Deletes all indexes in the cache.
  public func deleteAllIndexes() {
    cppBridge.DeleteAllIndexes()
  }
}

public extension Firestore {
  /// Turns debug logging of the Firestore client on or off.
  static func enableLogging(_ logging: Bool) {
    CppFirestoreBridge.EnableLogging(logging)
  }
}
