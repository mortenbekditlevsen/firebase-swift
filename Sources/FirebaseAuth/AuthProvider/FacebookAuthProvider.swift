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
 @brief Utility class for constructing Facebook Sign In credentials.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
public enum FacebookAuthProvider {
    public static let id = "facebook.com"
    
    /**
     @brief Creates an `AuthCredential` for a Facebook sign in.
     
     @param accessToken The Access Token from Facebook.
     @return An AuthCredential containing the Facebook credentials.
     */
    public static func credential(withAccessToken accessToken: String) -> AuthCredential {
        return FacebookAuthCredential(withAccessToken: accessToken)
    }
}

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
struct FacebookAuthCredential: AuthCredential, Codable {
  let accessToken: String
    var provider: String { FacebookAuthProvider.id }
    
  init(withAccessToken accessToken: String) {
    self.accessToken = accessToken
  }

    func prepare(_ request: inout VerifyAssertionRequest) {
    request.providerAccessToken = accessToken
  }

    enum CodingKeys: CodingKey {
        case accessToken
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.accessToken, forKey: .accessToken)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)

    }
}
