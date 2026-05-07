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

private let kStartMFASignInEndPoint = "accounts/mfaSignIn:start"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct StartMFASignInRequest: IdentityToolkitRequest,
  AuthRPCRequest {
     public typealias Response = StartMFASignInResponse
  var MFAPendingCredential: String?
  var MFAEnrollmentID: String?
  var signInInfo: AuthProtoStartMFAPhoneRequestInfo?

  /** @var response
      @brief The corresponding response for this request
   */

     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { true }
     public var endpoint: String { kStartMFASignInEndPoint }
     public var requestConfiguration: AuthRequestConfiguration

  init(MFAPendingCredential: String?, MFAEnrollmentID: String?,
       signInInfo: AuthProtoStartMFAPhoneRequestInfo?,
       requestConfiguration: AuthRequestConfiguration) {
      self.MFAPendingCredential = MFAPendingCredential
      self.MFAEnrollmentID = MFAEnrollmentID
      self.signInInfo = signInInfo
      self.requestConfiguration = requestConfiguration
  }
     
     enum CodingKeys: String, CodingKey {
         case mfaPendingCredential
         case mfaEnrollmentId
         case phoneSignInInfo
         case tenantId
     }
     
     public func encode(to encoder: any Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encodeIfPresent(MFAPendingCredential, forKey: .mfaPendingCredential)
         try container.encodeIfPresent(MFAEnrollmentID, forKey: .mfaEnrollmentId)
         try container.encodeIfPresent(signInInfo, forKey: .phoneSignInInfo)
         try container.encodeIfPresent(tenantID, forKey: .tenantId)

     }
}
