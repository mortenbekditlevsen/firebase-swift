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

/**
 @brief Utility class for constructing Twitter Sign In credentials.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public enum TwitterAuthProvider {
  public static let id = "twitter.com"

  /**
      @brief Creates an `AuthCredential` for a Twitter sign in.

      @param token The Twitter OAuth token.
      @param secret The Twitter OAuth secret.
      @return An AuthCredential containing the Twitter credentials.
   */
  public static func credential(withToken token: String, secret: String) -> AuthCredential {
    return TwitterAuthCredential(withToken: token, secret: secret)
  }
}

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
struct TwitterAuthCredential: AuthCredential, Codable {
  let token: String
  let secret: String
    var provider: String { TwitterAuthProvider.id }

  init(withToken token: String, secret: String) {
    self.token = token
    self.secret = secret
  }

    func prepare(_ request: inout VerifyAssertionRequest) {
        request.providerAccessToken = token
        request.providerOAuthTokenSecret = secret
    }

    enum CodingKeys: CodingKey {
        case token
        case secret
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.token, forKey: .token)
        try container.encode(self.secret, forKey: .secret)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try container.decode(String.self, forKey: .token)
        self.secret = try container.decode(String.self, forKey: .secret)
    }
}
