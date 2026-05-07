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

/** @var kVerifyCustomTokenEndpoint
    @brief The "verifyPassword" endpoint.
 */
private let kVerifyCustomTokenEndpoint = "verifyCustomToken"

/** @var kTokenKey
    @brief The key for the "token" value in the request.
 */
private let kTokenKey = "token"

/** @var kReturnSecureTokenKey
    @brief The key for the "returnSecureToken" value in the request.
 */
private let kReturnSecureTokenKey = "returnSecureToken"

/** @var kTenantIDKey
    @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct VerifyCustomTokenRequest: IdentityToolkitRequest,
  AuthRPCRequest, Encodable {
     public typealias Response = VerifyCustomTokenResponse

  public let token: String

  public var returnSecureToken: Bool

  /** @var response
      @brief The corresponding response for this request
   */

     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { false }
     public var endpoint: String { kVerifyCustomTokenEndpoint }
     public var requestConfiguration: AuthRequestConfiguration

  public init(token: String, requestConfiguration: AuthRequestConfiguration) {
    self.token = token
    returnSecureToken = true
      self.requestConfiguration = requestConfiguration
  }

  enum CodingKeys: String, CodingKey {
    case token
    case returnSecureToken
    case tenantID = "tenantId"
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(token, forKey: .token)
    if returnSecureToken { try c.encode(true, forKey: .returnSecureToken) }
    try c.encodeIfPresent(tenantID, forKey: .tenantID)
  }
}
