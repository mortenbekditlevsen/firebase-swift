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

/// Identifies a second factor enrollment, or the sign-in that needs a second factor.
public final class MultiFactorSession: @unchecked Sendable {
  /// For enrollment: the user's ID token.
  let idToken: String?

  /// For sign-in: the credential from the first factor.
  let mfaPendingCredential: String?

  /// For enrollment: the user enrolling.
  weak var user: User?

  /// For sign-in: the factor being verified, set by `PhoneAuthProvider`.
  var multiFactorInfo: MultiFactorInfo? {
    get { lock.withLock { _multiFactorInfo } }
    set { lock.withLock { _multiFactorInfo = newValue } }
  }

  private let lock = NSLock()
  private var _multiFactorInfo: MultiFactorInfo?

  init(enrolling user: User, idToken: String) {
    self.idToken = idToken
    self.user = user
    mfaPendingCredential = nil
  }

  init(mfaPendingCredential: String?) {
    idToken = nil
    self.mfaPendingCredential = mfaPendingCredential
  }
}
