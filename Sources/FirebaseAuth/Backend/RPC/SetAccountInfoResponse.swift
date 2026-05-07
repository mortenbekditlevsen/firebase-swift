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

/** @class FIRSetAccountInfoResponseProviderUserInfo
    @brief Represents the provider user info part of the response from the setAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/setAccountInfo
 */

public struct SetAccountInfoResponseProviderUserInfo: Decodable, Sendable {
  /** @property providerID
      @brief The ID of the identity provider.
   */
  public var providerID: String?

  /** @property displayName
      @brief The user's display name at the identity provider.
   */
  public var displayName: String?

  /** @property photoURL
      @brief The user's photo URL at the identity provider.
   */
  public var photoURL: URL?

    enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case displayName
        case photoURL = "photoUrl"
    }
}

/** @class FIRSetAccountInfoResponse
    @brief Represents the response from the setAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/setAccountInfo
 */
 public struct SetAccountInfoResponse: AuthRPCResponse, Decodable {
  /** @property email
      @brief The email or the user.
   */
  public var email: String?

  /** @property displayName
      @brief The display name of the user.
   */
  public var displayName: String?

  /** @property providerUserInfo
      @brief The user's profiles at the associated identity providers.
   */
  public var providerUserInfo: [SetAccountInfoResponseProviderUserInfo]?

  /** @property idToken
      @brief Either an authorization code suitable for performing an STS token exchange, or the
          access token from Secure Token Service, depending on whether @c returnSecureToken is set
          on the request.
   */
   public var idToken: String?

  /** @property approximateExpirationDate
      @brief The approximate expiration date of the access token.
   */
  public var approximateExpirationDate: Date?

  /** @property refreshToken
      @brief The refresh token from Secure Token Service.
   */
  public var refreshToken: String?

     enum CodingKeys: String, CodingKey {
         case email
         case displayName
         case providerUserInfo
         case idToken
         case expiresIn = "expiresIn"
         case refreshToken
     }
     
     public init(from decoder: any Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.email = try container.decodeIfPresent(String.self, forKey: .email)
         self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
         self.providerUserInfo = try container.decodeIfPresent([SetAccountInfoResponseProviderUserInfo].self, forKey: .providerUserInfo)
         self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
         self.approximateExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .expiresIn))?.date
         self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
     }
  public func setFields(dictionary: [String: Any]) throws {
  }
}
