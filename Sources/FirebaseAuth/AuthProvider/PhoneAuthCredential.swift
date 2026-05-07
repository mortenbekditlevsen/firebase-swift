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

/** @class PhoneAuthCredential
    @brief Implementation of FIRAuthCredential for Phone Auth credentials.
        This class is available on iOS only.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct PhoneAuthCredential: AuthCredential, Codable {
  enum CredentialKind {
    case phoneNumber(_ phoneNumber: String, _ temporaryProof: String)
    case verification(_ id: String, _ code: String)
  }

  let credentialKind: CredentialKind
     public var provider: String { PhoneAuthProvider.id }
  init(withTemporaryProof temporaryProof: String, phoneNumber: String) {
    credentialKind = .phoneNumber(phoneNumber, temporaryProof)
  }

  init(verificationID: String, verificationCode: String) {
      credentialKind = .verification(verificationID, verificationCode)
  }
     
     enum CodingKeys: CodingKey {
         case phoneNumber, temporaryProof, verificationID, verificationCode
     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         switch credentialKind {
         case let .phoneNumber(phoneNumber, temporaryProof):
             try container.encode(phoneNumber, forKey: .phoneNumber)
             try container.encode(temporaryProof, forKey: .temporaryProof)
         case let .verification(id, code):
             try container.encode(id, forKey: .verificationID)
             try container.encode(code, forKey: .verificationCode)
         }
     }

     public init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         if let phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber), let temporaryProof = try container.decodeIfPresent(String.self, forKey: .temporaryProof) {
             self.credentialKind = .phoneNumber(phoneNumber, temporaryProof)
         } else if let verificationID = try container.decodeIfPresent(String.self, forKey: .verificationID), let verificationCode = try container.decodeIfPresent(String.self, forKey: .verificationCode) {
             self.credentialKind = .verification(verificationID, verificationCode)
         } else {
             // XXX TODO
             throw DecodingError.typeMismatch(String.self, .init(codingPath: [], debugDescription: "xxx"))
         }

  }
}
