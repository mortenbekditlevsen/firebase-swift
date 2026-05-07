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

public struct VerifyPhoneNumberResponse:
  AuthRPCResponse {
  /** @property IDToken
   @brief Either an authorization code suitable for performing an STS token exchange, or the
   access token from Secure Token Service, depending on whether @c returnSecureToken is set
   on the request.
   */
   public var idToken: String

  /** @property refreshToken
   @brief The refresh token from Secure Token Service.
   */
  public var refreshToken: String

  /** @property localID
   @brief The Firebase Auth user ID.
   */
  public var localID: String?

  /** @property phoneNumber
   @brief The verified phone number.
   */
  public var phoneNumber: String?

  /** @property temporaryProof
   @brief The temporary proof code returned by the backend.
   */
  public var temporaryProof: String?

  /** @property isNewUser
   @brief Flag indicating that the user signing in is a new user and not a returning user.
   */

  public var isNewUser: Bool = false

  /** @property approximateExpirationDate
   @brief The approximate expiration date of the access token.
   */
  public var approximateExpirationDate: Date?

    
    enum CodingKeys: String, CodingKey {
        case idToken
        case refreshToken
        case localID = "localId"
        case phoneNumber
        case temporaryProof
        case isNewUser
        case expiresIn
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idToken = try container.decode(String.self, forKey: .idToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.localID = try container.decodeIfPresent(String.self, forKey: .localID)
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        self.temporaryProof = try container.decodeIfPresent(String.self, forKey: .temporaryProof)
        self.isNewUser = try container.decode(Bool.self, forKey: .isNewUser)
        self.approximateExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .expiresIn))?.date
    }
}
