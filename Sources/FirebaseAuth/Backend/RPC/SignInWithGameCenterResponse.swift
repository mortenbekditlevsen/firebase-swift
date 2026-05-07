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

public struct SignInWithGameCenterResponse:
  AuthRPCResponse, Decodable {
   public var idToken: String
  public var refreshToken: String
  public var localID: String?
  public var playerID: String?
  public var teamPlayerID: String?
  public var gamePlayerID: String?
  public var approximateExpirationDate: Date?
  public var isNewUser: Bool = false
  public var displayName: String?
    
    enum CodingKeys: String, CodingKey {
        case idToken
        case refreshToken
        case localID = "localId"
        case playerID = "playerId"
        case teamPlayerID = "teamPlayerId"
        case gamePlayerID = "gamePlayerId"
        case expiresIn
        case isNewUser
        case displayName
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idToken = try container.decode(String.self, forKey: .idToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.localID = try container.decodeIfPresent(String.self, forKey: .localID)
        self.playerID = try container.decodeIfPresent(String.self, forKey: .playerID)
        self.teamPlayerID = try container.decodeIfPresent(String.self, forKey: .teamPlayerID)
        self.gamePlayerID = try container.decodeIfPresent(String.self, forKey: .gamePlayerID)
        self.approximateExpirationDate = (try container.decodeIfPresent(RelativeDate.self, forKey: .expiresIn))?.date
        self.isNewUser = try container.decodeIfPresent(Bool.self, forKey: .isNewUser) ?? false
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

  public func setFields(dictionary: [String: Any]) throws {
  }
}
