// Copyright 2017 Google LLC
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

/// The firebase-ios-sdk release this package corresponds to, sent to the
/// backends in version headers. Keep it in sync with `firebaseVersion` in
/// Package.swift; UPSTREAM.md has each module's actual baseline.
public func FirebaseVersion() -> String {
  "13.1.1"
}

/// Stands in for upstream's heartbeat logger, which isn't ported: nothing
/// conforms to it yet.
public protocol FIRHeartbeatLoggerProtocol: Sendable {}

/// Gives SDKs App Check tokens. App Check isn't ported yet; until it is, an
/// app can set `FirebaseApp.appCheck` to its own provider.
public protocol AppCheckInterop: Sendable {
  func getToken(forcingRefresh: Bool) async throws -> String
}

/// An SDK's state for one app, standing in for upstream's component
/// container: `FirebaseApp.component(_:)` creates one of each type per app,
/// and `FirebaseApp.delete()` drops them.
package protocol FirebaseAppComponent: AnyObject, Sendable {
  /// Called with the app's component lock held, so it must not call
  /// `component(_:)`.
  init()

  /// Called when the app is deleted, after it has left the registry.
  func appWillBeDeleted(_ app: FirebaseApp) async
}

/// The entry point of Firebase SDKs.
///
/// Initialize and configure `FirebaseApp` using `FirebaseApp.configure()`, or other customized
/// ways as shown below.
///
/// The logic flow of the SDKs works as follows:
///
/// 1. A developer calls `FirebaseApp.configure()` (or another `configure` method), which reads the
///    options (`FirebaseOptions.defaultOptions()`) and creates the default app.
/// 2. The SDKs (Auth, Database, Firestore, …) get their instances for an app, such as
///    `Auth.auth()` for the default one.
///
/// Apps other than the default one need a name, and can be retrieved with `app(name:)`.
public final class FirebaseApp: Equatable, Sendable {
  public static func == (lhs: FirebaseApp, rhs: FirebaseApp) -> Bool {
    lhs === rhs
  }

  /// The name of the default app.
  package static let defaultAppName = "__FIRAPP_DEFAULT"

  /// Configures the default app from `FirebaseOptions.defaultOptions()`: the `FIREBASE_OPTIONS`
  /// environment variable or, as upstream, `GoogleService-Info.plist` in the main bundle. Crashes
  /// if there are no options, or if the default app is already configured.
  public static func configure() {
    guard let options = FirebaseOptions.defaultOptions() else {
      fatalError(
        "`FirebaseApp.configure()` could not find a valid GoogleService-Info.plist in your " +
          "project, or valid options in the \(FirebaseOptions.environmentVariable) " +
          "environment variable. Please download a configuration file from " +
          "https://console.firebase.google.com/."
      )
    }
    configure(options: options)
  }

  /// Configures the default app with `options`. Crashes if it's already configured.
  public static func configure(options: FirebaseOptions) {
    configure(name: defaultAppName, options: options)
  }

  /// Configures an app named `name` with `options`. The name can only contain letters, digits,
  /// hyphens and underscores. Crashes if an app with this name is already configured.
  public static func configure(name: String, options: FirebaseOptions) {
    if name.isEmpty {
      fatalError("Name cannot be empty.")
    }
    if name != defaultAppName {
      var allowed = CharacterSet.alphanumerics
      allowed.insert(charactersIn: "-_")
      if !name.unicodeScalars.allSatisfy(allowed.contains) {
        fatalError("App name can only contain alphanumeric, hyphen (-), and underscore (_) " +
          "characters")
      }
    }
    if options.googleAppID.isEmpty {
      fatalError("Configuration fails. It may be caused by an invalid GOOGLE_APP_ID in " +
        "GoogleService-Info.plist or set in the customized options.")
    }
    // Pre-cache the locale and calendar to prevent a race condition with C++ dependencies
    // that temporarily mutate the global POSIX C locale during initialization (upstream #16542).
    _ = cachedLocale
    allApps_.withLock { apps in
      if let existing = apps[name] {
        // Only an extension may configure an app twice, and only with the same options.
        guard isAppExtension, existing.options == options else {
          fatalError(name == defaultAppName ? "Default app has already been configured."
            : "App named \(name) has already been configured.")
        }
        return
      }
      apps[name] = FirebaseApp(options: options, name: name)
    }
  }

  /// The default app, or nil if it hasn't been configured.
  public static func app() -> FirebaseApp? {
    defaultApp
  }

  /// The app named `name`, or nil if there is none.
  public static func app(name: String) -> FirebaseApp? {
    allApps_.withLock { $0[name] }
  }

  /// The configured apps by name, or nil if there are none.
  public static var allApps: [String: FirebaseApp]? {
    allApps_.withLock { $0.isEmpty ? nil : $0 }
  }

  package static var defaultApp: FirebaseApp? { app(name: defaultAppName) }
  package static var isDefaultAppConfigured: Bool { defaultApp != nil }

  /// Deletes the app: it leaves the registry, and the SDKs drop their instances for it (Firestore
  /// terminates, Auth forgets its stored user). Returns false if the app wasn't configured.
  public func delete() async -> Bool {
    let removed = Self.allApps_.withLock { apps in
      guard apps[name] === self else { return false }
      apps[name] = nil
      return true
    }
    guard removed else { return false }
    let components = _components.withLock { state in
      state.isDeleted = true
      defer { state.components = [:] }
      return Array(state.components.values)
    }
    for component in components {
      await component.appWillBeDeleted(self)
    }
    return true
  }

  /// The name of this app.
  public let name: String

  /// The options this app was configured with.
  public let options: FirebaseOptions

  package var isDefaultApp: Bool { name == Self.defaultAppName }

  /// Auth's instance for this app, for the other SDKs. Auth sets it.
  package var auth: AuthInterop? {
    get { _auth.withLock { $0 } }
    set { _auth.withLock { $0 = newValue } }
  }

  /// The App Check provider the SDKs get tokens from. App Check isn't ported yet; until it is, an
  /// app can set its own provider here, before it gets any SDK instances for this app.
  public var appCheck: AppCheckInterop? {
    get { _appCheck.withLock { $0 } }
    set { _appCheck.withLock { $0 = newValue } }
  }

  package var heartbeatLogger: FIRHeartbeatLoggerProtocol? {
    get { _heartbeatLogger.withLock { $0 } }
    set { _heartbeatLogger.withLock { $0 = newValue } }
  }

  /// The component of type `C` for this app, created on first use. Crashes if the app has been
  /// deleted, as upstream's SDK getters do.
  package func component<C: FirebaseAppComponent>(_ type: C.Type) -> C {
    _components.withLock { state in
      if state.isDeleted {
        fatalError("FirebaseApp named \(name) has been deleted.")
      }
      let key = ObjectIdentifier(type)
      if let existing = state.components[key] as? C {
        return existing
      }
      let component = C()
      state.components[key] = component
      return component
    }
  }

  /// Creates an app that isn't in the registry, for tests (upstream's `initInstanceWithName:`).
  package init(options: FirebaseOptions, name: String) {
    self.options = options
    self.name = name
  }

  private struct Components {
    var components: [ObjectIdentifier: any FirebaseAppComponent] = [:]
    var isDeleted = false
  }

  private let _auth: Mutex<AuthInterop?> = .init(nil)
  private let _appCheck: Mutex<AppCheckInterop?> = .init(nil)
  private let _heartbeatLogger: Mutex<FIRHeartbeatLoggerProtocol?> = .init(nil)
  private let _components = Mutex(Components())

  private static let allApps_ = Mutex<[String: FirebaseApp]>([:])

  private static let cachedLocale: Void = {
    _ = Locale.current
    _ = Calendar.current
    _ = Calendar.autoupdatingCurrent
  }()

  private static var isAppExtension: Bool {
    #if canImport(Darwin)
      Bundle.main.bundlePath.hasSuffix(".appex")
    #else
      false
    #endif
  }
}

public protocol AuthInterop: AnyObject, Sendable {
  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String?
  func getUserID() -> String?
}

extension Notification.Name {
  /// Posted by Auth whenever the signed-in user or their ID token changes,
  /// for other Firebase SDKs (Database, Firestore) to refresh credentials.
  /// `object` is the `AuthInterop` instance and `userInfo` holds the
  /// `FIRAuthStateDidChangeInternalNotification…Key` entries. Unlike the
  /// public Auth notification, it is not posted on the main queue.
  public static let FIRAuthStateDidChangeInternalNotification =
    Notification.Name("FIRAuthStateDidChangeInternalNotification")
}

/// The `FirebaseApp` the notifying Auth instance belongs to.
public let FIRAuthStateDidChangeInternalNotificationAppKey =
  "FIRAuthStateDidChangeInternalNotificationAppKey"
/// The new ID token; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationTokenKey =
  "FIRAuthStateDidChangeInternalNotificationTokenKey"
/// The new user's UID; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationUIDKey =
  "FIRAuthStateDidChangeInternalNotificationUIDKey"
