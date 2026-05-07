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

/** @class AuthDataResult
    @brief Helper object that contains the result of a successful sign-in, link and reauthenticate
        action. It contains references to a `User` instance and a `AdditionalUserInfo` instance.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct AuthDataResult: Codable, Sendable {
  /** @property user
      @brief The signed in user.
   */
     public let user: User
  /** @property additionalUserInfo
      @brief If available contains the additional IdP specific information about signed in user.
   */
  public let additionalUserInfo: AdditionalUserInfo?

  /** @property credential
      @brief This property will be non-nil after a successful headful-lite sign-in via
          `signIn(with:uiDelegate:completion:)`. May be used to obtain the accessToken and/or IDToken
          pertaining to a recently signed-in user.
   */
  public let credential: OAuthCredential?

  private let kAdditionalUserInfoCodingKey = "additionalUserInfo"
  private let kUserCodingKey = "user"
  private let kCredentialCodingKey = "credential"

  // TODO: All below here should be internal

  /** @fn initWithUser:additionalUserInfo:
   @brief Designated initializer.
   @param user The signed in user reference.
   @param additionalUserInfo The additional user info.
   @param credential The updated OAuth credential if available.
   */
  public init(withUser user: User,
              additionalUserInfo: AdditionalUserInfo?,
                    credential: OAuthCredential? = nil) {
    self.user = user
    self.additionalUserInfo = additionalUserInfo
    self.credential = credential
  }

  public static var supportsSecureCoding: Bool {
    return true
  }

     enum CodingKeys: String, CodingKey {
         case additionalUserInfo
         case user
         case credential
     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)

         try container.encode(user, forKey: .user)
         try container.encodeIfPresent(additionalUserInfo, forKey: .additionalUserInfo)
         try container.encodeIfPresent(credential, forKey: .credential)
     }

     public init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.additionalUserInfo = try container.decodeIfPresent(AdditionalUserInfo.self, forKey: .additionalUserInfo)
         self.credential =  try container.decodeIfPresent(OAuthCredential.self, forKey: .credential)
         self.user = try container.decode(User.self, forKey: .user)
     }

}
