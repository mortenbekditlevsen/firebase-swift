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

import Foundation

private let kPlaceholderTokenValue = "eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ=="

final class AppCheckCoreTokenResult: NSObject, @unchecked Sendable {
  let token: AppCheckCoreToken
  let error: Error?

  init(token: AppCheckCoreToken, error: Error?) {
    self.token = token
    self.error = error
    super.init()
  }

  convenience init(token: AppCheckCoreToken) {
    self.init(token: token, error: nil)
  }

  convenience init(error: Error) {
    let placeholder = AppCheckCoreTokenResult.placeholderToken()
    self.init(token: placeholder, error: error)
  }

  static func placeholderToken() -> AppCheckCoreToken {
    return AppCheckCoreToken(token: kPlaceholderTokenValue, expirationDate: Date.distantPast)
  }
}
