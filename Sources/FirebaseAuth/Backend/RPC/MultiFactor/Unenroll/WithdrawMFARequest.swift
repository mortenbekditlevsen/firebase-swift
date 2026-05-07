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

private let kWithdrawMFAEndPoint = "accounts/mfaEnrollment:withdraw"

/** @var kTenantIDKey
    @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
struct WithdrawMFARequest: IdentityToolkitRequest, AuthRPCRequest {
    public typealias Response = WithdrawMFAResponse

  public var idToken: String?
  public var mfaEnrollmentID: String?

  /** @var response
      @brief The corresponding response for this request
   */

    public var useStaging: Bool { false }
    public var useIdentityPlatform: Bool { false }
    public var endpoint: String { kWithdrawMFAEndPoint }
    public var requestConfiguration: AuthRequestConfiguration

  public init(idToken: String?,
                    mfaEnrollmentID: String?,
                    requestConfiguration: AuthRequestConfiguration) {
    self.idToken = idToken
    self.mfaEnrollmentID = mfaEnrollmentID
      self.requestConfiguration = requestConfiguration
  }
}
