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
public final class AppCheckDebugProvider: AppCheckProvider, @unchecked Sendable {
  private let debugProvider: AppCheckCoreDebugProvider
  private let projectID: String?
  private let googleAppID: String

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
    let debugProvider = AppCheckCoreDebugProvider(serviceName: app.name,
                                                  resourceName: app.appCheckResourceName,
                                                  baseURL: nil,
                                                  apiKey: apiKey,
                                                  requestHooks: nil)
    self.init(debugProvider: debugProvider, projectID: app.options.projectID,
              googleAppID: app.options.googleAppID)
  }

  init(debugProvider: AppCheckCoreDebugProvider, projectID: String?, googleAppID: String) {
    self.debugProvider = debugProvider
    self.projectID = projectID
    self.googleAppID = googleAppID
    logDebugTokenMessage(code: "I-FAA003001", prefix: "")
  }

  /// Returns the locally generated token.
  public func localDebugToken() -> String {
    debugProvider.localDebugToken()
  }

  /// Returns the currently used App Check debug token. The priority:
  ///  - `FIRAAppCheckDebugToken` env variable value
  ///  - previously generated stored local token
  ///  - newly generated random token
  public func currentDebugToken() -> String {
    debugProvider.currentDebugToken()
  }

  public func getToken() async throws -> AppCheckToken {
    do {
      return try await debugProvider.publicToken()
    } catch {
      logDebugTokenExchangeError()
      throw error
    }
  }

  public func getLimitedUseToken() async throws -> AppCheckToken {
    do {
      return try await debugProvider.publicLimitedUseToken()
    } catch {
      logDebugTokenExchangeError()
      throw error
    }
  }

  private func logDebugTokenExchangeError() {
    logDebugTokenMessage(code: "I-FAA003003", prefix: "Failed to exchange debug token. ")
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
