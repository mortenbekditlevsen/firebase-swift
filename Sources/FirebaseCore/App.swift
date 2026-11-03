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

/// An App Check token for the SDKs, as upstream's `AppCheckTokenResultInterop`.
public protocol AppCheckTokenResultInterop: Sendable {
  /// The token. When getting it failed, a placeholder, which SDKs send anyway, as upstream does,
  /// so the backend can tell an App Check failure from a client without App Check.
  var token: String { get }

  /// Why getting the token failed, if it did.
  var error: Error? { get }
}

/// Gives SDKs App Check tokens, as upstream's `AppCheckInterop`. FirebaseAppCheck's `AppCheck`
/// implements it.
public protocol AppCheckInterop: AnyObject, Sendable {
  /// A cached token, or a new one if there's none or `forcingRefresh` is true.
  func getToken(forcingRefresh: Bool) async -> AppCheckTokenResultInterop

  /// A new limited-use token, which isn't cached.
  func getLimitedUseToken() async -> AppCheckTokenResultInterop

  /// The notification posted (to `NotificationCenter.default`) each time the token changes. Its
  /// `userInfo` has the token and the app's name under `notificationTokenKey` and
  /// `notificationAppNameKey`.
  var tokenDidChangeNotificationName: String { get }

  /// The `userInfo` key for the token in `tokenDidChangeNotificationName` notifications.
  var notificationTokenKey: String { get }

  /// The `userInfo` key for the app's name in `tokenDidChangeNotificationName` notifications.
  var notificationAppNameKey: String { get }
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

  /// Forwards to `auth` on each call, for SDKs to hold: upstream creates Auth when the app is
  /// configured, but here it's created by the first `Auth.auth(app:)`, which may come after the
  /// SDK. With no Auth there's no user, so no token.
  package var lazyAuth: AuthInterop { LazyAuth(app: self) }

  /// App Check's instance for this app, for the other SDKs. Upstream creates it when the app is
  /// configured; here it's created on first use, by the factory FirebaseAppCheck registers in
  /// `appCheckFactory` when the app sets its provider factory.
  package var appCheck: AppCheckInterop? {
    get {
      _appCheck.withLock { appCheck in
        if case let .created(instance) = appCheck {
          return instance
        }
        let instance = Self.appCheckFactory.withLock { $0 }?(self)
        appCheck = .created(instance)
        return instance
      }
    }
    set { _appCheck.withLock { $0 = .created(newValue) } }
  }

  /// Creates App Check's instance for an app, or nil if it has none. Set by FirebaseAppCheck. It's
  /// called with the app's App Check lock held, so it must not read `appCheck`.
  package static let appCheckFactory = Mutex<(@Sendable (FirebaseApp) -> AppCheckInterop?)?>(nil)

  private enum AppCheckState {
    case notCreated
    case created(AppCheckInterop?)
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
  private let _appCheck = Mutex(AppCheckState.notCreated)
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

private final class LazyAuth: AuthInterop {
  private let app: FirebaseApp

  init(app: FirebaseApp) {
    self.app = app
  }

  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String? {
    try await app.auth?.getToken(forcingRefresh: forceRefresh)
  }

  func getUserID() -> String? {
    app.auth?.getUserID()
  }
}

public protocol AuthInterop: AnyObject, Sendable {
  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String?
  func getUserID() -> String?
}

extension Notification.Name {
  /// Posted by Auth whenever the signed-in user or their ID token changes,
  /// and when it's created with a saved user, for other Firebase SDKs
  /// (Database, Firestore) to refresh credentials.
  /// `object` is the `AuthInterop` instance and `userInfo` holds the
  /// `FIRAuthStateDidChangeInternalNotification…Key` entries. Unlike the
  /// public Auth notification, it is not posted on the main queue.
  public static let FIRAuthStateDidChangeInternalNotification =
    Notification.Name("FIRAuthStateDidChangeInternalNotification")
}

/// The `FirebaseApp` the notifying Auth instance belongs to. SDKs filter by it, since they hold
/// `FirebaseApp.lazyAuth`, not the Auth instance.
public let FIRAuthStateDidChangeInternalNotificationAppKey =
  "FIRAuthStateDidChangeInternalNotificationAppKey"
/// The new ID token; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationTokenKey =
  "FIRAuthStateDidChangeInternalNotificationTokenKey"
/// The new user's UID; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationUIDKey =
  "FIRAuthStateDidChangeInternalNotificationUIDKey"
