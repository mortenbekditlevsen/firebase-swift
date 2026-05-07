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

 public final class AdditionalUserInfo: Codable, @unchecked Sendable {
  private static let providerIDCodingKey = "providerID"
  private static let profileCodingKey = "profile"
  private static let usernameCodingKey = "username"
  private static let newUserKey = "newUser"

  /** @property providerID
      @brief The provider identifier.
   */
  public let providerID: String?

  /** @property profile
      @brief Dictionary containing the additional IdP specific information.
   */
  public let profile: [String: Any]?

  /** @property username
      @brief username The name of the user.
   */
  public let username: String?

  /** @property isMewUser
      @brief Indicates whether or not the current user was signed in for the first time.
   */
  public let isNewUser: Bool

  // Maintain newUser for Objective C API.
  public func newUser() -> Bool {
    return isNewUser
  }

  public static func userInfo(verifyAssertionResponse: VerifyAssertionResponse)
    -> AdditionalUserInfo {
        AdditionalUserInfo(providerID: verifyAssertionResponse.providerID,
                           profile: verifyAssertionResponse.profile,
                           username: verifyAssertionResponse.username,
                           isNewUser: verifyAssertionResponse.isNewUser)
  }

  init(providerID: String?, profile: [String: Any]?, username: String?, isNewUser: Bool) {
    self.providerID = providerID
    self.profile = profile
    self.username = username
    self.isNewUser = isNewUser
  }

     enum CodingKeys: CodingKey {
         case providerID
         case profile
         case username
         case isNewUser
     }

     public required init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.providerID = try container.decode(String.self, forKey: .providerID)
         // XXX TODO
         self.profile = nil
         self.username = try container.decode(String.self, forKey: .username)
         self.isNewUser = try container.decodeIfPresent(Bool.self, forKey: .isNewUser) ?? false

     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encodeIfPresent(providerID, forKey: .providerID)
         try container.encodeIfPresent(username, forKey: .username)
         try container.encode(isNewUser, forKey: .isNewUser)
         // XXX TODO
//         try container.encode(profile, forKey: .profile)
     }
    
}
