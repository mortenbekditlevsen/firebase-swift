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

private let kHttpsProtocol = "https:"
private let kHttpProtocol = "http:"

private let kEmulatorHostAndPrefixFormat = "%@/%@"

private let gAPIHost = "www.googleapis.com"

private let kFirebaseAuthAPIHost = "www.googleapis.com"
private let kIdentityPlatformAPIHost = "identitytoolkit.googleapis.com"

private let kFirebaseAuthStagingAPIHost = "staging-www.sandbox.googleapis.com"
private let kIdentityPlatformStagingAPIHost =
  "staging-identitytoolkit.sandbox.googleapis.com"

/** @class FIRIdentityToolkitRequest
 @brief Represents a request to an identity toolkit endpoint.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
protocol IdentityToolkitRequest: AuthRPCRequest {
    /** @property endpoint
     @brief Gets the RPC's endpoint.
     */
    var endpoint: String { get }
    
    /** @property APIKey
     @brief Gets the client's API key used for the request.
     */
    var apiKey: String { get }
    
    /** @property tenantID
     @brief The tenant ID of the request. nil if none is available.
     */
    var tenantID: String? { get }
    
    var requestConfiguration: AuthRequestConfiguration { get }
    
    var useIdentityPlatform: Bool { get }
    
    var  useStaging: Bool { get }
    
    //     public init(
    //        endpoint: String,
    //        requestConfiguration: AuthRequestConfiguration,
    //        useIdentityPlatform: Bool = false,
    //        useStaging: Bool = false
    //     ) {
    //    self.endpoint = endpoint
    //    apiKey = requestConfiguration.apiKey
    //    _requestConfiguration = requestConfiguration
    //    _useIdentityPlatform = useIdentityPlatform
    //    _useStaging = useStaging
    //    tenantID = requestConfiguration.auth?.tenantID
    //  }
}

extension IdentityToolkitRequest {
    
    public var tenantID: String? { requestConfiguration.tenantId }
    public var apiKey: String { requestConfiguration.apiKey }
    
    public func containsPostBody() -> Bool {
        true
    }

  /** @fn requestURL
   @brief Gets the request's full URL.
   */
  public func requestURL() -> URL {
    let apiProtocol: String
    let apiHostAndPathPrefix: String
    let urlString: String
    let emulatorHostAndPort = requestConfiguration.emulatorHostAndPort
    if useIdentityPlatform {
      if let emulatorHostAndPort = emulatorHostAndPort {
        apiProtocol = kHttpProtocol
        apiHostAndPathPrefix = "\(emulatorHostAndPort)/\(kIdentityPlatformAPIHost)"
      } else if useStaging {
        apiHostAndPathPrefix = kIdentityPlatformStagingAPIHost
        apiProtocol = kHttpsProtocol
      } else {
        apiHostAndPathPrefix = kIdentityPlatformAPIHost
        apiProtocol = kHttpsProtocol
      }
      urlString = "\(apiProtocol)//\(apiHostAndPathPrefix)/v2/\(endpoint)?key=\(apiKey)"

    } else {
      if let emulatorHostAndPort = emulatorHostAndPort {
        apiProtocol = kHttpProtocol
        apiHostAndPathPrefix = "\(emulatorHostAndPort)/\(kFirebaseAuthAPIHost)"
      } else if useStaging {
        apiProtocol = kHttpsProtocol
        apiHostAndPathPrefix = kFirebaseAuthStagingAPIHost
      } else {
        apiProtocol = kHttpsProtocol
        apiHostAndPathPrefix = kFirebaseAuthAPIHost
      }
      urlString =
        "\(apiProtocol)//\(apiHostAndPathPrefix)/identitytoolkit/v3/relyingparty/\(endpoint)?key=\(apiKey)"
    }
    return URL(string: urlString)!
  }
}
