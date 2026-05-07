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

/** @var kReceiptKey
    @brief The key used to encode the receipt property for NSSecureCoding.
 */
private let kReceiptKey = "receipt"

/** @var kSecretKey
    @brief The key used to encode the secret property for NSSecureCoding.
 */
private let kSecretKey = "secret"

private let kFiveMinutes = 5 * 60.0

/** @class FIRAuthAppCredential
    @brief A class represents a credential that proves the identity of the app.
 */
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
 public struct SecureTokenService: Codable, Sendable, Equatable {
  /** @property requestConfiguration
      @brief The configuration for making requests to server.
   */
  public var requestConfiguration: AuthRequestConfiguration?

  /** @property accessToken
      @brief The cached access token.
      @remarks This method is specifically for providing the access token to internal clients during
          deserialization and sign-in events, and should not be used to retrieve the access token by
          anyone else.
   */
  public var accessToken: String

  /** @property refreshToken
      @brief The refresh token for the user, or @c nil if the user has yet completed sign-in flow.
      @remarks This property needs to be set manually after the instance is decoded from archive.
   */
  public var refreshToken: String?

  /** @property accessTokenExpirationDate
      @brief The expiration date of the cached access token.
   */
  public var accessTokenExpirationDate: Date?

  /** @fn initWithRequestConfiguration:accessToken:accessTokenExpirationDate:refreshToken
      @brief Creates a @c FIRSecureTokenService with access and refresh tokens.
      @param requestConfiguration The configuration for making requests to server.
      @param accessToken The STS access token.
      @param accessTokenExpirationDate The approximate expiration date of the access token.
      @param refreshToken The STS refresh token.
   */
  public init(withRequestConfiguration requestConfiguration: AuthRequestConfiguration?,
                    accessToken: String,
                    accessTokenExpirationDate: Date?,
                    refreshToken: String) {
    self.requestConfiguration = requestConfiguration
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.accessTokenExpirationDate = accessTokenExpirationDate
//    taskQueue = AuthSerialTaskQueue()
  }

  /** @fn fetchAccessTokenForcingRefresh:callback:
      @brief Fetch a fresh ephemeral access token for the ID associated with this instance. The token
          received in the callback should be considered short lived and not cached.
      @param forceRefresh Forces the token to be refreshed.
      @param callback Callback block that will be called to return either the token or an error.
          Invoked asyncronously on the auth global work queue in the future.
   */
          
  public mutating func fetchAccessToken(forcingRefresh forceRefresh: Bool) async throws -> (String, Bool) {

      // XXX TODO mutable self capture in concurrent code...
//      try await taskQueue.enqueue {
          if !forceRefresh, self.hasValidAccessToken() {
              return (self.accessToken, false)
          } else {
              AuthLog.logDebug(code: "I-AUT000017", message: "Fetching new token from backend.")
              
              return try await self.requestAccessToken(retryIfExpired: true)
          }

//      }
  }

//  private let taskQueue: AuthSerialTaskQueue<(String, Bool)>

     enum CodingKeys: String, CodingKey {
         case APIKey, refreshToken, accessToken, accessTokenExpirationDate
     }

     public init(from decoder: Decoder) throws {
         let container = try decoder.container(keyedBy: CodingKeys.self)
         refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
         accessToken = try container.decode(String.self, forKey: .accessToken)
         accessTokenExpirationDate = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpirationDate)
         requestConfiguration = nil
//         taskQueue = AuthSerialTaskQueue()
     }

     public func encode(to encoder: Encoder) throws {
         var container = encoder.container(keyedBy: CodingKeys.self)
         try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
         try container.encode(accessToken, forKey: .accessToken)
         try container.encodeIfPresent(accessTokenExpirationDate, forKey: .accessTokenExpirationDate)

     }

  // MARK: Private methods

  /** @fn requestAccessToken:
      @brief Makes a request to STS for an access token.
      @details This handles both the case that the token has not been granted yet and that it just
          needs to be refreshed. The caller is responsible for making sure that this is occurring in
          a @c _taskQueue task.
      @param callback Called when the fetch is complete. Invoked asynchronously on the main thread in
          the future.
      @remarks Because this method is guaranteed to only be called from tasks enqueued in
          @c _taskQueue, we do not need any @synchronized guards around access to _accessToken/etc.
          since only one of those tasks is ever running at a time, and those tasks are the only
          access to and mutation of these instance variables.
   */
  private mutating func requestAccessToken(retryIfExpired: Bool) async throws -> (String, Bool) {
      // TODO: This was a crash in ObjC SDK, should it callback with an error?
      guard let refreshToken, let requestConfiguration else {
          fatalError("refreshToken and requestConfiguration should not be nil")
      }

      let request = SecureTokenRequest.refreshRequest(refreshToken: refreshToken,
                                                      requestConfiguration: requestConfiguration)
      let response = try await AuthBackend.post(withRequest: request)
      var tokenUpdated = false
      let newAccessToken = response.accessToken
      if !newAccessToken.isEmpty,
         newAccessToken != self.accessToken {
          let tokenResult = AuthTokenResult.tokenResult(token: newAccessToken)
          // There is an edge case where the request for a new access token may be made right
          // before the app goes inactive, resulting in the callback being invoked much later
          // with an expired access token. This does not fully solve the issue, as if the
          // callback is invoked less than an hour after the request is made, a token is not
          // re-requested here but the approximateExpirationDate will still be off since that
          // is computed at the time the token is received.
          if retryIfExpired,
             let expirationDate = tokenResult?.expirationDate,
             expirationDate.timeIntervalSinceNow <= kFiveMinutes {
              // We only retry once, to avoid an infinite loop in the case that an end-user has
              // their local time skewed by over an hour.
              return try await self.requestAccessToken(retryIfExpired: false)
          }
          self.accessToken = newAccessToken
          self.accessTokenExpirationDate = response.approximateExpirationDate
          tokenUpdated = true
          AuthLog.logDebug(
            code: "I-AUT000017",
            message: "Updated access token. Estimated expiration date: " +
            "\(String(describing: self.accessTokenExpirationDate)), current date: \(Date())"
          )
      }
      if let newRefreshToken = response.refreshToken,
         newRefreshToken != self.refreshToken {
          self.refreshToken = newRefreshToken
          tokenUpdated = true
      }
      return (response.accessToken, tokenUpdated)
  }

  private func hasValidAccessToken() -> Bool {
    if let accessTokenExpirationDate,
       accessTokenExpirationDate.timeIntervalSinceNow > kFiveMinutes {
      AuthLog.logDebug(code: "I-AUT000017",
                       message: "Has valid access token. Estimated expiration date:" +
                         "\(accessTokenExpirationDate), current date: \(Date())")
      return true
    }
    AuthLog.logDebug(code: "I-AUT000017",
                     message: "Does not have valid access token. Estimated expiration date:" +
                       "\(String(describing: accessTokenExpirationDate)), current date: \(Date())")
    return false
  }
}
