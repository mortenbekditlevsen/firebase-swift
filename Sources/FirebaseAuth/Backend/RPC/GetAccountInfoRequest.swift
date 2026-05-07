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

/** @var kGetAccountInfoEndpoint
    @brief The "getAccountInfo" endpoint.
 */
private let kGetAccountInfoEndpoint = "getAccountInfo"


/** @class FIRGetAccountInfoRequest
    @brief Represents the parameters for the getAccountInfo endpoint.
    @see https://developers.google.com/identity/toolkit/web/reference/relyingparty/getAccountInfo
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct GetAccountInfoRequest: IdentityToolkitRequest,
                                      AuthRPCRequest, Encodable {
     public typealias Response = GetAccountInfoResponse
     
     /** @property accessToken
      @brief The STS Access Token for the authenticated user.
      */
     public let accessToken: String
     
     
     /** @var response
      @brief The corresponding response for this request
      */
     
     /** @fn initWithAccessToken:requestConfiguration
      @brief Designated initializer.
      @param accessToken The Access Token of the authenticated user.
      @param requestConfiguration An object containing configurations to be added to the request.
      */
     public var useStaging: Bool { false }
     public var useIdentityPlatform: Bool { false }
     public var endpoint: String { kGetAccountInfoEndpoint }
     public var requestConfiguration: AuthRequestConfiguration
     
     public init(accessToken: String, requestConfiguration: AuthRequestConfiguration) {
         self.accessToken = accessToken
         self.requestConfiguration = requestConfiguration
     }
     
     enum CodingKeys: String, CodingKey {
         case IDToken = "idToken"
     }
     
     public func encode(to encoder: any Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encode(accessToken, forKey: .IDToken)
     }
 }
