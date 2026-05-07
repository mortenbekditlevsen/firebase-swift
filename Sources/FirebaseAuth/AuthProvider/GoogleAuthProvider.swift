// Copyright 2022 Google LLC
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

/**
 @brief Utility class for constructing Google Sign In credentials.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public enum GoogleAuthProvider {
  public static let id = "google.com"

  /**
      @brief Creates an `AuthCredential` for a Google sign in.

      @param IDToken The ID Token from Google.
      @param accessToken The Access Token from Google.
      @return An AuthCredential containing the Google credentials.
   */
  public static func credential(withIDToken IDToken: String,
                                     accessToken: String) -> AuthCredential {
    return GoogleAuthCredential(withIDToken: IDToken, accessToken: accessToken)
  }

}

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 struct GoogleAuthCredential: AuthCredential, Codable {
  let idToken: String
  let accessToken: String

     var provider: String { GoogleAuthProvider.id }
     
  init(withIDToken idToken: String, accessToken: String) {
    self.idToken = idToken
    self.accessToken = accessToken
  }

     func prepare(_ request: inout VerifyAssertionRequest) {
    request.providerIDToken = idToken
    request.providerAccessToken = accessToken
  }

     enum CodingKeys: CodingKey {
         case idToken
         case accessToken
     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encode(self.idToken, forKey: .idToken)
         try container.encode(self.accessToken, forKey: .accessToken)
     }

      public init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.idToken = try container.decode(String.self, forKey: .idToken)
         self.accessToken = try container.decode(String.self, forKey: .accessToken)
     }
}
