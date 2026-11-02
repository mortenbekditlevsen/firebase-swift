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
  /** @class FIRPhoneMultiFactorAssertion
   @brief The subclass of base class FIRMultiFactorAssertion, used to assert ownership of a phone
       second factor.
       This class is available on iOS only.
   */
  @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
  
  public class MultiFactorResolver {
    /**
        @brief The opaque session identifier for the current sign-in flow.
     */
    public let session: MultiFactorSession

    /**
        @brief The list of hints for the second factors needed to complete the sign-in for the current
            session.
     */
    public let hints: [MultiFactorInfo]

    /**
        @brief The Auth reference for the current FIRMultiResolver.
     */
    public let auth: Auth

    /// Completes sign-in with a second factor, using a `MultiFactorAssertion` that confirms the
    /// user completed the second factor challenge.
    public func resolveSignIn(with assertion: MultiFactorAssertion) async throws -> AuthDataResult {
      let phoneAssertion = assertion as? PhoneMultiFactorAssertion
      guard let credential = phoneAssertion?.authCredential,
            case let .verification(verificationID, code) = credential.credentialKind else {
        throw AuthErrorUtils.error(code: .internalError,
                                   message: "A phone assertion needs a verification code.")
      }
      let request = FinalizeMFASignInRequest(
        mfaPendingCredential: mfaPendingCredential,
        verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo(sessionInfo: verificationID,
                                                               verificationCode: code),
        requestConfiguration: auth.requestConfiguration
      )
      let response = try await AuthBackend.post(withRequest: request)
      guard let idToken = response.idToken, let refreshToken = response.refreshToken else {
        throw AuthErrorUtils.unexpectedResponse(deserializedResponse: response)
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
      session = MultiFactorSession()
      session.mfaPendingCredential = mfaPendingCredential
    }
  }

#endif
