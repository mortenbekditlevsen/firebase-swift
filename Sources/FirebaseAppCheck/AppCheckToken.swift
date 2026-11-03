// Copyright 2020 Google LLC
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

/// An object representing a Firebase App Check token. Upstream's `AppCheckToken` is a class; it's
/// a value type here.
public struct AppCheckToken: Hashable, Sendable {
  /// A Firebase App Check token.
  public let token: String

  /// The App Check token's expiration date in the device's local time.
  public let expirationDate: Date

  /// The date when the token was received, in the device's local time.
  let receivedAtDate: Date

  /// The default initializer.
  /// - Parameters:
  ///   - token: A Firebase App Check token.
  ///   - expirationDate: A Firebase App Check token expiration date in the device local time.
  public init(token: String, expirationDate: Date) {
    self.init(token: token, expirationDate: expirationDate, receivedAtDate: Date())
  }

  init(token: String, expirationDate: Date, receivedAtDate: Date) {
    self.token = token
    self.expirationDate = expirationDate
    self.receivedAtDate = receivedAtDate
  }

  init(internalToken: AppCheckCoreToken) {
    self.init(token: internalToken.token,
              expirationDate: internalToken.expirationDate,
              receivedAtDate: internalToken.receivedAtDate)
  }

  var internalToken: AppCheckCoreToken {
    AppCheckCoreToken(token: token, expirationDate: expirationDate, receivedAt: receivedAtDate)
  }
}
