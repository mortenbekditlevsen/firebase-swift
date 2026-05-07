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

/** @class FIRVerifyAssertionResponse
 @brief Represents the response from the verifyAssertion endpoint.
 @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/verifyAssertion
 */
public struct VerifyAssertionResponse: AuthRPCResponse, Decodable {
    internal init(
        federatedID: String? = nil,
        providerID: String? = nil,
        localID: String? = nil,
        email: String? = nil,
        inputEmail: String? = nil,
        originalEmail: String? = nil,
        oauthRequestToken: String? = nil,
        oauthScope: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        fullName: String? = nil,
        nickName: String? = nil,
        displayName: String? = nil,
        idToken: String,
        approximateExpirationDate: Date? = nil,
        refreshToken: String,
        action: String? = nil,
        language: String? = nil,
        timeZone: String? = nil,
        photoURL: URL? = nil,
        dateOfBirth: String? = nil,
        context: String? = nil,
        verifiedProvider: [String]? = nil,
        needConfirmation: Bool = false,
        emailRecycled: Bool = false,
        emailVerified: Bool = false,
        isNewUser: Bool = false,
        profile: [String : Sendable]? = nil,
        username: String? = nil,
        oauthIDToken: String? = nil,
        oauthExpirationDate: Date? = nil,
        oauthAccessToken: String? = nil,
        oauthSecretToken: String? = nil,
        pendingToken: String? = nil,
        MFAPendingCredential: String? = nil,
        MFAInfo: [AuthProtoMFAEnrollment]? = nil
    ) {
        self.federatedID = federatedID
        self.providerID = providerID
        self.localID = localID
        self.email = email
        self.inputEmail = inputEmail
        self.originalEmail = originalEmail
        self.oauthRequestToken = oauthRequestToken
        self.oauthScope = oauthScope
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.nickName = nickName
        self.displayName = displayName
        self.idToken = idToken
        self.approximateExpirationDate = approximateExpirationDate
        self.refreshToken = refreshToken
        self.action = action
        self.language = language
        self.timeZone = timeZone
        self.photoURL = photoURL
        self.dateOfBirth = dateOfBirth
        self.context = context
        self.verifiedProvider = verifiedProvider
        self.needConfirmation = needConfirmation
        self.emailRecycled = emailRecycled
        self.emailVerified = emailVerified
        self.isNewUser = isNewUser
        self.profile = profile
        self.username = username
        self.oauthIDToken = oauthIDToken
        self.oauthExpirationDate = oauthExpirationDate
        self.oauthAccessToken = oauthAccessToken
        self.oauthSecretToken = oauthSecretToken
        self.pendingToken = pendingToken
        self.MFAPendingCredential = MFAPendingCredential
        self.MFAInfo = MFAInfo
    }
    
  /** @property federatedID
   @brief The unique ID identifies the IdP account.
   */
  public var federatedID: String?

  /** @property providerID
   @brief The IdP ID. For white listed IdPs it's a short domain name e.g. google.com, aol.com,
   live.net and yahoo.com. If the "providerId" param is set to OpenID OP identifer other than
   the whilte listed IdPs the OP identifier is returned. If the "identifier" param is federated
   ID in the createAuthUri request. The domain part of the federated ID is returned.
   */
  public var providerID: String?

  /** @property localID
   @brief The RP local ID if it's already been mapped to the IdP account identified by the
   federated ID.
   */
  public var localID: String?

  /** @property email
   @brief The email returned by the IdP. NOTE: The federated login user may not own the email.
   */
  public var email: String?

  /** @property inputEmail
   @brief It's the identifier param in the createAuthUri request if the identifier is an email. It
   can be used to check whether the user input email is different from the asserted email.
   */
  public var inputEmail: String?

  /** @property originalEmail
   @brief The original email stored in the mapping storage. It's returned when the federated ID is
   associated to a different email.
   */
  public var originalEmail: String?

  /** @property oauthRequestToken
   @brief The user approved request token for the OpenID OAuth extension.
   */
  public var oauthRequestToken: String?

  /** @property oauthScope
   @brief The scope for the OpenID OAuth extension.
   */
  public var oauthScope: String?

  /** @property firstName
   @brief The first name of the user.
   */
  public var firstName: String?

  /** @property lastName
   @brief The last name of the user.
   */
  public var lastName: String?

  /** @property fullName
   @brief The full name of the user.
   */
  public var fullName: String?

  /** @property nickName
   @brief The nick name of the user.
   */
  public var nickName: String?

  /** @property displayName
   @brief The display name of the user.
   */
  public var displayName: String?

  /** @property idToken
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

  /** @property action
   @brief The action code.
   */
  public var action: String?

  /** @property language
   @brief The language preference of the user.
   */
  public var language: String?

  /** @property timeZone
   @brief The timezone of the user.
   */
  public var timeZone: String?

  /** @property photoURL
   @brief The URI of the public accessible profile picture.
   */
  public var photoURL: URL?

  /** @property dateOfBirth
   @brief The birth date of the IdP account.
   */
  public var dateOfBirth: String?

  /** @property context
   @brief The opaque value used by the client to maintain context info between the authentication
   request and the IDP callback.
   */
  public var context: String?

  /** @property verifiedProvider
   @brief When action is 'map', contains the idps which can be used for confirmation.
   */
  public var verifiedProvider: [String]?

  /** @property needConfirmation
   @brief Whether the assertion is from a non-trusted IDP and need account linking confirmation.
   */
  public var needConfirmation: Bool = false

  /** @property emailRecycled
   @brief It's true if the email is recycled.
   */
  public var emailRecycled: Bool = false

  /** @property emailVerified
   @brief The value is true if the IDP is also the email provider. It means the user owns the
   email.
   */
  public var emailVerified: Bool = false

  /** @property isNewUser
   @brief Flag indicating that the user signing in is a new user and not a returning user.
   */
  public var isNewUser: Bool = false

  /** @property profile
   @brief Dictionary containing the additional IdP specific information.
   */
     public var profile: [String: Sendable]?

  /** @property username
   @brief The name of the user.
   */
  public var username: String?

  /** @property oauthIDToken
   @brief The ID token for the OpenID OAuth extension.
   */
  public var oauthIDToken: String?

  /** @property oauthExpirationDate
   @brief The approximate expiration date of the oauth access token.
   */
  public var oauthExpirationDate: Date?

  /** @property oauthAccessToken
   @brief The access token for the OpenID OAuth extension.
   */
  public var oauthAccessToken: String?

  /** @property oauthSecretToken
   @brief The secret for the OpenID OAuth extention.
   */
  public var oauthSecretToken: String?

  /** @property pendingToken
   @brief The pending ID Token string.
   */
  public var pendingToken: String?

  public var MFAPendingCredential: String?

  public var MFAInfo: [AuthProtoMFAEnrollment]?

     enum CodingKeys: String, CodingKey {
         case federatedID = "federatedId"
         case providerID = "providerId"
         case localID = "localId"
         case email
         case inputEmail
         case originalEmail
         case oauthRequestToken
         case oauthScope
         case firstName
         case lastName
         case fullName
         case nickName
         case displayName
         case idToken
         
         
         case expiresIn
         case refreshToken
         case action
         case language
         case timeZone
         case photoURL = "photoUrl"
         case dateOfBirth
         case context
         case verifiedProvider
         case needConfirmation
         case emailRecycled
         case emailVerified
         case isNewUser
         case username
         case oauthIDToken = "oauthIdToken"
         case oauthExpireIn
         case oauthAccessToken
         case oauthSecretToken
         case pendingToken
         case MFAPendingCredential = "mfaPendingCredential"
         case MFAInfo = "mfaInfo"
         case rawUserInfo

     }
     
     public init(from decoder: any Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.federatedID = try container.decodeIfPresent(String.self, forKey: .federatedID)
         self.providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
         self.localID = try container.decodeIfPresent(String.self, forKey: .localID)
         self.email = try container.decodeIfPresent(String.self, forKey: .email)
         self.inputEmail = try container.decodeIfPresent(String.self, forKey: .inputEmail)
         self.originalEmail = try container.decodeIfPresent(String.self, forKey: .originalEmail)
         self.oauthRequestToken = try container.decodeIfPresent(String.self, forKey: .oauthRequestToken)
         self.oauthScope = try container.decodeIfPresent(String.self, forKey: .oauthScope)
         self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
         self.lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
         self.fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
         self.nickName = try container.decodeIfPresent(String.self, forKey: .nickName)
         self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
         self.idToken = try container.decode(String.self, forKey: .idToken)
         self.approximateExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .expiresIn))?.date
         self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
         self.action = try container.decodeIfPresent(String.self, forKey: .action)
         self.language = try container.decodeIfPresent(String.self, forKey: .language)
         self.timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
         self.photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
         self.dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
         self.context = try container.decodeIfPresent(String.self, forKey: .context)
         self.verifiedProvider = try container.decodeIfPresent([String].self, forKey: .verifiedProvider)
         self.needConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needConfirmation) ?? false
         self.emailRecycled = try container.decodeIfPresent(Bool.self, forKey: .emailRecycled) ?? false
         self.emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
         self.isNewUser = try container.decode(Bool.self, forKey: .isNewUser)
         self.username = try container.decodeIfPresent(String.self, forKey: .username)
         self.oauthIDToken = try container.decodeIfPresent(String.self, forKey: .oauthIDToken)
         self.oauthExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .oauthExpireIn))?.date
         self.oauthAccessToken = try container.decodeIfPresent(String.self, forKey: .oauthAccessToken)
         self.oauthSecretToken = try container.decodeIfPresent(String.self, forKey: .oauthSecretToken)
         self.pendingToken = try container.decodeIfPresent(String.self, forKey: .pendingToken)
         self.MFAPendingCredential = try container.decodeIfPresent(String.self, forKey: .MFAPendingCredential)
         self.MFAInfo = try container.decodeIfPresent([AuthProtoMFAEnrollment].self, forKey: .MFAInfo)
         
         if let rawUserInfo = try container.decodeIfPresent(String.self, forKey: .rawUserInfo) {
             
             //    if let rawUserInfo = dictionary["rawUserInfo"] as? String,
             if let data = rawUserInfo.data(using: .utf8) {
                 if let info = try? JSONSerialization.jsonObject(with: data, options: .mutableLeaves),
                    let profile = info as? [String: Sendable] {
                     self.profile = profile
                 }
             }
             //    } else if let profile = dictionary["rawUserInfo"] as? [String: Any] {
             //      self.profile = profile
             //    }

         }
         
         
         if let verifiedProvider = try? container.decode([String].self, forKey: .verifiedProvider) {
             self.verifiedProvider = verifiedProvider
         } else if let verifiedProvider = try? container.decode(String.self, forKey: .verifiedProvider) {
             if let data = verifiedProvider.data(using: .utf8) {
                 if let decoded = try? JSONSerialization.jsonObject(with: data, options: .mutableLeaves),
                    let provider = decoded as? [String] {
                     self.verifiedProvider = provider
                 }
             }
         }
     }
     
  public func setFields(dictionary: [String: Any]) throws {
  }
}

struct RelativeDate: Decodable {
    var date: Date
    enum CodingKeys: CodingKey {
        case date
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let relativeDate = try container.decode(String.self)
        self.date = Date(timeIntervalSinceNow: Double(relativeDate) ?? 0)
    }
}
