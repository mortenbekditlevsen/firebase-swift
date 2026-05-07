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

/** @class FIRVerifyPasswordResponse
    @brief Represents the response from the verifyPassword endpoint.
    @remarks Possible error codes:
       - FIRAuthInternalErrorCodeUserDisabled
       - FIRAuthInternalErrorCodeEmailNotFound
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/verifyPassword
 */
 public struct VerifyPasswordResponse: AuthRPCResponse {
  /** @property localID
      @brief The RP local ID if it's already been mapped to the IdP account identified by the
          federated ID.
   */
  public var localID: String?

  /** @property email
      @brief The email returned by the IdP. NOTE: The federated login user may not own the email.
   */
  public var email: String?

  /** @property displayName
      @brief The display name of the user.
   */
  public var displayName: String?

  /** @property IDToken
      @brief Either an authorization code suitable for performing an STS token exchange, or the
          access token from Secure Token Service, depending on whether @c returnSecureToken is set
          on the request.
   */
   public var idToken: String

  /** @property approximateExpirationDate
      @brief The approximate expiration date of the access token.
   */
  public var approximateExpirationDate: Date?

  /** @property refreshToken
      @brief The refresh token from Secure Token Service.
   */
  public var refreshToken: String

  /** @property photoURL
      @brief The URI of the public accessible profile picture.
   */
  public var photoURL: URL?

   public var mfaPendingCredential: String?

   public var mfaInfo: [AuthProtoMFAEnrollment]?

     enum CodingKeys: String, CodingKey {
         case localID = "localId"
         case email
         case displayName
         case idToken
         case expiresIn
         case refreshToken
         case photoURL = "photoUrl"
         case mfaPendingCredential
         case mfaInfo
     }
  
     public func setFields(dictionary: [String : Any]) throws {
         
     }
     
     public init(from decoder: any Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.localID = try container.decodeIfPresent(String.self, forKey: .localID)
         self.email = try container.decodeIfPresent(String.self, forKey: .email)
         self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
         self.idToken = try container.decode(String.self, forKey: .idToken)
         self.approximateExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .expiresIn))?.date
         self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
         self.photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
         self.mfaPendingCredential = try container.decodeIfPresent(String.self, forKey: .mfaPendingCredential)
         self.mfaInfo = try container.decodeIfPresent([AuthProtoMFAEnrollment].self, forKey: .mfaInfo)
     }
}
