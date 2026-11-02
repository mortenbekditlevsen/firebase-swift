// Copyright 2023 Google LLC
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
#if os(iOS)
  import Foundation
  import Synchronization
  import UIKit

  protocol AuthAPNSTokenApplication: Sendable {
    @MainActor func registerForRemoteNotifications()
  }

  extension UIApplication: AuthAPNSTokenApplication {}

  /// Gets the APNs token phone auth sends to the backend.
  ///
  /// There's no app delegate swizzling in this port: the app passes the token to
  /// `Auth.setAPNSToken(_:type:)` from
  /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
  final class AuthAPNSTokenManager: Sendable {
    /// The timeout for registering for remote notifications.
    let timeout: TimeInterval

    let application: AuthAPNSTokenApplication

    private struct State {
      var token: AuthAPNSToken?
      var pending: [CheckedContinuation<AuthAPNSToken, Error>] = []
      /// Bumped by each registration, so a timer only cancels its own.
      var generation = 0
    }

    private let state = Mutex(State())

    init(withApplication application: AuthAPNSTokenApplication, timeout: TimeInterval = 5) {
      self.application = application
      self.timeout = timeout
    }

    /// Returns the APNs token, registering for remote notifications if there's none yet.
    /// Throws `missingAppToken` if no token arrives within `timeout`.
    func getToken() async throws -> AuthAPNSToken {
      try await withCheckedThrowingContinuation { continuation in
        enum Action { case resume(AuthAPNSToken), wait, register(Int) }
        let action: Action = state.withLock { state in
          if let token = state.token {
            return .resume(token)
          }
          state.pending.append(continuation)
          guard state.pending.count == 1 else { return .wait }
          state.generation += 1
          return .register(state.generation)
        }
        switch action {
        case let .resume(token):
          continuation.resume(returning: token)
        case .wait:
          break
        case let .register(generation):
          let application = self.application
          Task { @MainActor in application.registerForRemoteNotifications() }
          kAuthGlobalWorkQueue.asyncAfter(deadline: .now() + timeout) {
            let expired = self.state.withLock { state -> [CheckedContinuation<AuthAPNSToken, Error>] in
              guard state.generation == generation else { return [] }
              defer { state.pending = [] }
              return state.pending
            }
            let error = AuthErrorUtils.missingAppTokenError(underlyingError: nil)
            for continuation in expired {
              continuation.resume(throwing: error)
            }
          }
        }
      }
    }

    /// The APNs token, if one is available.
    ///
    /// Setting a token of type `unknown` detects the type from the provisioning profile.
    var token: AuthAPNSToken? {
      get { state.withLock { $0.token } }
      set {
        guard var token = newValue else {
          state.withLock { $0.token = nil }
          return
        }
        if token.type == .unknown {
          token = AuthAPNSToken(withData: token.data,
                                type: Self.isProductionApp() ? .prod : .sandbox)
        }
        let waiting = state.withLock { [token] state in
          state.token = token
          defer { state.pending = [] }
          return state.pending
        }
        for continuation in waiting {
          continuation.resume(returning: token)
        }
      }
    }

    /// Fails any pending `getToken()` calls with `error`.
    func cancel(withError error: Error) {
      let waiting = state.withLock { state in
        defer { state.pending = [] }
        return state.pending
      }
      for continuation in waiting {
        continuation.resume(throwing: error)
      }
    }

    private static func isProductionApp() -> Bool {
      let defaultAppTypeProd = true
      #if targetEnvironment(simulator)
        AuthLog.logInfo(code: "I-AUT000006", message: "Assuming prod APNs token type on simulator.")
        return defaultAppTypeProd
      #else
        // App Store builds have no embedded provisioning profile, so they take the default
        // below. (Upstream checks for them first through GoogleUtilities.)

        // TODO: resolve https://github.com/firebase/firebase-ios-sdk/issues/10921
        // to support TestFlight

        let path = Bundle.main.bundlePath + "/" + "embedded.mobileprovision"
        let profileData: Data
        do {
          profileData = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
          AuthLog.logInfo(code: "I-AUT000008",
                          message: "Error while reading embedded mobileprovision \(error)")
          return defaultAppTypeProd
        }

        // The "embedded.mobileprovision" sometimes contains characters with value 0, which signals
        // the end of a c-string and halts the ASCII parser, or with value > 127, which violates
        // strict 7-bit ASCII. Replace any 0s or invalid characters in the input.
        let bytes = profileData.map { $0 == 0 || $0 > 127 ? 46 /* ASCII '.' */ : $0 }
        guard let embeddedProfile = String(bytes: bytes, encoding: .utf8) else {
          AuthLog.logInfo(code: "I-AUT000008",
                          message: "Error while reading embedded mobileprovision. " +
                            "Failed to convert to String")
          return defaultAppTypeProd
        }

        guard let start = embeddedProfile.range(of: "<plist"),
              let end = embeddedProfile.range(of: "</plist>", range: start.lowerBound ..< embeddedProfile.endIndex)
        else {
          return defaultAppTypeProd
        }
        let plistContents = embeddedProfile[start.lowerBound ..< end.upperBound]
        do {
          let plistData = try PropertyListSerialization.propertyList(from: Data(plistContents.utf8),
                                                                     format: nil)
          guard let plistMap = plistData as? [String: Any] else {
            AuthLog.logInfo(code: "I-AUT000008",
                            message: "Error while converting assumed plist to dictionary.")
            return defaultAppTypeProd
          }
          if plistMap["ProvisionedDevices"] != nil {
            AuthLog.logInfo(code: "I-AUT000011",
                            message: "Provisioning profile has specifically provisioned devices, " +
                              "most likely a Dev profile.")
          }
          guard let entitlements = plistMap["Entitlements"] as? [String: Any],
                let apsEnvironment = entitlements["aps-environment"] as? String else {
            AuthLog.logInfo(code: "I-AUT000013",
                            message: "No aps-environment set. If testing on a device APNS is not " +
                              "correctly configured. Please recheck your provisioning profiles.")
            return defaultAppTypeProd
          }
          AuthLog.logDebug(code: "I-AUT000012",
                           message: "APNS Environment in profile: \(apsEnvironment)")
          return apsEnvironment != "development"
        } catch {
          AuthLog.logInfo(code: "I-AUT000008",
                          message: "Error while converting assumed plist to dict " +
                            "\(error.localizedDescription)")
          return defaultAppTypeProd
        }
      #endif
    }
  }
#endif
