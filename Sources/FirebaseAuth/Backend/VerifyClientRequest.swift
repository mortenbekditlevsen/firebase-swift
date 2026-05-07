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

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)

public struct VerifyClientRequest: IdentityToolkitRequest, AuthRPCRequest, Encodable {
    public typealias Response = VerifyClientResponse

  /// The endpoint for the verifyClient request.
  private static let verifyClientEndpoint = "verifyClient"

  /// The key for the appToken request paramenter.
  private static let appTokenKey = "appToken"

  /// The key for the isSandbox request parameter.
  private static let isSandboxKey = "isSandbox"

  /** @var response
      @brief The corresponding response for this request
   */
  
    enum CodingKeys: CodingKey {
        case appToken
        case isSandbox
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.appToken, forKey: .appToken)
        try container.encode(self.isSandbox, forKey: .isSandbox)
    }

  /// The APNS device token.
  public private(set) var appToken: String?

  /// The flag that denotes if the appToken  pertains to Sandbox or Production.
  public private(set) var isSandbox: Bool
    
    public var requestConfiguration: AuthRequestConfiguration
    
    var endpoint: String {
        Self.verifyClientEndpoint
    }
    var useStaging: Bool { false }
    var useIdentityPlatform: Bool { false }

  public init(withAppToken: String?,
                    isSandbox: Bool,
                    requestConfiguration: AuthRequestConfiguration) {
    appToken = withAppToken
    self.isSandbox = isSandbox
      self.requestConfiguration = requestConfiguration
  }
}
