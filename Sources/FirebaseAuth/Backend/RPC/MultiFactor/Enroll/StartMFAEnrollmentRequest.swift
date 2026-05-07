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

private let kStartMFAEnrollmentEndPoint = "accounts/mfaEnrollment:start"

/** @var kTenantIDKey
    @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 struct StartMFAEnrollmentRequest: IdentityToolkitRequest,
  AuthRPCRequest {
     public typealias Response = StartMFAEnrollmentResponse

  private(set) var idToken: String?
  private(set) var enrollmentInfo: AuthProtoStartMFAPhoneRequestInfo?

  /** @var response
      @brief The corresponding response for this request
   */
     
     var useIdentityPlatform: Bool { true }
     var useStaging: Bool { false }
     var endpoint: String { kStartMFAEnrollmentEndPoint }
     var requestConfiguration: AuthRequestConfiguration

  init(idToken: String?,
       enrollmentInfo: AuthProtoStartMFAPhoneRequestInfo?,
       requestConfiguration: AuthRequestConfiguration) {
      self.idToken = idToken
      self.enrollmentInfo = enrollmentInfo
      self.requestConfiguration = requestConfiguration
  }
     
     enum CodingKeys: CodingKey {
         case idToken
         case phoneEnrollmentInfo
         case tenantId
         
     }
     
     func encode(to encoder: any Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encodeIfPresent(idToken.self, forKey: .idToken)
         try container.encodeIfPresent(enrollmentInfo, forKey: .phoneEnrollmentInfo)
         try container.encodeIfPresent(tenantID, forKey: .tenantId)
     }
}
