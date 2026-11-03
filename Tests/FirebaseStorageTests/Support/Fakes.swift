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

// Swift counterparts of the fakes in upstream's SharedTestUtilities, for the
// port's interop protocols.

import FirebaseCore
import Foundation

final class FIRAuthInteropFake: AuthInterop, @unchecked Sendable {
  let token: String?
  let userID: String?
  let error: Error?

  init(token: String?, userID: String?, error: Error?) {
    self.token = token
    self.userID = userID
    self.error = error
  }

  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String? {
    if let error { throw error }
    return token
  }

  func getUserID() -> String? { userID }
}

final class FIRAppCheckTokenResultFake: @unchecked Sendable {
  let token: String
  let error: Error?

  init(token: String, error: Error?) {
    self.token = token
    self.error = error
  }
}

/// The port's AppCheckInterop throws where upstream's returns a result with
/// an error (and a placeholder token).
final class FIRAppCheckFake: AppCheckInterop, @unchecked Sendable {
  private let lock = NSLock()
  private var _tokenResult = FIRAppCheckTokenResultFake(token: "fake_valid_token", error: nil)
  private var _limitedUseTokenResult = FIRAppCheckTokenResultFake(
    token: "fake_limited_use_valid_token", error: nil
  )

  var tokenResult: FIRAppCheckTokenResultFake {
    get { lock.withLock { _tokenResult } }
    set { lock.withLock { _tokenResult = newValue } }
  }

  var limitedUseTokenResult: FIRAppCheckTokenResultFake {
    get { lock.withLock { _limitedUseTokenResult } }
    set { lock.withLock { _limitedUseTokenResult = newValue } }
  }

  func getToken(forcingRefresh: Bool) async throws -> String {
    let result = tokenResult
    if let error = result.error { throw error }
    return result.token
  }
}
