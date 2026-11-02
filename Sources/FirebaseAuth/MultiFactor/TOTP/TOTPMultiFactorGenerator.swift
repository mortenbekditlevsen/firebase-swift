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

/// Creates TOTP secrets and assertions.
public enum TOTPMultiFactorGenerator {
  /// Creates a TOTP secret to enroll as a second factor.
  /// - Parameter session: The session from `MultiFactor.session()`.
  public static func generateSecret(with session: MultiFactorSession) async throws
    -> TOTPSecret {
    guard let user = session.user, let idToken = session.idToken else {
      throw AuthErrorUtils.error(code: .internalError, message: "Invalid ID token.")
    }
    let request = StartMFAEnrollmentRequest(idToken: idToken,
                                            totpEnrollmentInfo: .init(),
                                            requestConfiguration: user.requestConfiguration)
    let response = try await AuthBackend.post(withRequest: request)
    guard let info = response.totpSessionInfo else {
      throw AuthErrorUtils.error(code: .internalError, message: "Error generating TOTP secret.")
    }
    return TOTPSecret(secretKey: info.sharedSecretKey,
                      hashingAlgorithm: info.hashingAlgorithm,
                      codeLength: info.verificationCodeLength,
                      codeIntervalSeconds: info.periodSec,
                      enrollmentCompletionDeadline: info.finalizeEnrollmentTime,
                      sessionInfo: info.sessionInfo)
  }

  /// The assertion for enrolling the TOTP second factor of `secret`.
  /// - Parameter oneTimePassword: A code from the authenticator app.
  public static func assertionForEnrollment(with secret: TOTPSecret,
                                            oneTimePassword: String) -> TOTPMultiFactorAssertion {
    TOTPMultiFactorAssertion(secretOrID: .secret(secret), oneTimePassword: oneTimePassword)
  }

  /// The assertion for signing in with an enrolled TOTP second factor.
  /// - Parameter enrollmentID: The `uid` of the factor's `MultiFactorInfo`.
  /// - Parameter oneTimePassword: A code from the authenticator app.
  public static func assertionForSignIn(withEnrollmentID enrollmentID: String,
                                        oneTimePassword: String) -> TOTPMultiFactorAssertion {
    TOTPMultiFactorAssertion(secretOrID: .enrollmentID(enrollmentID),
                             oneTimePassword: oneTimePassword)
  }
}
