// Copyright 2020 Google LLC
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
import Logging
import Synchronization

let logger = Logger(label: "[FirebaseAppCheck]")

public extension Notification.Name {
  /// A notification with the specified name is sent to the default notification center
  /// (`NotificationCenter.default`) each time a Firebase app check token is refreshed.
  /// The user info dictionary contains `AppCheckTokenNotificationKey` and
  /// `AppCheckAppNameNotificationKey` keys.
  static let AppCheckTokenDidChange =
    Notification.Name("FIRAppCheckAppCheckTokenDidChangeNotification")
}

/// `userInfo` key for the `AppCheckToken` in `AppCheckTokenDidChange` notifications.
public let AppCheckTokenNotificationKey = "FIRAppCheckTokenNotificationKey"

/// `userInfo` key for the `FirebaseApp.name` in `AppCheckTokenDidChange` notifications.
public let AppCheckAppNameNotificationKey = "FIRAppCheckAppNameNotificationKey"

/// A class used to manage App Check tokens for a given Firebase app.
public final class AppCheck: AppCheckInterop, Sendable {
  /// Returns a default instance of `AppCheck`, for the default Firebase app.
  /// - Note: `FirebaseApp.configure()` must be called before using this method, and the
  ///   provider factory must have been set with `setAppCheckProviderFactory(_:keychain:)`.
  public static func appCheck() -> AppCheck {
    guard let app = FirebaseApp.app() else {
      fatalError("The default FirebaseApp instance must be configured before the default " +
        "AppCheck instance can be initialized. One way to ensure this is to call " +
        "`FirebaseApp.configure()` in the App Delegate's " +
        "`application(_:didFinishLaunchingWithOptions:)`.")
    }
    guard let appCheck = appCheck(app: app) else {
      fatalError("App Check could not be created for the default app. Set a provider factory " +
        "with `AppCheck.setAppCheckProviderFactory(_:keychain:)` before `FirebaseApp.configure()`.")
    }
    return appCheck
  }

  /// Returns an instance of `AppCheck` for an application, or nil if there's no provider for it.
  /// - Parameter firebaseApp: A configured `FirebaseApp` instance if exists.
  public static func appCheck(app firebaseApp: FirebaseApp) -> AppCheck? {
    firebaseApp.appCheck as? AppCheck
  }

  /// Set an instance of a Firebase App Check provider factory, and the storage App Check keeps
  /// its tokens in.
  ///
  /// Upstream sets a default factory when the module loads (the debug provider in the Simulator,
  /// DeviceCheck elsewhere), so linking FirebaseAppCheck turns App Check on. Swift can't run code
  /// at load time, so here App Check is on once this is called, for example with
  /// `DeviceCheckProviderFactory()`.
  ///
  /// Call it before `FirebaseApp.configure()`, as upstream requires. Here it takes effect for
  /// each app whose App Check instance hasn't been created yet: SDKs create it when they're
  /// created.
  /// - Parameters:
  ///   - factory: An instance of a Firebase App Check provider factory.
  ///   - keychain: Where tokens (and App Attest's artifact) are stored between launches. Upstream
  ///     uses the keychain; this port leaves the choice to the app, see `AppCheckKeychain`.
  public static func setAppCheckProviderFactory(_ factory: (any AppCheckProviderFactory)?,
                                                keychain: any AppCheckKeychain) {
    configuration.withLock { $0 = Configuration(providerFactory: factory, keychain: keychain) }
    FirebaseApp.appCheckFactory.withLock {
      $0 = { app in AppCheck(app: app) }
    }
  }

  /// The storage passed to `setAppCheckProviderFactory(_:keychain:)`.
  static var keychain: (any AppCheckKeychain)? {
    configuration.withLock { $0?.keychain }
  }

  /// If this flag is disabled then Firebase App Check will not periodically auto-refresh the
  /// Firebase App Check token. The default value of the flag is equal to
  /// `FirebaseApp.dataCollectionDefaultEnabled`, which is true here. To disable auto-refresh for
  /// a specific `FirebaseApp` instance, set the flag to false. The flag is saved, so it doesn't
  /// have to be set on each launch.
  public var isTokenAutoRefreshEnabled: Bool {
    get { settings.isTokenAutoRefreshEnabled }
    set { settings.isTokenAutoRefreshEnabled = newValue }
  }

  /// Requests a Firebase App Check token. This method should *only* be used if you need to
  /// authorize requests to a non-Firebase backend. Requests to Firebase backends are authorized
  /// automatically if configured.
  ///
  /// If the token has been cached and is still valid, it's returned; otherwise a new token is
  /// requested.
  /// - Parameter forcingRefresh: If `true`, both the in-memory and persisted caches are ignored
  ///   and a new token is requested from the App Check backend.
  /// - Throws: An error in `AppCheckErrorDomain`.
  public func token(forcingRefresh: Bool) async throws -> AppCheckToken {
    do {
      let token = try await appCheckCore.token(forcingRefresh: forcingRefresh)
      return AppCheckToken(internalToken: token)
    } catch {
      throw AppCheckErrorUtil.publicDomainError(with: error)
    }
  }

  /// Requests a limited-use Firebase App Check token. This method should be used only if you need
  /// to authorize requests to a non-Firebase backend.
  ///
  /// Returns limited-use tokens that are intended for use with your non-Firebase backend
  /// endpoints that are protected with Replay Protection. This method does not affect the token
  /// generation behavior of the `token(forcingRefresh:)` method.
  /// - Throws: An error in `AppCheckErrorDomain`.
  public func limitedUseToken() async throws -> AppCheckToken {
    do {
      return AppCheckToken(internalToken: try await appCheckCore.limitedUseToken())
    } catch {
      throw AppCheckErrorUtil.publicDomainError(with: error)
    }
  }

  // MARK: - AppCheckInterop

  public func getToken(forcingRefresh: Bool) async -> AppCheckTokenResultInterop {
    await tokenResult { try await self.appCheckCore.token(forcingRefresh: forcingRefresh) }
  }

  public func getLimitedUseToken() async -> AppCheckTokenResultInterop {
    await tokenResult { try await self.appCheckCore.limitedUseToken() }
  }

  public var tokenDidChangeNotificationName: String {
    Notification.Name.AppCheckTokenDidChange.rawValue
  }

  public var notificationTokenKey: String { AppCheckTokenNotificationKey }

  public var notificationAppNameKey: String { AppCheckAppNameNotificationKey }

  // MARK: - Internal

  private struct Configuration {
    let providerFactory: (any AppCheckProviderFactory)?
    let keychain: any AppCheckKeychain
  }

  private static let configuration = Mutex<Configuration?>(nil)

  private let appName: String
  private let appCheckCore: AppCheckCore
  private let settings: AppCheckSettings
  private let tokenDelegate: TokenDelegate

  /// As upstream's `-[FIRAppCheck initWithApp:]`.
  convenience init?(app: FirebaseApp) {
    guard let configuration = Self.configuration.withLock({ $0 }),
          let providerFactory = configuration.providerFactory else {
      logger.error("""
      I-FAA001001: Cannot instantiate `FIRAppCheck` for app: \(app.name) without a provider \
      factory. Please register a provider factory using \
      `AppCheck.setAppCheckProviderFactory(_:keychain:)` method.
      """)
      return nil
    }
    guard let appCheckProvider = providerFactory.createProvider(with: app) else {
      logger.error("""
      I-FAA001002: Cannot instantiate `FIRAppCheck` for app: \(app.name) without an app check \
      provider. Please make sure the provider factory returns a valid app check provider.
      """)
      return nil
    }
    let settings = AppCheckSettings(appName: app.name)
    let tokenDelegate = TokenDelegate(appName: app.name)
    let appCheckCore = AppCheckCore(
      serviceName: "FirebaseApp:\(app.name)",
      resourceName: app.appCheckResourceName,
      appCheckProvider: InternalAppCheckProvider(appCheckProvider: appCheckProvider),
      settings: settings,
      tokenDelegate: tokenDelegate,
      keychain: configuration.keychain,
      keychainAccessGroup: app.options.appGroupID
    )
    self.init(appName: app.name, appCheckCore: appCheckCore, settings: settings,
              tokenDelegate: tokenDelegate)
  }

  init(appName: String, appCheckCore: AppCheckCore, settings: AppCheckSettings,
       tokenDelegate: TokenDelegate) {
    self.appName = appName
    self.appCheckCore = appCheckCore
    self.settings = settings
    self.tokenDelegate = tokenDelegate
    tokenDelegate.appCheck.withLock { $0 = WeakAppCheck(value: self) }
  }

  /// The token, or the placeholder token and the error, as upstream's interop methods return.
  private func tokenResult(_ getToken: () async throws -> AppCheckCoreToken) async
    -> AppCheckTokenResultInterop {
    do {
      return TokenResult(token: try await getToken().token, error: nil)
    } catch {
      return TokenResult(token: AppCheckCoreTokenResult.placeholderToken().token, error: error)
    }
  }
}

private struct TokenResult: AppCheckTokenResultInterop {
  let token: String
  let error: Error?
}

private struct WeakAppCheck {
  weak var value: AppCheck?
}

/// Receives AppCheckCore's token updates and posts `AppCheckTokenDidChange`, as upstream's
/// `FIRAppCheck` does as a `GACAppCheckTokenDelegate`.
final class TokenDelegate: NSObject, AppCheckCoreTokenDelegate, @unchecked Sendable {
  private let appName: String
  fileprivate let appCheck = Mutex(WeakAppCheck())

  init(appName: String) {
    self.appName = appName
  }

  func tokenDidUpdate(_ token: AppCheckCoreToken, serviceName: String) {
    NotificationCenter.default.post(
      name: .AppCheckTokenDidChange,
      object: appCheck.withLock { $0.value },
      userInfo: [
        AppCheckTokenNotificationKey: token.token,
        AppCheckAppNameNotificationKey: appName,
      ]
    )
  }
}

/// Whether tokens are refreshed automatically, as upstream's `FIRAppCheckSettings`: an explicit
/// setting (saved in UserDefaults), else `FirebaseAppCheckTokenAutoRefreshEnabled` in the main
/// bundle's Info.plist, else `FirebaseApp.isDataCollectionDefaultEnabled`, which isn't ported and
/// is true.
final class AppCheckSettings: NSObject, AppCheckCoreSettingsProtocol, @unchecked Sendable {
  static let userDefaultsKeyPrefix = "FIRAppCheckTokenAutoRefreshEnabled_"
  static let infoPlistKey = "FirebaseAppCheckTokenAutoRefreshEnabled"

  private let userDefaults: UserDefaults
  private let mainBundle: Bundle
  private let userDefaultsKey: String
  private let state = Mutex<Bool?>(nil)

  init(appName: String, userDefaults: UserDefaults = .standard, mainBundle: Bundle = .main) {
    self.userDefaults = userDefaults
    self.mainBundle = mainBundle
    userDefaultsKey = Self.userDefaultsKeyPrefix + appName
  }

  var isTokenAutoRefreshEnabled: Bool {
    get {
      state.withLock { state in
        if let state {
          return state
        }
        let configured = (userDefaults.object(forKey: userDefaultsKey) as? NSNumber)
          ?? (mainBundle.object(forInfoDictionaryKey: Self.infoPlistKey) as? NSNumber)
        if let configured {
          state = configured.boolValue
          return configured.boolValue
        }
        return true
      }
    }
    set {
      state.withLock { $0 = newValue }
      userDefaults.set(newValue, forKey: userDefaultsKey)
    }
  }
}
