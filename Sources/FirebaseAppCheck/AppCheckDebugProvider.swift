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

/// A Firebase App Check provider that can exchange a debug token registered in the Firebase
/// console for a Firebase App Check token. The debug provider is designed to enable testing
/// applications on a simulator or test environment.
///
/// NOTE: Do NOT use the debug provider in applications used by real users.
///
/// The debug token is read from the `FIRAAppCheckDebugToken` environment variable if it's set,
/// as in a CI environment; otherwise a token is generated, saved and logged on the first launch.
/// Register it in the Firebase console, or with
/// `firebase appcheck:debugtokens:create <token> --project <project ID> --app <app ID>`.
///
/// Alternatively, provision a debug token with the Firebase CLI
/// (`firebase appcheck:debugtokens:create --app <app ID>`), which registers it and saves it to
/// `~/.config/configstore/firebase-appcheck.json`. Apps launched from Xcode in a Simulator
/// pick up the saved token automatically, so no manual registration is needed.
public final class AppCheckDebugProvider: AppCheckProvider, @unchecked Sendable {
  private let debugProvider: AppCheckCoreDebugProvider
  let projectID: String?
  let googleAppID: String
  /// Where `debugProvider` got the debug token it exchanges. The only token `init(app:)` passes
  /// it is one from the Firebase CLI's config store, so `.provided` means that token is in use.
  private let debugTokenSource: AppCheckCoreDebugTokenSource

  /// The default initializer.
  /// - Parameter app: A `FirebaseApp` instance.
  /// - Returns: An instance of `AppCheckDebugProvider` if the provided `FirebaseApp` instance
  ///   contains all required parameters.
  public convenience init?(app: FirebaseApp) {
    let missingFields = tokenExchangeMissingFields(in: app.options)
    guard missingFields.isEmpty, let apiKey = app.options.apiKey else {
      logger.error("""
      I-FAA003002: Cannot instantiate `FIRAppCheckDebugProvider` for app: \(app.name). The \
      following `FirebaseOptions` fields are missing: \(missingFields.joined(separator: ", "))
      """)
      return nil
    }
    // In a Simulator, use the debug token provisioned by the Firebase CLI on the host machine (if
    // any) instead of generating a new one that would need to be registered manually.
    let configStoreDebugToken =
      AppCheckDebugTokenConfigStore.debugToken(forGoogleAppID: app.options.googleAppID)
    let debugProvider = AppCheckCoreDebugProvider(serviceName: app.name,
                                                  resourceName: app.appCheckResourceName,
                                                  baseURL: nil,
                                                  apiKey: apiKey,
                                                  requestHooks: nil,
                                                  debugToken: configStoreDebugToken)
    self.init(debugProvider: debugProvider, projectID: app.options.projectID,
              googleAppID: app.options.googleAppID)
  }

  init(debugProvider: AppCheckCoreDebugProvider, projectID: String?, googleAppID: String) {
    self.debugProvider = debugProvider
    self.projectID = projectID
    self.googleAppID = googleAppID
    debugTokenSource = debugProvider.debugTokenSource
    switch debugTokenSource {
    case .local:
      logDebugTokenMessage(code: "I-FAA003001", prefix: "")
    case .provided:
      logger.notice("""
      I-FAA003004: Debug token loaded from ~/\(AppCheckDebugTokenConfigStore.relativePath).
      """)
    case .environmentVariable:
      // AppCheckCore logs that the environment variable is used; the local token is unused.
      break
    }
  }

  /// Returns the locally generated token.
  public func localDebugToken() -> String {
    debugProvider.localDebugToken()
  }

  /// Returns the currently used App Check debug token. The priority:
  ///  - `FIRAAppCheckDebugToken` env variable value
  ///  - Simulator only: the token for the app's Google App ID in
  ///    `~/.config/configstore/firebase-appcheck.json` on the host machine, as provisioned by
  ///    `firebase appcheck:debugtokens:create`
  ///  - previously generated stored local token
  ///  - newly generated random token
  public func currentDebugToken() -> String {
    debugProvider.currentDebugToken()
  }

  public func getToken() async throws -> AppCheckToken {
    do {
      return try await debugProvider.publicToken()
    } catch {
      logDebugTokenExchangeError(error)
      throw error
    }
  }

  public func getLimitedUseToken() async throws -> AppCheckToken {
    do {
      return try await debugProvider.publicLimitedUseToken()
    } catch {
      logDebugTokenExchangeError(error)
      throw error
    }
  }

  private func logDebugTokenExchangeError(_ error: any Error) {
    if debugTokenSource == .local {
      logDebugTokenMessage(code: "I-FAA003003", prefix: "Failed to exchange debug token. ")
      return
    }
    guard let message = debugTokenExchangeFailureMessage(for: error) else { return }
    let code = debugTokenSource == .provided ? "I-FAA003005" : "I-FAA003003"
    logger.warning("\(code): \(message)")
  }

  /// The message to log when exchanging an environment variable or config store debug token
  /// fails, or `nil` when there's nothing actionable to report (e.g. the server was
  /// unreachable). Unlike the local token's registration instructions, these never include the
  /// token.
  func debugTokenExchangeFailureMessage(for error: any Error) -> String? {
    let nsError = error as NSError
    if nsError.domain == AppCheckCoreErrorDomain,
       nsError.code == AppCheckCoreErrorCode.serverUnreachable.rawValue {
      return nil
    }
    let projectArgument = projectID.map { $0.isEmpty ? "" : " --project \($0)" } ?? ""
    // App Check Core errors describe the failure in `NSLocalizedFailureReasonErrorKey`; using it
    // directly avoids Foundation's generic "The operation couldn’t be completed." prefix.
    let errorDescription = nsError.localizedFailureReason ?? nsError.localizedDescription
    switch debugTokenSource {
    case .provided:
      // The config store is only read at launch, so a new token requires relaunching the app.
      return """
      Failed to exchange the debug token loaded from \
      ~/\(AppCheckDebugTokenConfigStore.relativePath): \(errorDescription)

      If the token was rejected by the server, run \
      `firebase appcheck:debugtokens:create --force\(projectArgument) --app \(googleAppID)` to \
      provision a new token, then relaunch the app.
      """
    case .environmentVariable:
      return """
      Failed to exchange the debug token from the `AppCheckDebugToken` or \
      `FIRAAppCheckDebugToken` environment variable: \(errorDescription)

      Make sure the token is registered for app \(googleAppID), for example with \
      `firebase appcheck:debugtokens:create <token>\(projectArgument) --app \(googleAppID)`.
      """
    case .local:
      return nil
    }
  }

  private func logDebugTokenMessage(code: String, prefix: String) {
    guard let projectID, !projectID.isEmpty, !googleAppID.isEmpty else { return }
    let debugToken = localDebugToken()
    logger.warning("""
    \(code): \(prefix)To use this token for app debugging, register it with your project.

    Firebase App Check debug token: \(debugToken)

    You can do so in the Firebase Console:
    https://console.firebase.google.com/project/\(projectID)/appcheck/apps?selectedAppId=\(googleAppID)

    Or using the Firebase CLI:
    firebase appcheck:debugtokens:create \(debugToken) --project \(projectID) --app \(googleAppID)

    Note: To keep your project secure, please revoke and delete this token using the
    Firebase Console or the CLI (`firebase appcheck:debugtokens:delete`) when you finish \
    debugging.

    Warning: This debug token is a secret and should not be shared or uploaded to source code.

    Debug Token Guide: https://firebase.google.com/docs/app-check/ios/debug-provider
    Firebase CLI install instructions: https://firebase.google.com/docs/cli
    """)
  }
}

/// An implementation of `AppCheckProviderFactory` that creates a new instance of
/// `AppCheckDebugProvider` when requested.
///
/// NOTE: Do NOT use the debug provider factory in applications used by real users.
public final class AppCheckDebugProviderFactory: AppCheckProviderFactory {
  public init() {}

  public func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
    AppCheckDebugProvider(app: app)
  }
}
