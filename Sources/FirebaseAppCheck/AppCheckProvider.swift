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

/// A protocol for objects that can create Firebase App Check tokens.
public protocol AppCheckProvider: AnyObject, Sendable {
  /// Returns a new Firebase App Check token.
  func getToken() async throws -> AppCheckToken

  /// Returns a new Firebase App Check token suitable for consumption in a limited-use scenario.
  /// Upstream makes this optional; providers that don't implement it get `getToken()`, as
  /// upstream does for them.
  func getLimitedUseToken() async throws -> AppCheckToken
}

public extension AppCheckProvider {
  func getLimitedUseToken() async throws -> AppCheckToken {
    try await getToken()
  }
}

/// Implement this protocol to provide instances of a custom App Check provider for each
/// `FirebaseApp`, and pass it to `AppCheck.setAppCheckProviderFactory(_:keychain:)`.
public protocol AppCheckProviderFactory: AnyObject, Sendable {
  /// Creates a new instance of a Firebase App Check provider.
  /// - Parameter app: An instance of `FirebaseApp` to create the provider for.
  /// - Returns: A new instance implementing the `AppCheckProvider` protocol.
  func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)?
}

/// Adapts a public `AppCheckProvider` to AppCheckCore, as upstream's
/// `FIRInternalAppCheckProvider`.
final class InternalAppCheckProvider: NSObject, AppCheckCoreProvider, @unchecked Sendable {
  private let appCheckProvider: any AppCheckProvider

  init(appCheckProvider: any AppCheckProvider) {
    self.appCheckProvider = appCheckProvider
  }

  func getToken(completion: @escaping (AppCheckCoreToken?, Error?) -> Void) {
    nonisolated(unsafe) let completion = completion
    Task {
      do {
        completion(try await appCheckProvider.getToken().internalToken, nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  func getLimitedUseToken(completion: @escaping (AppCheckCoreToken?, Error?) -> Void) {
    nonisolated(unsafe) let completion = completion
    Task {
      do {
        completion(try await appCheckProvider.getLimitedUseToken().internalToken, nil)
      } catch {
        completion(nil, error)
      }
    }
  }
}

/// Adapts an AppCheckCore provider (debug, DeviceCheck, App Attest) to `AppCheckProvider`, for the
/// public providers that wrap one.
extension AppCheckCoreProvider {
  func publicToken() async throws -> AppCheckToken {
    AppCheckToken(internalToken: try await getToken())
  }

  func publicLimitedUseToken() async throws -> AppCheckToken {
    AppCheckToken(internalToken: try await getLimitedUseToken())
  }
}

/// The `FirebaseOptions` fields the token exchange needs, which are missing, as upstream's
/// `FIRAppCheckValidator`.
func tokenExchangeMissingFields(in options: FirebaseOptions) -> [String] {
  var missingFields: [String] = []
  if options.apiKey?.isEmpty ?? true {
    missingFields.append("APIKey")
  }
  if options.projectID?.isEmpty ?? true {
    missingFields.append("projectID")
  }
  if options.googleAppID.isEmpty {
    missingFields.append("googleAppID")
  }
  return missingFields
}

extension FirebaseApp {
  /// The App Check resource name of the app, as upstream's `FIRApp+AppCheck`.
  var appCheckResourceName: String {
    "projects/\(options.projectID ?? "")/apps/\(options.googleAppID)"
  }
}
