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

/// Asserts ownership of a TOTP second factor.
public final class TOTPMultiFactorAssertion: MultiFactorAssertion, @unchecked Sendable {
  enum SecretOrID {
    /// For enrolling.
    case secret(TOTPSecret)
    /// For signing in.
    case enrollmentID(String)
  }

  let oneTimePassword: String
  let secretOrID: SecretOrID

  init(secretOrID: SecretOrID, oneTimePassword: String) {
    self.oneTimePassword = oneTimePassword
    self.secretOrID = secretOrID
    super.init(factorID: PhoneMultiFactorInfo.TOTPMultiFactorID)
  }
}
