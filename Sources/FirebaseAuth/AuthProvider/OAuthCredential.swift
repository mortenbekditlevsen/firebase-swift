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

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct OAuthCredential: AuthCredential, Codable {
  /** @property IDToken
      @brief The ID Token associated with this credential.
   */
   public let idToken: String?

  /** @property accessToken
      @brief The access token associated with this credential.
   */
  public let accessToken: String?

  /** @property secret
      @brief The secret associated with this credential. This will be nil for OAuth 2.0 providers.
      @detail OAuthCredential already exposes a providerId getter. This will help the developer
          determine whether an access token/secret pair is needed.
   */
  public let secret: String?

  // internal
  let OAuthResponseURLString: String?
  let sessionID: String?
  let pendingToken: String?
  let fullName: PersonNameComponents?
  // private
  let rawNonce: String?
     
     public var provider: String

  // TODO: Remove public objc
  public init(withProviderID providerID: String,
                    idToken: String? = nil,
                    rawNonce: String? = nil,
                    accessToken: String? = nil,
                    secret: String? = nil,
                    fullName: PersonNameComponents? = nil,
                    pendingToken: String? = nil) {
    self.idToken = idToken
    self.rawNonce = rawNonce
    self.accessToken = accessToken
    self.pendingToken = pendingToken
    self.secret = secret
    self.fullName = fullName
    OAuthResponseURLString = nil
    sessionID = nil
      self.provider = providerID
  }

  public init(withProviderID providerID: String,
                    sessionID: String,
                    OAuthResponseURLString: String) {
    self.sessionID = sessionID
    self.OAuthResponseURLString = OAuthResponseURLString
    accessToken = nil
    pendingToken = nil
    secret = nil
    idToken = nil
    rawNonce = nil
    fullName = nil
      self.provider = providerID
  }

  public init?(withVerifyAssertionResponse response: VerifyAssertionResponse) {
    guard Self.nonEmptyString(response.oauthIDToken) ||
      Self.nonEmptyString(response.oauthAccessToken) ||
      Self.nonEmptyString(response.oauthSecretToken) else {
      return nil
    }
    self.init(withProviderID: response.providerID ?? OAuthProvider.id,
              idToken: response.oauthIDToken,
              rawNonce: nil,
              accessToken: response.oauthAccessToken,
              secret: response.oauthSecretToken,
              pendingToken: response.pendingToken)
  }

     public func prepare(_ request: inout VerifyAssertionRequest) {
    request.providerIDToken = idToken
    request.providerRawNonce = rawNonce
    request.providerAccessToken = accessToken
    request.requestURI = OAuthResponseURLString
    request.sessionID = sessionID
    request.providerOAuthTokenSecret = secret
    request.fullName = fullName
    request.pendingToken = pendingToken
  }

  // MARK: Secure Coding

     enum CodingKeys: String, CodingKey {
         case idToken
         case rawNonce
         case accessToken
         case pendingToken
         case secret
         case fullName
     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encodeIfPresent(self.idToken, forKey: .idToken)
         try container.encodeIfPresent(self.rawNonce, forKey: .rawNonce)
         try container.encodeIfPresent(self.accessToken, forKey: .accessToken)
         try container.encodeIfPresent(self.pendingToken, forKey: .pendingToken)
         try container.encodeIfPresent(self.secret, forKey: .secret)
         try container.encodeIfPresent(self.fullName, forKey: .fullName)
     }

     public init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)

         idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
         rawNonce = try container.decodeIfPresent(String.self, forKey: .rawNonce)
         accessToken = try container.decodeIfPresent(String.self,  forKey: .accessToken)
         pendingToken = try container.decodeIfPresent(String.self, forKey: .pendingToken)
         secret = try container.decodeIfPresent(String.self, forKey: .secret)
         fullName = try container.decodeIfPresent(PersonNameComponents.self, forKey: .fullName)
         OAuthResponseURLString = nil
         sessionID = nil
         self.provider = OAuthProvider.id
     }

  private static func nonEmptyString(_ string: String?) -> Bool {
    guard let string else {
      return false
    }
    return string.count > 0
  }
}
