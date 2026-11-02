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

/// A second factor enrolled for a user.
public class MultiFactorInfo: @unchecked Sendable {
  /// The multi-factor enrollment ID.
  public let uid: String

  /// The user friendly name of the current second factor.
  public let displayName: String?

  /// The second factor enrollment date.
  public let enrollmentDate: Date?

  /// The identifier of the second factor: `PhoneMultiFactorInfo.PhoneMultiFactorID` or
  /// `PhoneMultiFactorInfo.TOTPMultiFactorID`.
  public let factorID: String

  /// Returns `nil` if the enrollment has no enrollment ID.
  init?(proto: AuthProtoMFAEnrollment, factorID: String) {
    guard let uid = proto.mfaEnrollmentID else {
      AuthLog.logWarning(code: "I-AUT000035",
                         message: "Ignoring a second factor enrollment without an enrollment ID.")
      return nil
    }
    self.uid = uid
    displayName = proto.displayName
    enrollmentDate = proto.enrolledAt
    self.factorID = factorID
  }

  /// The phone or TOTP factor for an enrollment, or `nil` for other or invalid enrollments.
  static func info(for proto: AuthProtoMFAEnrollment) -> MultiFactorInfo? {
    if proto.phoneInfo != nil {
      return PhoneMultiFactorInfo(proto: proto)
    }
    if proto.isTOTP {
      return TOTPMultiFactorInfo(proto: proto)
    }
    return nil
  }
}
