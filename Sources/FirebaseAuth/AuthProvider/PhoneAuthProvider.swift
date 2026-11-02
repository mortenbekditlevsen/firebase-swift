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
import Foundation

/// A concrete implementation of `AuthProvider` for phone auth providers.
///
/// This type is available on iOS only.
///
/// There's no app delegate swizzling in this port. For phone auth to work, the app passes
/// - the APNs token to `Auth.setAPNSToken(_:type:)`,
/// - remote notifications to `Auth.canHandleNotification(_:)`, and
/// - opened URLs to `Auth.canHandle(_:)` (for the reCAPTCHA fallback).
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
public struct PhoneAuthProvider: Sendable {
  public static let id = "phone"

  #if os(iOS)
    /// Returns an instance of `PhoneAuthProvider` for the default `Auth` object.
    public static func provider() -> PhoneAuthProvider {
      PhoneAuthProvider(auth: Auth.auth())
    }

    /// Returns an instance of `PhoneAuthProvider` for the provided `Auth` object.
    /// - Parameter auth: The auth object to associate with the phone auth provider instance.
    public static func provider(auth: Auth) -> PhoneAuthProvider {
      PhoneAuthProvider(auth: auth)
    }

    /// Starts the phone number authentication flow by sending a verification code to the
    /// specified phone number.
    ///
    /// Possible error codes:
    /// * `AuthErrorCodeCaptchaCheckFailed` - Indicates that the reCAPTCHA token obtained by
    /// the Firebase Auth is invalid or has expired.
    /// * `AuthErrorCodeQuotaExceeded` - Indicates that the phone verification quota for this
    /// project has been exceeded.
    /// * `AuthErrorCodeInvalidPhoneNumber` - Indicates that the phone number provided is invalid.
    /// * `AuthErrorCodeMissingPhoneNumber` - Indicates that a phone number was not provided.
    /// - Parameter phoneNumber: The phone number to be verified.
    /// - Parameter uiDelegate: An object used to present the `SFSafariViewController`.
    /// - Parameter multiFactorSession: The session for second factor enrollment or sign-in.
    /// - Returns: The verification ID.
    public func verifyPhoneNumber(_ phoneNumber: String,
                                  uiDelegate: AuthUIDelegate? = nil,
                                  multiFactorSession: MultiFactorSession? = nil) async throws
      -> String {
      guard AuthWebUtils.isCallbackSchemeRegistered(forCustomURLScheme: callbackScheme,
                                                    urlTypes: auth.mainBundleUrlTypes ?? []) else {
        fatalError(
          "Please register custom URL scheme \(callbackScheme) in the app's Info.plist file."
        )
      }
      guard let verificationID = try await internalVerify(phoneNumber: phoneNumber,
                                                          uiDelegate: uiDelegate,
                                                          multiFactorSession: multiFactorSession)
      else {
        throw AuthErrorUtils.invalidVerificationIDError(message: "Invalid verification ID")
      }
      return verificationID
    }

    /// Verifies ownership of a second factor phone number by sending it a verification code.
    /// - Parameter multiFactorInfo: The phone multi factor whose number needs verification.
    /// - Parameter uiDelegate: An object used to present the `SFSafariViewController`.
    /// - Parameter multiFactorSession: A session to identify the MFA flow.
    /// - Returns: The verification ID.
    public func verifyPhoneNumber(with multiFactorInfo: PhoneMultiFactorInfo,
                                  uiDelegate: AuthUIDelegate? = nil,
                                  multiFactorSession: MultiFactorSession?) async throws -> String {
      multiFactorSession?.multiFactorInfo = multiFactorInfo
      return try await verifyPhoneNumber(multiFactorInfo.phoneNumber,
                                         uiDelegate: uiDelegate,
                                         multiFactorSession: multiFactorSession)
    }

    /// Creates a `PhoneAuthCredential` for the verification ID and code.
    /// - Parameter verificationID: The verification ID obtained from invoking
    /// `verifyPhoneNumber(_:uiDelegate:multiFactorSession:)`.
    /// - Parameter verificationCode: The verification code obtained from the user.
    public func credential(withVerificationID verificationID: String,
                           verificationCode: String) -> PhoneAuthCredential {
      PhoneAuthCredential(verificationID: verificationID, verificationCode: verificationCode)
    }

    // MARK: Private

    /// How the app proves its identity when asking for a code.
    private enum CodeIdentity {
      case credential(AuthAppCredential)
      case recaptcha(String)
      /// In test mode.
      case empty

      var appCredential: AuthAppCredential? {
        if case let .credential(credential) = self { credential } else { nil }
      }

      var reCAPTCHAToken: String? {
        if case let .recaptcha(token) = self { token } else { nil }
      }
    }

    private func internalVerify(phoneNumber: String,
                                uiDelegate: AuthUIDelegate?,
                                multiFactorSession: MultiFactorSession?) async throws -> String? {
      guard !phoneNumber.isEmpty else {
        throw AuthErrorUtils.missingPhoneNumberError(message: nil)
      }
      guard let manager = auth.notificationManager,
            await manager.checkNotificationForwarding() else {
        throw AuthErrorUtils.notificationNotForwardedError()
      }
      // Upstream asks the backend whether reCAPTCHA Enterprise is on for phone auth first.
      // That isn't ported: this is upstream's flow for when it's off.
      return try await verifyClAndSendVerificationCode(toPhoneNumber: phoneNumber,
                                                       retryOnInvalidAppCredential: true,
                                                       multiFactorSession: multiFactorSession,
                                                       uiDelegate: uiDelegate)
    }

    private func verifyClAndSendVerificationCode(toPhoneNumber phoneNumber: String,
                                                 retryOnInvalidAppCredential: Bool,
                                                 multiFactorSession session: MultiFactorSession?,
                                                 uiDelegate: AuthUIDelegate?) async throws
      -> String? {
      let codeIdentity: CodeIdentity
      if auth.settings?.isAppVerificationDisabledForTesting == true {
        codeIdentity = .empty
      } else {
        codeIdentity = try await verifyClient(withUIDelegate: uiDelegate)
      }
      do {
        guard let session else {
          let request = SendVerificationCodeRequest(
            phoneNumber: phoneNumber,
            appCredential: codeIdentity.appCredential,
            reCAPTCHAToken: codeIdentity.reCAPTCHAToken,
            requestConfiguration: auth.requestConfiguration
          )
          return try await AuthBackend.post(withRequest: request).verificationID
        }
        let startMFARequestInfo = AuthProtoStartMFAPhoneRequestInfo(
          phoneNumber: phoneNumber,
          appCredential: codeIdentity.appCredential,
          reCAPTCHAToken: codeIdentity.reCAPTCHAToken
        )
        return try await executeMFARequest(startMFARequestInfo: startMFARequestInfo,
                                           multiFactorSession: session)
      } catch {
        if case .empty = codeIdentity { throw error }
        guard (error as NSError).code == AuthErrorCode.invalidAppCredential.rawValue else {
          throw error
        }
        guard retryOnInvalidAppCredential else {
          throw AuthErrorUtils.unexpectedResponse(deserializedResponse: nil, underlyingError: error)
        }
        auth.appCredentialManager?.clearCredential()
        return try await verifyClAndSendVerificationCode(toPhoneNumber: phoneNumber,
                                                         retryOnInvalidAppCredential: false,
                                                         multiFactorSession: session,
                                                         uiDelegate: uiDelegate)
      }
    }

    private func executeMFARequest(startMFARequestInfo: AuthProtoStartMFAPhoneRequestInfo,
                                   multiFactorSession session: MultiFactorSession) async throws
      -> String? {
      guard let idToken = session.idToken else {
        let request = StartMFASignInRequest(
          MFAPendingCredential: session.mfaPendingCredential,
          MFAEnrollmentID: session.multiFactorInfo?.uid,
          signInInfo: startMFARequestInfo,
          requestConfiguration: auth.requestConfiguration
        )
        return try await AuthBackend.post(withRequest: request).responseInfo?.sessionInfo
      }
      let request = StartMFAEnrollmentRequest(
        idToken: idToken,
        enrollmentInfo: startMFARequestInfo,
        requestConfiguration: auth.requestConfiguration
      )
      return try await AuthBackend.post(withRequest: request).phoneSessionInfo?.sessionInfo
    }

    /// Proves the app's identity with an APNs-delivered app credential, falling back to
    /// reCAPTCHA in the simulator or when no notification arrives.
    private func verifyClient(withUIDelegate uiDelegate: AuthUIDelegate?) async throws
      -> CodeIdentity {
      // Remove the simulator check below after FCM supports APNs in simulators
      #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
          return try await .recaptcha(reCAPTCHAFlow(withUIDelegate: uiDelegate))
        }
      #endif
      guard let appCredentialManager = auth.appCredentialManager,
            let tokenManager = auth.tokenManager else {
        return try await .recaptcha(reCAPTCHAFlow(withUIDelegate: uiDelegate))
      }
      if let credential = appCredentialManager.credential {
        return .credential(credential)
      }
      let token: AuthAPNSToken
      do {
        token = try await tokenManager.getToken()
      } catch {
        return try await .recaptcha(reCAPTCHAFlow(withUIDelegate: uiDelegate))
      }
      let request = VerifyClientRequest(withAppToken: token.string,
                                        isSandbox: token.type == .sandbox,
                                        requestConfiguration: auth.requestConfiguration)
      let response: VerifyClientResponse
      do {
        response = try await AuthBackend.post(withRequest: request)
      } catch {
        let code = (error as NSError).code
        // reCAPTCHA Flow if it's an invalid app credential or a missing app token.
        guard code == AuthErrorCode.invalidAppCredential.rawValue ||
          code == AuthErrorCode.missingAppToken.rawValue else {
          throw error
        }
        return try await .recaptcha(reCAPTCHAFlow(withUIDelegate: uiDelegate))
      }
      guard let receipt = response.receipt, let timeout = response.suggestedTimeout else {
        throw AuthErrorUtils.unexpectedResponse(deserializedResponse: nil, underlyingError: nil)
      }
      let credential = await appCredentialManager.didStartVerification(withReceipt: receipt,
                                                                      timeout: timeout)
      guard credential.secret != nil else {
        AuthLog.logWarning(code: "I-AUT000014", message: "Failed to receive remote " +
          "notification to verify app identity within \(timeout) " +
          "second(s), falling back to reCAPTCHA verification.")
        return try await .recaptcha(reCAPTCHAFlow(withUIDelegate: uiDelegate))
      }
      return .credential(credential)
    }

    private func reCAPTCHAFlow(withUIDelegate uiDelegate: AuthUIDelegate?) async throws -> String {
      let eventID = AuthWebUtils.randomString(withLength: 43)
      let url = try await reCAPTCHAURL(withEventID: eventID)
      let callbackScheme = self.callbackScheme
      let callbackURL = try await auth.authURLPresenter.present(
        url,
        uiDelegate: uiDelegate
      ) { callbackURL in
        AuthWebUtils.isExpectedCallbackURL(callbackURL,
                                           eventID: eventID,
                                           authType: Self.kAuthTypeVerifyApp,
                                           callbackScheme: callbackScheme)
      }
      return try reCAPTCHAToken(forURL: callbackURL)
    }

    /// Parses the reCAPTCHA token from the callback URL.
    private func reCAPTCHAToken(forURL url: URL) throws -> String {
      let actualURLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
      guard let queryItems = actualURLComponents?.queryItems,
            let deepLinkURL = AuthWebUtils.queryItemValue(name: "deep_link_id", from: queryItems)
      else {
        let reason = "Failed to get url Components for url: \(url)"
        throw AuthErrorUtils.appVerificationUserInteractionFailure(reason: reason)
      }
      if let queryItems = URLComponents(string: deepLinkURL)?.queryItems {
        if let token = AuthWebUtils.queryItemValue(name: "recaptchaToken", from: queryItems) {
          return token
        }
        if let firebaseError = AuthWebUtils.queryItemValue(name: "firebaseError",
                                                           from: queryItems) {
          let errorDict: [String: Any]?
          do {
            errorDict = try JSONSerialization.jsonObject(with: Data(firebaseError.utf8))
              as? [String: Any]
          } catch {
            throw AuthErrorUtils.JSONSerializationError(underlyingError: error)
          }
          if let code = errorDict?["code"] as? String,
             let message = errorDict?["message"] as? String {
            throw AuthErrorUtils.urlResponseError(code: code, message: message)
          }
        }
      }
      let reason = "An unknown error occurred with the following response: \(deepLinkURL)"
      throw AuthErrorUtils.appVerificationUserInteractionFailure(reason: reason)
    }

    private func reCAPTCHAURL(withEventID eventID: String) async throws -> URL {
      let requestConfiguration = auth.requestConfiguration
      let authDomain = try await AuthWebUtils
        .fetchAuthDomain(withRequestConfiguration: requestConfiguration)
      var queryItems = [URLQueryItem(name: "apiKey", value: requestConfiguration.apiKey),
                        URLQueryItem(name: "authType", value: Self.kAuthTypeVerifyApp),
                        URLQueryItem(name: "ibi", value: Bundle.main.bundleIdentifier ?? ""),
                        URLQueryItem(name: "v", value: AuthBackend.authUserAgent()),
                        URLQueryItem(name: "eventId", value: eventID)]
      if usingClientIDScheme {
        queryItems.append(URLQueryItem(name: "clientId", value: auth.app?.options.clientID))
      } else {
        queryItems.append(URLQueryItem(name: "appId", value: auth.app?.options.googleAppID))
      }
      if let languageCode = requestConfiguration.languageCode {
        queryItems.append(URLQueryItem(name: "hl", value: languageCode))
      }
      // Upstream adds an App Check token as the fragment; App Check isn't ported.
      var components = URLComponents(string: "https://\(authDomain)/__/auth/handler")
      components?.queryItems = queryItems
      guard let url = components?.url else {
        throw AuthErrorUtils.appVerificationUserInteractionFailure(
          reason: "Invalid reCAPTCHA URL for auth domain \(authDomain)"
        )
      }
      return url
    }

    private static let kAuthTypeVerifyApp = "verifyApp"

    private let auth: Auth
    private let callbackScheme: String
    private let usingClientIDScheme: Bool

    init(auth: Auth) {
      self.auth = auth
      if let clientID = auth.app?.options.clientID {
        let reverseClientIDScheme = clientID.components(separatedBy: ".").reversed()
          .joined(separator: ".")
        if AuthWebUtils.isCallbackSchemeRegistered(forCustomURLScheme: reverseClientIDScheme,
                                                   urlTypes: auth.mainBundleUrlTypes ?? []) {
          callbackScheme = reverseClientIDScheme
          usingClientIDScheme = true
          return
        }
      }
      usingClientIDScheme = false
      if let appID = auth.app?.options.googleAppID {
        let dashedAppID = appID.replacingOccurrences(of: ":", with: "-")
        callbackScheme = "app-\(dashedAppID)"
        return
      }
      callbackScheme = ""
    }
  #endif
}
