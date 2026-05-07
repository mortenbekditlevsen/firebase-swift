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

// TODO: Remove objc public after Sample app is replaced.

/** @class FIRAuthAppCredential
    @brief A class represents a credential that proves the identity of the app.
 */
 public struct AuthAppCredential: Codable, Sendable {
  /** @property receipt
      @brief The server acknowledgement of receiving client's claim of identity.
   */
  public var receipt: String

  /** @property secret
      @brief The secret that the client received from server via a trusted channel, if ever.
   */
  public var secret: String?

  /** @fn initWithReceipt:secret:
      @brief Initializes the instance.
      @param receipt The server acknowledgement of receiving client's claim of identity.
      @param secret The secret that the client received from server via a trusted channel, if ever.
      @return The initialized instance.
   */
  public init(receipt: String, secret: String?) {
    self.secret = secret
    self.receipt = receipt
  }
}
