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

/** @var kErrorKey
    @brief The key for the "error" value in JSON responses from the server.
 */
private let kErrorKey = "error"

/** @class FIRGetAccountInfoResponseProviderUserInfo
    @brief Represents the provider user info part of the response from the getAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
 */

public struct GetAccountInfoResponseProviderUserInfo: Decodable, Sendable {
  /** @property providerID
   @brief The ID of the identity provider.
   */
  public let providerID: String?

  /** @property displayName
   @brief The user's display name at the identity provider.
   */
  public let displayName: String?

  /** @property photoURL
   @brief The user's photo URL at the identity provider.
   */
  public let photoURL: URL?

  /** @property federatedID
   @brief The user's identifier at the identity provider.
   */
  public let federatedID: String?

  /** @property email
   @brief The user's email at the identity provider.
   */
  public let email: String?

  /** @property phoneNumber
   @brief A phone number associated with the user.
   */
  public let phoneNumber: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case displayName
        case photoURL = "photoUrl"
        case federatedID = "federatedId"
        case email
        case phoneNumber
    }
}

/** @class FIRGetAccountInfoResponseUser
    @brief Represents the firebase user info part of the response from the getAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
 */
public struct GetAccountInfoResponseUser: Decodable, Sendable {
  /** @property localID
   @brief The ID of the user.
   */
  public let localID: String?

  /** @property email
   @brief The email or the user.
   */
  public let email: String?

  /** @property emailVerified
   @brief Whether the email has been verified.
   */
  public let emailVerified: Bool

  /** @property displayName
   @brief The display name of the user.
   */
  public let displayName: String?

  /** @property photoURL
   @brief The user's photo URL.
   */
  public let photoURL: URL?

  /** @property creationDate
   @brief The user's creation date.
   */
  public let creationDate: Date?

  /** @property lastSignInDate
   @brief The user's last login date.
   */
  public let lastLoginDate: Date?

  /** @property providerUserInfo
   @brief The user's profiles at the associated identity providers.
   */
  public let providerUserInfo: [GetAccountInfoResponseProviderUserInfo]?

  /** @property passwordHash
   @brief Information about user's password.
   @remarks This is not necessarily the hash of user's actual password.
   */

  public let passwordHash: String?

  /** @property phoneNumber
   @brief A phone number associated with the user.
   */
  public let phoneNumber: String?

   public let mfaEnrollments: [AuthProtoMFAEnrollment]?

  /** @fn initWithAPIKey:
   @brief Designated initializer.
   @param dictionary The provider user info data from endpoint.
   */
    enum CodingKeys: String, CodingKey {
        case localID = "localId"
        case email
        case emailVerified
        case displayName
        case photoURL
        case creationDate = "createdAt"
        case lastLoginDate = "lastLoginAt"
        case providerUserInfo
        case passwordHash
        case phoneNumber
        case mfaEnrollments = "mfaInfo"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.localID = try container.decodeIfPresent(String.self, forKey: .localID)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        if let creationDateString = try container.decodeIfPresent(String.self, forKey: .creationDate) {
            self.creationDate = Date(timeIntervalSince1970: (Double(creationDateString) ?? 0) / 1000)
        } else {
            self.creationDate = nil
        }
        if let lastLoginDateString = try container.decodeIfPresent(String.self, forKey: .lastLoginDate) {
            self.lastLoginDate = Date(timeIntervalSince1970: (Double(lastLoginDateString) ?? 0) / 1000)
        } else {
            self.lastLoginDate = nil
        }
        self.providerUserInfo = try container.decodeIfPresent([GetAccountInfoResponseProviderUserInfo].self, forKey: .providerUserInfo)
        self.passwordHash = try container.decodeIfPresent(String.self, forKey: .passwordHash)
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        self.mfaEnrollments = try container.decodeIfPresent([AuthProtoMFAEnrollment].self, forKey: .mfaEnrollments)
    }
}

/** @class FIRGetAccountInfoResponse
    @brief Represents the response from the setAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct GetAccountInfoResponse: AuthRPCResponse {
  /** @property providerUserInfo
   @brief The requested users' profiles.
   */
  public var user: GetAccountInfoResponseUser
     
     enum CodingKeys: CodingKey {
         case users
     }
     
     public init(from decoder: any Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         let users = try container.decode([GetAccountInfoResponseUser].self, forKey: .users)
         guard users.count == 1 else {
             // XXX TODO: Not actually deserialized. That is harder with Decoding. Is it necessary though?
             throw AuthErrorUtils.unexpectedResponse(deserializedResponse: users)
         }
         print("USERSDATA", users[0])
         self.user = users[0]

     }
}
