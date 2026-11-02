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

/// Completes a sign-in that needs a second factor. Read it from the `secondFactorRequired`
/// error's `AuthErrors.userInfoMultiFactorResolverKey`.
public final class MultiFactorResolver: @unchecked Sendable {
  /// The opaque session identifier for the current sign-in flow.
  public let session: MultiFactorSession

  /// The second factors the user can complete sign-in with.
  public let hints: [MultiFactorInfo]

  /// The Auth reference for the current MultiFactorResolver.
  public let auth: Auth

  /// Completes sign-in with a second factor, using a `MultiFactorAssertion` that confirms the
  /// user completed the second factor challenge: from `PhoneMultiFactorGenerator` or
  /// `TOTPMultiFactorGenerator.assertionForSignIn(withEnrollmentID:oneTimePassword:)`.
  public func resolveSignIn(with assertion: MultiFactorAssertion) async throws -> AuthDataResult {
    let request: FinalizeMFASignInRequest
    switch assertion {
    case let phoneAssertion as PhoneMultiFactorAssertion:
      let (verificationID, code) = try phoneAssertion.verification()
      request = FinalizeMFASignInRequest(
        mfaPendingCredential: mfaPendingCredential,
        verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo(sessionInfo: verificationID,
                                                               verificationCode: code),
        requestConfiguration: auth.requestConfiguration
      )
    case let totpAssertion as TOTPMultiFactorAssertion:
      guard case let .enrollmentID(enrollmentID) = totpAssertion.secretOrID else {
        throw AuthErrorUtils.error(code: .internalError,
                                   message: "TOTP sign-in needs an assertion with an enrollment ID.")
      }
      request = FinalizeMFASignInRequest(
        mfaPendingCredential: mfaPendingCredential,
        mfaEnrollmentID: enrollmentID,
        totpVerificationInfo: .init(verificationCode: totpAssertion.oneTimePassword),
        requestConfiguration: auth.requestConfiguration
      )
    default:
      throw AuthErrorUtils.error(code: .internalError,
                                 message: "Unsupported second factor: \(assertion.factorID).")
    }
    let response = try await AuthBackend.post(withRequest: request)
    guard let idToken = response.idToken, let refreshToken = response.refreshToken else {
      throw AuthErrorUtils.invalidUserTokenError(
        message: "Invalid user token: accessToken or refreshToken is nil"
      )
    }
    let user = try await auth.completeSignIn(withAccessToken: idToken,
                                             accessTokenExpirationDate: nil,
                                             refreshToken: refreshToken,
                                             anonymous: false)
    try await auth.updateCurrentUser(user)
    return AuthDataResult(withUser: user, additionalUserInfo: nil)
  }

  let mfaPendingCredential: String?

  init(with mfaPendingCredential: String?, hints: [MultiFactorInfo], auth: Auth) {
    self.mfaPendingCredential = mfaPendingCredential
    self.hints = hints
    self.auth = auth
    session = MultiFactorSession(mfaPendingCredential: mfaPendingCredential)
  }
}
