// Copyright 2026 Google LLC
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
@testable import FirebaseAuth
import Foundation
import Testing

/// TOTP request and response formats. The Auth emulator doesn't support TOTP, so these check
/// the JSON against upstream's.
struct MultiFactorTests {
  private let configuration = AuthRequestConfiguration(apiKey: "key", appID: "app")

  private func json(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func startingTOTPEnrollmentSendsAnEmptyObject() throws {
    let request = StartMFAEnrollmentRequest(idToken: "token", totpEnrollmentInfo: .init(),
                                            requestConfiguration: configuration)
    let body = try json(request)
    #expect(body["idToken"] as? String == "token")
    #expect((body["totpEnrollmentInfo"] as? [String: Any])?.isEmpty == true)
    #expect(body["phoneEnrollmentInfo"] == nil)
  }

  @Test func finishingTOTPEnrollmentSendsTheSessionAndCode() throws {
    let request = FinalizeMFAEnrollmentRequest(
      idToken: "token", displayName: "Authenticator",
      totpVerificationInfo: .init(sessionInfo: "session", verificationCode: "123456"),
      requestConfiguration: configuration
    )
    let body = try json(request)
    #expect(body["displayName"] as? String == "Authenticator")
    let info = try #require(body["totpVerificationInfo"] as? [String: Any])
    #expect(info["sessionInfo"] as? String == "session")
    #expect(info["verificationCode"] as? String == "123456")
    #expect(body["phoneVerificationInfo"] == nil)
  }

  @Test func totpSignInSendsTheEnrollmentIDBesideTheCode() throws {
    let request = FinalizeMFASignInRequest(
      mfaPendingCredential: "pending", mfaEnrollmentID: "enrollment",
      totpVerificationInfo: .init(verificationCode: "654321"),
      requestConfiguration: configuration
    )
    let body = try json(request)
    #expect(body["mfaPendingCredential"] as? String == "pending")
    #expect(body["mfaEnrollmentId"] as? String == "enrollment")
    #expect((body["totpVerificationInfo"] as? [String: Any])?["verificationCode"] as? String
      == "654321")
  }

  @Test func readsTheTOTPSecret() throws {
    let json = """
      {"totpSessionInfo": {"sharedSecretKey": "SECRET", "verificationCodeLength": 6,
        "hashingAlgorithm": "SHA1", "periodSec": 30, "sessionInfo": "session",
        "finalizeEnrollmentTime": "2026-11-02T10:00:00.123456Z"}}
      """
    let response = try JSONDecoder().decode(StartMFAEnrollmentResponse.self, from: Data(json.utf8))
    let info = try #require(response.totpSessionInfo)
    #expect(info.sharedSecretKey == "SECRET")
    #expect(info.verificationCodeLength == 6)
    #expect(info.periodSec == 30)
    #expect(info.finalizeEnrollmentTime != nil)
  }

  @Test func aTOTPResponseWithoutASecretFails() {
    // Upstream #16904: this crashed.
    let json = #"{"totpSessionInfo": {"verificationCodeLength": 6}}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(StartMFAEnrollmentResponse.self, from: Data(json.utf8))
    }
  }

  @Test func qrCodeURLsEscapeTheLabel() throws {
    let secret = TOTPSecret(secretKey: "SECRET", hashingAlgorithm: "SHA1", codeLength: 6,
                            codeIntervalSeconds: 30, enrollmentCompletionDeadline: nil,
                            sessionInfo: nil)
    let url = secret.generateQRCodeURL(withAccountName: "a@example.com", issuer: "My App")
    #expect(url == "otpauth://totp/My%20App:a@example.com" +
      "?secret=SECRET&issuer=My%20App&algorithm=SHA1&digits=6")
    #expect(URL(string: url) != nil)
    #expect(secret.sharedSecretKey() == "SECRET")
  }

  @Test func enrollmentsKeepTheirKindWhenSaved() throws {
    let json = """
      [{"mfaEnrollmentId": "p", "phoneInfo": "+15550000000"},
       {"mfaEnrollmentId": "t", "totpInfo": {}, "displayName": "Authenticator"},
       {"phoneInfo": "+15550000001"}]
      """
    let enrollments = try JSONDecoder().decode([AuthProtoMFAEnrollment].self, from: Data(json.utf8))
    let saved = try JSONDecoder().decode([AuthProtoMFAEnrollment].self,
                                         from: JSONEncoder().encode(enrollments))
    #expect(saved == enrollments)
    let factors = MultiFactor(user: nil, enrollments: saved).enrolledFactors
    // The last one has no enrollment ID and is skipped.
    #expect(factors.map(\.factorID) == ["phone", "totp"])
    #expect(factors[1] is TOTPMultiFactorInfo)
    #expect(factors[1].displayName == "Authenticator")
  }
}
