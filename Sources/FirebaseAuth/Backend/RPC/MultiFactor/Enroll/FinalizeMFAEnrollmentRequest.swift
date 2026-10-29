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

private let kFinalizeMFAEnrollmentEndPoint = "accounts/mfaEnrollment:finalize"

/** @var kTenantIDKey
 @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
struct FinalizeMFAEnrollmentRequest: IdentityToolkitRequest, AuthRPCRequest {
    public typealias Response = FinalizeMFAEnrollmentResponse

  var idToken: String?

  var displayName: String?

  var verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo?

  /** @var response
      @brief The corresponding response for this request
   */
  var response: AuthRPCResponse = FinalizeMFAEnrollmentResponse()

    var endpoint: String { kFinalizeMFAEnrollmentEndPoint }
    var requestConfiguration: AuthRequestConfiguration
    var useStaging: Bool { false }
    var useIdentityPlatform: Bool { true }
    
  init(idToken: String?, displayName: String?,
       verificationInfo: AuthProtoFinalizeMFAPhoneRequestInfo?,
       requestConfiguration: AuthRequestConfiguration) {
    self.idToken = idToken
    self.displayName = displayName
    self.verificationInfo = verificationInfo
      self.requestConfiguration = requestConfiguration
  }
}

extension FinalizeMFAEnrollmentRequest {
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: AuthRPCCodingKey.self)
    try c.encodeIfPresent(idToken, forKey: .init("idToken"))
    try c.encodeIfPresent(displayName, forKey: .init("displayName"))
    try c.encodeIfPresent(verificationInfo, forKey: .init("phoneVerificationInfo"))
    try c.encodeIfPresent(tenantID, forKey: .init(kTenantIDKey))
  }
}
