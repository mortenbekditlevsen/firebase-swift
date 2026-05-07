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
 @brief A concrete implementation of `AuthProvider` for Email & Password Sign In.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public enum EmailAuthProvider {
  public static let id = "password"

  /**
      @brief Creates an `AuthCredential` for an email & password sign in.

      @param email The user's email address.
      @param password The user's password.
      @return An `AuthCredential` containing the email & password credential.
   */
  public static func credential(withEmail email: String, password: String) -> AuthCredential {
    return EmailAuthCredential(withEmail: email, password: password)
  }

  /** @fn credentialWithEmail:Link:
      @brief Creates an `AuthCredential` for an email & link sign in.

      @param email The user's email address.
      @param link The email sign-in link.
      @return An `AuthCredential` containing the email & link credential.
   */
  public static func credential(withEmail email: String, link: String) -> AuthCredential {
    return EmailAuthCredential(withEmail: email, link: link)
  }
}

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
struct EmailAuthCredential: AuthCredential, Codable {
  let email: String

  enum EmailType {
    case password(String)
    case link(String)
  }

  let emailType: EmailType
    var provider: String { EmailAuthProvider.id }

  init(withEmail email: String, password: String) {
    self.email = email
    emailType = .password(password)
  }

  init(withEmail email: String, link: String) {
    self.email = email
    emailType = .link(link)
  }

    enum CodingKeys: String, CodingKey {
        case email
        case link
        case password
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        switch emailType {
        case .link(let link):
            try container.encode(link, forKey: .link)
        case .password(let password):
            try container.encode(password, forKey: .password)
        }
    }

     init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decode(String.self, forKey: .email)
        if let link = try container.decodeIfPresent(String.self, forKey: .link) {
            self.emailType = .link(link)
        } else {
            let password = try container.decode(String.self, forKey: .password)
            self.emailType = .password(password)
        }
    }

}
