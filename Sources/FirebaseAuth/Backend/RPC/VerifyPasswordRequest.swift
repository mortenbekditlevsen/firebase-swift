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

/** @var kVerifyPasswordEndpoint
    @brief The "verifyPassword" endpoint.
 */
private let kVerifyPasswordEndpoint = "verifyPassword"

/** @class FIRVerifyPasswordRequest
    @brief Represents the parameters for the verifyPassword endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/verifyPassword
 */
 public struct VerifyPasswordRequest: IdentityToolkitRequest,
                                      AuthRPCRequest, Encodable {
     public typealias Response = VerifyPasswordResponse
     
     /** @property email
      @brief The email of the user.
      */
     public var email: String
     
     /** @property password
      @brief The password inputed by the user.
      */
     public var password: String
     
     /** @property pendingIDToken
      @brief The GITKit token for the non-trusted IDP, which is to be confirmed by the user.
      */
     public var pendingIDToken: String?
     
     /** @property captchaChallenge
      @brief The captcha challenge.
      */
     public var captchaChallenge: String?
     
     /** @property captchaResponse
      @brief Response to the captcha.
      */
     public var captchaResponse: String?
     
     /** @property returnSecureToken
      @brief Whether the response should return access token and refresh token directly.
      @remarks The default value is @c YES .
      */
     public var returnSecureToken: Bool
     
     /** @var response
      @brief The corresponding response for this request
      */
     
     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { false }
     public var endpoint: String { kVerifyPasswordEndpoint }
     public var requestConfiguration: AuthRequestConfiguration
     
     public init(
        email: String,
        password: String,
        requestConfiguration: AuthRequestConfiguration
     ) {
         self.email = email
         self.password = password
         self.returnSecureToken = true
         self.requestConfiguration = requestConfiguration
     }

     enum CodingKeys: String, CodingKey {
         case email
         case password
         case pendingIDToken = "pendingIdToken"
         case captchaChallenge = "captchaChallenge"
         case captchaResponse = "captchaResponse"
         case returnSecureToken = "returnSecureToken"
         case tenantID = "tenantId"
         
     }
     public func encode(to encoder: any Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encode(email, forKey: .email)
         try container.encode(password, forKey: .password)
         try container.encodeIfPresent(pendingIDToken, forKey: .pendingIDToken)
         try container.encodeIfPresent(captchaChallenge, forKey: .captchaChallenge)
         try container.encodeIfPresent(captchaResponse, forKey: .captchaResponse)
         if returnSecureToken {
             try container.encode(true, forKey: .returnSecureToken)
         }
         try container.encodeIfPresent(tenantID, forKey: .tenantID)
     }
 }
