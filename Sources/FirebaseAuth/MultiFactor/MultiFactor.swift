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

#if os(iOS)

  /** @class FIRMultiFactor
   @brief The interface defining the multi factor related properties and operations pertaining to a
       user.
       This class is available on iOS only.
   */
  @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
   public class MultiFactor {
    public var enrolledFactors: [MultiFactorInfo]?

    /// Gets a session for a second factor enrollment operation. It identifies the current user
    /// trying to enroll a second factor.
    public func session() async throws -> MultiFactorSession {
      // The port took the default app's current user (fixed upstream in #14238).
      guard let user else {
        throw AuthErrorUtils.nullUserError(message: nil)
      }
      return MultiFactorSession(idToken: try await user.internalGetToken())
    }

    /// Enrolls a second factor as identified by the `MultiFactorAssertion` parameter for the
    /// current user.
    /// - Parameter assertion: The second factor to enroll.
    /// - Parameter displayName: An optional display name associated with the multi factor to enroll.
    public func enroll(with assertion: MultiFactorAssertion, displayName: String?) async throws {
      let phoneAssertion = assertion as? PhoneMultiFactorAssertion
      guard let credential = phoneAssertion?.authCredential,
            case let .verification(verificationID, code) = credential.credentialKind else {
        throw AuthErrorUtils.error(code: .internalError,
                                   message: "A phone assertion needs a verification code.")
      }
      guard let user else {
        throw AuthErrorUtils.nullUserError(message: nil)
      }
      let request = FinalizeMFAEnrollmentRequest(
        idToken: user.rawAccessToken(),
        displayName: displayName,
        verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo(sessionInfo: verificationID,
                                                               verificationCode: code),
        requestConfiguration: user.requestConfiguration
      )
      let response = try await AuthBackend.post(withRequest: request)
      try await completeSignIn(user, idToken: response.idToken, refreshToken: response.refreshToken,
                               signOutOnFailure: true, response: response)
    }

    /// Unenrolls the given second factor.
    public func unenroll(with factorInfo: MultiFactorInfo) async throws {
      try await unenroll(withFactorUID: factorInfo.uid)
    }

    /// Unenrolls the second factor with the given UID.
    public func unenroll(withFactorUID factorUID: String) async throws {
      guard let user else {
        throw AuthErrorUtils.nullUserError(message: nil)
      }
      let request = WithdrawMFARequest(idToken: user.rawAccessToken(),
                                       mfaEnrollmentID: factorUID,
                                       requestConfiguration: user.requestConfiguration)
      let response = try await AuthBackend.post(withRequest: request)
      try await completeSignIn(user, idToken: response.idToken, refreshToken: response.refreshToken,
                               signOutOnFailure: false, response: response)
    }

    /// Continues the session with the tokens the backend returns after a change of factors.
    private func completeSignIn(_ user: User, idToken: String?, refreshToken: String?,
                                signOutOnFailure: Bool, response: Any) async throws {
      guard let auth = user.auth else {
        throw AuthErrorUtils.nullUserError(message: nil)
      }
      guard let idToken, let refreshToken else {
        throw AuthErrorUtils.unexpectedResponse(deserializedResponse: response)
      }
      do {
        let user = try await auth.completeSignIn(withAccessToken: idToken,
                                                 accessTokenExpirationDate: nil,
                                                 refreshToken: refreshToken,
                                                 anonymous: false)
        // The port dropped the new user, so the current one kept its old factors.
        try await auth.updateCurrentUser(user)
      } catch {
        if signOutOnFailure {
          try? auth.signOut()
        }
        throw error
      }
    }

    weak var user: User?

    /// A view of `user`'s enrollments. Enrollments that can't be read are skipped.
    init(user: User?, enrollments: [AuthProtoMFAEnrollment]) {
      self.user = user
      enrolledFactors = enrollments.compactMap { PhoneMultiFactorInfo(proto: $0) }
    }
  }

#endif
