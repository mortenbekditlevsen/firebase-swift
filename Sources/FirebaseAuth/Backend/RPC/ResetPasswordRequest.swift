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

/** @var kResetPasswordEndpoint
    @brief The "resetPassword" endpoint.
 */
private let kResetPasswordEndpoint = "resetPassword"

/** @var kOOBCodeKey
    @brief The "resetPassword" key.
 */
private let kOOBCodeKey = "oobCode"

/** @var kCurrentPasswordKey
    @brief The "newPassword" key.
 */
private let kCurrentPasswordKey = "newPassword"

/** @var kTenantIDKey
    @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct ResetPasswordRequest: IdentityToolkitRequest,
  AuthRPCRequest, Encodable {
     public typealias Response = ResetPasswordResponse

  /** @property oobCode
      @brief The oobCode sent in the request.
   */
     
  public let oobCode: String

  /** @property updatedPassword
      @brief The new password sent in the request.
   */
  public let updatedPassword: String?

  /** @var response
      @brief The corresponding response for this request
   */

  /** @fn initWithOobCode:newPassword:requestConfiguration:
      @brief Designated initializer.
      @param oobCode The OOB Code.
      @param newPassword The new password.
      @param requestConfiguration An object containing configurations to be added to the request.
   */
     
     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { false }
     public var endpoint: String { kResetPasswordEndpoint }
     public var requestConfiguration: AuthRequestConfiguration

  public init(oobCode: String, newPassword: String?,
                    requestConfiguration: AuthRequestConfiguration) {
    self.oobCode = oobCode
    updatedPassword = newPassword
      self.requestConfiguration = requestConfiguration
  }

  enum CodingKeys: String, CodingKey {
    case oobCode
    case updatedPassword = "newPassword"
    case tenantID = "tenantId"
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(oobCode, forKey: .oobCode)
    try c.encodeIfPresent(updatedPassword, forKey: .updatedPassword)
    try c.encodeIfPresent(tenantID, forKey: .tenantID)
  }
}
