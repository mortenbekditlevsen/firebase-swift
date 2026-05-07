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

#if os(macOS) || os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
  import Foundation
  import GameKit

  /**
   @brief A concrete implementation of `AuthProvider` for Game Center Sign In. Not available on watchOS.
   */
  @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
   public enum GameCenterAuthProvider {
    public static let id = "gc.apple.com"

    /** @fn
        @brief Creates an `AuthCredential` for a Game Center sign in.
     */
    public static func getCredential() async throws -> AuthCredential {
      /**
       Linking GameKit.framework without using it on macOS results in App Store rejection.
       Thus we don't link GameKit.framework to our SDK directly. `optionalLocalPlayer` is used for
       checking whether the APP that consuming our SDK has linked GameKit.framework. If not, a
       `GameKitNotLinkedError` will be raised.
       **/
      guard let _: AnyClass = NSClassFromString("GKLocalPlayer") else {
        throw AuthErrorUtils.gameKitNotLinkedError()
      }

      let localPlayer = GKLocalPlayer.local
      guard localPlayer.isAuthenticated else {
        throw AuthErrorUtils.localPlayerNotAuthenticatedError()
      }

      if #available(iOS 13.5, macOS 15.0.5, macCatalyst 13.5, tvOS 13.4.8, *) {
        let (publicKeyURL, signature, salt, timestamp) = try await localPlayer.fetchItemsForIdentityVerificationSignature()
          return GameCenterAuthCredential(withPlayerID: localPlayer.playerID,
                                          teamPlayerID: localPlayer.teamPlayerID,
                                          gamePlayerID: localPlayer.gamePlayerID,
                                          publicKeyURL: publicKeyURL,
                                          signature: signature,
                                          salt: salt,
                                          timestamp: timestamp,
                                          displayName: localPlayer.displayName)
      } else {
          let (publicKeyURL, signature, salt, timestamp) = try await localPlayer
              .generateIdentityVerificationSignature()
          /**
           @c `localPlayer.alias` is actually the displayname needed, instead of
           `localPlayer.displayname`. For more information, check
           https://developer.apple.com/documentation/gamekit/gkplayer
           **/
          let displayName = localPlayer.alias
          return GameCenterAuthCredential(withPlayerID: localPlayer.playerID,
                                          teamPlayerID: nil,
                                          gamePlayerID: nil,
                                          publicKeyURL: publicKeyURL,
                                          signature: signature,
                                          salt: salt,
                                          timestamp: timestamp,
                                          displayName: displayName)
      }
    }

    /** @fn
        @brief Creates an `AuthCredential` for a Game Center sign in.
     */
  }

  // Change to internal
  @available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
  
  public struct GameCenterAuthCredential: AuthCredential, Codable {
    public let playerID: String
    public let teamPlayerID: String?
    public let gamePlayerID: String?
    public let publicKeyURL: URL?
    public let signature: Data?
    public let salt: Data?
    public let timestamp: UInt64
    public let displayName: String
      
      public var provider: String {GameCenterAuthProvider.id}

    /**
        @brief Designated initializer.
        @param playerID The ID of the Game Center local player.
        @param teamPlayerID The teamPlayerID of the Game Center local player.
        @param gamePlayerID The gamePlayerID of the Game Center local player.
        @param publicKeyURL The URL for the public encryption key.
        @param signature The verification signature generated.
        @param salt A random string used to compute the hash and keep it randomized.
        @param timestamp The date and time that the signature was created.
        @param displayName The display name of the Game Center player.
     */
    init(withPlayerID playerID: String, teamPlayerID: String?, gamePlayerID: String?,
         publicKeyURL: URL?, signature: Data?, salt: Data?,
         timestamp: UInt64, displayName: String) {
      self.playerID = playerID
      self.teamPlayerID = teamPlayerID
      self.gamePlayerID = gamePlayerID
      self.publicKeyURL = publicKeyURL
      self.signature = signature
      self.salt = salt
      self.timestamp = timestamp
      self.displayName = displayName
    }


      enum CodingKeys: CodingKey {
          case playerID
          case teamPlayerID
          case gamePlayerID
          case publicKeyURL
          case signature
          case salt
          case timestamp
          case displayName
      }

      public func encode(to encoder: Encoder) throws {
          var container = encoder.container(keyedBy: CodingKeys.self)
          try container.encode(self.playerID, forKey: .playerID)
          try container.encodeIfPresent(self.teamPlayerID, forKey: .teamPlayerID)
          try container.encodeIfPresent(self.gamePlayerID, forKey: .gamePlayerID)
          try container.encodeIfPresent(self.publicKeyURL, forKey: .publicKeyURL)
          try container.encodeIfPresent(self.signature, forKey: .signature)
          try container.encodeIfPresent(self.salt, forKey: .salt)
          try container.encode(self.timestamp, forKey: .timestamp)
          try container.encode(self.displayName, forKey: .displayName)
      }

      public init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          self.playerID = try container.decode(String.self, forKey: .playerID)
          self.teamPlayerID = try container.decode(String.self, forKey: .teamPlayerID)
          self.gamePlayerID = try container.decode(String.self, forKey: .gamePlayerID)
          self.timestamp = try container.decode(UInt64.self, forKey: .timestamp)

          self.displayName = try container.decode(String.self, forKey: .displayName)

          self.publicKeyURL = try container.decodeIfPresent(URL.self, forKey: .publicKeyURL)
          self.signature = try container.decodeIfPresent(Data.self, forKey: .signature)
          self.salt = try container.decodeIfPresent(Data.self, forKey: .salt)
      }
  }
#endif
