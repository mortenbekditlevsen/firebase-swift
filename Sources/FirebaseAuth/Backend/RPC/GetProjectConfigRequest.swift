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

/** @var kGetProjectConfigEndPoint
    @brief The "getProjectConfig" endpoint.
 */
private let kGetProjectConfigEndPoint = "getProjectConfig"

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
public struct GetProjectConfigRequest: IdentityToolkitRequest,
                                       AuthRPCRequest {
    public typealias Response = GetProjectConfigResponse
        
    public var useStaging: Bool { false }
    public var useIdentityPlatform: Bool { false }
    public var endpoint: String { kGetProjectConfigEndPoint }
    public var requestConfiguration: AuthRequestConfiguration
    
    public init(requestConfiguration: AuthRequestConfiguration) {
        self.requestConfiguration = requestConfiguration
    }
    
    public func containsPostBody() -> Bool { false }
}
