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

/// A phone number second factor.
public final class PhoneMultiFactorInfo: MultiFactorInfo, @unchecked Sendable {
  /// The string identifier for using phone as a second factor.
  public static let PhoneMultiFactorID = "phone"

  /// The string identifier for using TOTP as a second factor.
  public static let TOTPMultiFactorID = "totp"

  /// The phone number associated with the current second factor.
  public let phoneNumber: String

  /// Returns `nil` if the enrollment has no enrollment ID or phone number.
  init?(proto: AuthProtoMFAEnrollment) {
    guard let phoneNumber = proto.phoneInfo else {
      return nil
    }
    self.phoneNumber = phoneNumber
    // The port used "FIRPhoneMultiFactorID" (upstream's Objective-C name) as the ID.
    super.init(proto: proto, factorID: Self.PhoneMultiFactorID)
  }
}
