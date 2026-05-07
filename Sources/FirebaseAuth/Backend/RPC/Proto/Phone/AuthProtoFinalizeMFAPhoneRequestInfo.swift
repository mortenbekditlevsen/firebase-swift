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


public struct AuthProtoFinalizeMFAPhoneRequestInfo:
  Decodable, Sendable /* AuthProto */ {

  var sessionInfo: String?
  var code: String?
  public init(sessionInfo: String?, verificationCode: String?) {
    self.sessionInfo = sessionInfo
    code = verificationCode
  }
    
    enum CodingKeys: CodingKey {
        case sessionInfo
        case code
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionInfo = try container.decodeIfPresent(String.self, forKey: .sessionInfo)
        self.code = try container.decodeIfPresent(String.self, forKey: .code)
    }

  public var dictionary: [String: Any] {
      [:]
  }
}
