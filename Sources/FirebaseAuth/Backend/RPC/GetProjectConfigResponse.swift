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

public struct GetProjectConfigResponse:
  AuthRPCResponse {
  /** @property projectID
      @brief The unique ID pertaining to the current project.
   */
  public var projectID: String?

  /** @property authorizedDomains
      @brief A list of domains allowlisted for the current project.
   */
  public var authorizedDomains: [String]?

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case authorizedDomains
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        do {
            self.authorizedDomains = try container.decodeIfPresent([String].self, forKey: .authorizedDomains)
        } catch {
            if let authorizedDomainsString = try container.decodeIfPresent(String.self, forKey: .authorizedDomains) {
                let data = Data(authorizedDomainsString.utf8)
                if let decoded = try? JSONSerialization.jsonObject(
                    with: data,
                    options: [.mutableLeaves]
                ), let array = decoded as? [String] {
                    self.authorizedDomains = array
                }
            }
        }
    }
  public func setFields(dictionary: [String: Any]) throws {
  }
}
