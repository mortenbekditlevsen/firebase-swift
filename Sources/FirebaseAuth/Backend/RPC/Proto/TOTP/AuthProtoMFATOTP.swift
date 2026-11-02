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

/// Starts a TOTP enrollment. The backend takes an empty object.
struct AuthProtoStartMFATOTPEnrollmentRequestInfo: Encodable, Sendable {}

/// The shared secret for a TOTP enrollment.
struct AuthProtoStartMFATOTPEnrollmentResponseInfo: Decodable, Sendable {
  let sharedSecretKey: String
  let verificationCodeLength: Int
  let hashingAlgorithm: String?
  let periodSec: Int
  let sessionInfo: String?
  let finalizeEnrollmentTime: Date?

  private enum CodingKeys: String, CodingKey {
    case sharedSecretKey, verificationCodeLength, hashingAlgorithm, periodSec, sessionInfo,
         finalizeEnrollmentTime
  }

  /// Throws if there's no shared secret key (upstream #16904).
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sharedSecretKey = try container.decode(String.self, forKey: .sharedSecretKey)
    verificationCodeLength = try container.decodeIfPresent(Int.self,
                                                           forKey: .verificationCodeLength) ?? 0
    hashingAlgorithm = try container.decodeIfPresent(String.self, forKey: .hashingAlgorithm)
    periodSec = try container.decodeIfPresent(Int.self, forKey: .periodSec) ?? 0
    sessionInfo = try container.decodeIfPresent(String.self, forKey: .sessionInfo)
    finalizeEnrollmentTime = try container
      .decodeIfPresent(String.self, forKey: .finalizeEnrollmentTime)
      .flatMap { ISO8601DateFormatter.mfaTimestamp.date(from: $0) }
  }
}

/// Completes a TOTP enrollment with a code from the authenticator app.
struct AuthProtoFinalizeMFATOTPEnrollmentRequestInfo: Encodable, Sendable {
  let sessionInfo: String?
  let verificationCode: String?
}

/// Completes a TOTP sign-in with a code from the authenticator app. The enrollment ID goes
/// next to it in the request.
struct AuthProtoFinalizeMFATOTPSignInRequestInfo: Encodable, Sendable {
  let verificationCode: String?
}

extension ISO8601DateFormatter {
  /// The backend's timestamps, such as "2026-11-02T10:00:00.123456Z".
  nonisolated(unsafe) static let mfaTimestamp: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
