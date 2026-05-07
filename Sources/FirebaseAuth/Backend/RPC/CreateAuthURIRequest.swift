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

/** @var kCreateAuthURIEndpoint
    @brief The "createAuthUri" endpoint.
 */
private let kCreateAuthURIEndpoint = "createAuthUri"

/** @var kProviderIDKey
    @brief The key for the "providerId" value in the request.
 */
private let kProviderIDKey = "providerId"

/** @var kIdentifierKey
    @brief The key for the "identifier" value in the request.
 */
private let kIdentifierKey = "identifier"

/** @var kContinueURIKey
    @brief The key for the "continueUri" value in the request.
 */
private let kContinueURIKey = "continueUri"

/** @var kOpenIDRealmKey
    @brief The key for the "openidRealm" value in the request.
 */
private let kOpenIDRealmKey = "openidRealm"

/** @var kClientIDKey
    @brief The key for the "clientId" value in the request.
 */
private let kClientIDKey = "clientId"

/** @var kContextKey
    @brief The key for the "context" value in the request.
 */
private let kContextKey = "context"

/** @var kAppIDKey
    @brief The key for the "appId" value in the request.
 */
private let kAppIDKey = "appId"

/** @var kTenantIDKey
    @brief The key for the tenant id value in the request.
 */
private let kTenantIDKey = "tenantId"

/** @class FIRCreateAuthURIRequest
    @brief Represents the parameters for the createAuthUri endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/createAuthUri
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct CreateAuthURIRequest: IdentityToolkitRequest,
  AuthRPCRequest, Encodable {
     public typealias Response = CreateAuthURIResponse
  /** @property identifier
      @brief The email or federated ID of the user.
   */
  public let identifier: String

  /** @property continueURI
      @brief The URI to which the IDP redirects the user after the federated login flow.
   */
  public let continueURI: String

  /** @property openIDRealm
      @brief Optional realm for OpenID protocol. The sub string "scheme://domain:port" of the param
          "continueUri" is used if this is not set.
   */
  public var openIDRealm: String?

  /** @property providerID
      @brief The IdP ID. For white listed IdPs it's a short domain name e.g. google.com, aol.com,
          live.net and yahoo.com. For other OpenID IdPs it's the OP identifier.
   */
  public var providerID: String?

  /** @property clientID
      @brief The relying party OAuth client ID.
   */
  public var clientID: String?

  /** @property context
      @brief The opaque value used by the client to maintain context info between the authentication
          request and the IDP callback.
   */
  public var context: String?

  /** @property appID
      @brief The iOS client application's bundle identifier.
   */
  public var appID: String?

  /** @var response
      @brief The corresponding response for this request
   */

     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { false }
     public var endpoint: String { kCreateAuthURIEndpoint }
     public var requestConfiguration: AuthRequestConfiguration

  public init(identifier: String, continueURI: String,
                    requestConfiguration: AuthRequestConfiguration) {
    self.identifier = identifier
    self.continueURI = continueURI
      self.requestConfiguration = requestConfiguration
  }

  enum CodingKeys: String, CodingKey {
    case identifier
    case continueURI = "continueUri"
    case openIDRealm = "openidRealm"
    case providerID = "providerId"
    case clientID = "clientId"
    case context
    case appID = "appId"
    case tenantID = "tenantId"
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(identifier, forKey: .identifier)
    try c.encode(continueURI, forKey: .continueURI)
    try c.encodeIfPresent(openIDRealm, forKey: .openIDRealm)
    try c.encodeIfPresent(providerID, forKey: .providerID)
    try c.encodeIfPresent(clientID, forKey: .clientID)
    try c.encodeIfPresent(context, forKey: .context)
    try c.encodeIfPresent(appID, forKey: .appID)
    try c.encodeIfPresent(tenantID, forKey: .tenantID)
  }
}
