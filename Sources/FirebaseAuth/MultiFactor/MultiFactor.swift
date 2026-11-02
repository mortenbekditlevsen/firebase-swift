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
import Foundation

/// The second factors of a user, and the operations to change them.
public final class MultiFactor: @unchecked Sendable {
  /// The user's second factors.
  public let enrolledFactors: [MultiFactorInfo]

  /// Gets a session for enrolling a second factor.
  public func session() async throws -> MultiFactorSession {
    // The port took the default app's current user (fixed upstream in #14238).
    guard let user else {
      throw AuthErrorUtils.nullUserError(message: nil)
    }
    return try await MultiFactorSession(enrolling: user, idToken: user.internalGetToken())
  }

  /// Enrolls a second factor as identified by the `MultiFactorAssertion` parameter for the
  /// current user.
  /// - Parameter assertion: The second factor to enroll: from `PhoneMultiFactorGenerator` or
  ///   `TOTPMultiFactorGenerator.assertionForEnrollment(with:oneTimePassword:)`.
  /// - Parameter displayName: An optional display name associated with the multi factor to enroll.
  public func enroll(with assertion: MultiFactorAssertion, displayName: String?) async throws {
    guard let user else {
      throw AuthErrorUtils.nullUserError(message: nil)
    }
    let request: FinalizeMFAEnrollmentRequest
    switch assertion {
    case let phoneAssertion as PhoneMultiFactorAssertion:
      let (verificationID, code) = try phoneAssertion.verification()
      request = FinalizeMFAEnrollmentRequest(
        idToken: user.rawAccessToken(),
        displayName: displayName,
        verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo(sessionInfo: verificationID,
                                                               verificationCode: code),
        requestConfiguration: user.requestConfiguration
      )
    case let totpAssertion as TOTPMultiFactorAssertion:
      guard case let .secret(secret) = totpAssertion.secretOrID else {
        throw AuthErrorUtils.error(code: .internalError,
                                   message: "Enrolling TOTP needs an assertion with a secret.")
      }
      request = FinalizeMFAEnrollmentRequest(
        idToken: user.rawAccessToken(),
        displayName: displayName,
        totpVerificationInfo: .init(sessionInfo: secret.sessionInfo,
                                    verificationCode: totpAssertion.oneTimePassword),
        requestConfiguration: user.requestConfiguration
      )
    default:
      throw AuthErrorUtils.error(code: .internalError,
                                 message: "Unsupported second factor: \(assertion.factorID).")
    }
    let response = try await AuthBackend.post(withRequest: request)
    try await completeSignIn(user, idToken: response.idToken, refreshToken: response.refreshToken)
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
    try await completeSignIn(user, idToken: response.idToken, refreshToken: response.refreshToken)
  }

  /// Continues the session with the tokens the backend returns after a change of factors.
  /// The old tokens are revoked by then, so a failure signs the user out, as upstream does.
  private func completeSignIn(_ user: User, idToken: String?, refreshToken: String?) async throws {
    guard let auth = user.auth else {
      throw AuthErrorUtils.nullUserError(message: nil)
    }
    guard let idToken, let refreshToken else {
      // Upstream #14663.
      throw AuthErrorUtils.invalidUserTokenError(
        message: "Invalid user token: accessToken or refreshToken is nil"
      )
    }
    do {
      let user = try await auth.completeSignIn(withAccessToken: idToken,
                                               accessTokenExpirationDate: nil,
                                               refreshToken: refreshToken,
                                               anonymous: false)
      // The port dropped the new user, so the current one kept its old factors.
      try await auth.updateCurrentUser(user)
    } catch {
      try? auth.signOut()
      throw error
    }
  }

  weak var user: User?

  /// A view of `user`'s enrollments. Enrollments that can't be read are skipped.
  init(user: User?, enrollments: [AuthProtoMFAEnrollment]) {
    self.user = user
    enrolledFactors = enrollments.compactMap(MultiFactorInfo.info(for:))
  }
}
