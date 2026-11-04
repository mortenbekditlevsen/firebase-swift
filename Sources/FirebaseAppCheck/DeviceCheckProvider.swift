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

#if canImport(DeviceCheck)

  import FirebaseCore
  import Foundation

  /// Firebase App Check provider that verifies app integrity using the
  /// [DeviceCheck](https://developer.apple.com/documentation/devicecheck/dcdevice) API.
  /// This class is available on all platforms for select OS versions. See
  /// https://firebase.google.com/docs/ios/learn-more for more details.
  public final class DeviceCheckProvider: AppCheckProvider, @unchecked Sendable {
    private let deviceCheckProvider: AppCheckCoreDeviceCheckProvider

    /// The default initializer.
    /// - Parameter app: A `FirebaseApp` instance.
    /// - Returns: An instance of `DeviceCheckProvider` if the provided `FirebaseApp` instance
    ///   contains all required parameters.
    public init?(app: FirebaseApp) {
      let missingFields = tokenExchangeMissingFields(in: app.options)
      guard missingFields.isEmpty, let apiKey = app.options.apiKey else {
        logger.error("""
        I-FAA004001: Cannot instantiate `FIRDeviceCheckProvider` for app: \(app.name). The \
        following `FirebaseOptions` fields are missing: \(missingFields.joined(separator: ", "))
        """)
        return nil
      }
      deviceCheckProvider = AppCheckCoreDeviceCheckProvider(serviceName: app.name,
                                                            resourceName: app.appCheckResourceName,
                                                            apiKey: apiKey,
                                                            requestHooks: nil)
    }

    public func getToken() async throws -> AppCheckToken {
      try await deviceCheckProvider.publicToken()
    }

    public func getLimitedUseToken() async throws -> AppCheckToken {
      try await deviceCheckProvider.publicLimitedUseToken()
    }
  }

  /// An implementation of `AppCheckProviderFactory` that creates a new instance of
  /// `DeviceCheckProvider` when requested.
  public final class DeviceCheckProviderFactory: AppCheckProviderFactory {
    public init() {}

    public func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
      DeviceCheckProvider(app: app)
    }
  }

  /// Firebase App Check provider that verifies app integrity using the
  /// [DeviceCheck](https://developer.apple.com/documentation/devicecheck/dcappattestservice) API.
  /// This class is available on all platforms for select OS versions. See
  /// https://firebase.google.com/docs/ios/learn-more for more details.
  public final class AppAttestProvider: AppCheckProvider, @unchecked Sendable {
    private let appAttestProvider: AppCheckCoreAppAttestProvider

    /// The default initializer.
    /// - Parameter app: A `FirebaseApp` instance.
    /// - Returns: An instance of `AppAttestProvider` if the provided `FirebaseApp` instance
    ///   contains all required parameters.
    public init?(app: FirebaseApp) {
      // The artifact goes where App Check's token does.
      let keychain = AppCheck.keychain ?? AppCheckSystemKeychain()
      appAttestProvider = AppCheckCoreAppAttestProvider(serviceName: app.name,
                                                        resourceName: app.appCheckResourceName,
                                                        baseURL: nil,
                                                        apiKey: app.options.apiKey,
                                                        keychain: keychain,
                                                        keychainAccessGroup: app.options.appGroupID,
                                                        requestHooks: nil)
    }

    public func getToken() async throws -> AppCheckToken {
      try await appAttestProvider.publicToken()
    }

    public func getLimitedUseToken() async throws -> AppCheckToken {
      try await appAttestProvider.publicLimitedUseToken()
    }
  }

  /// An implementation of `AppCheckProviderFactory` that creates a new instance of
  /// `AppAttestProvider` when requested.
  public final class AppAttestProviderFactory: AppCheckProviderFactory {
    public init() {}

    public func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
      AppAttestProvider(app: app)
    }
  }

#endif // canImport(DeviceCheck)
