// Copyright 2026 Google LLC
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

protocol AppCheckCoreStorageProtocol: NSObjectProtocol {
  func setToken(_ token: AppCheckCoreToken?) async throws -> AppCheckCoreToken?
  func getToken() async throws -> AppCheckCoreToken?
}

final class AppCheckCoreStorage: NSObject, AppCheckCoreStorageProtocol {
  /// Storage service name for Keychain.
  /// Internal scope exists for testing purposes.
  /// Do not rename: retains value for compatibility with existing stored data from v11 or lower.
  static let keychainService = "com.google.app_check_core.token_storage"

  let tokenKey: String
  // firebase-swift: the app's `AppCheckKeychain` instead of GoogleUtilities' `GULKeychainStorage`,
  // which archived the stored objects itself; here they're archived below.
  let keychain: any AppCheckKeychain
  let accessGroup: String?

  init(tokenKey: String,
       keychain: any AppCheckKeychain,
       accessGroup: String?) {
    self.tokenKey = tokenKey
    self.keychain = keychain
    self.accessGroup = accessGroup
    super.init()
  }

  func getToken() async throws -> AppCheckCoreToken? {
    AppCheckCoreStoredToken.registerArchivedClassName()
    do {
      guard let data = try await keychain.data(forKey: tokenKey,
                                               service: Self.keychainService,
                                               accessGroup: accessGroup) else {
        return nil
      }
      let storedToken = try NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: data
      )
      return storedToken?.appCheckToken()
    } catch {
      // Wrap keychain error
      throw AppCheckCoreErrorUtil.keychainError(with: error)
    }
  }

  func setToken(_ token: AppCheckCoreToken?) async throws -> AppCheckCoreToken? {
    AppCheckCoreStoredToken.registerArchivedClassName()
    do {
      if let token = token {
        let storedToken = AppCheckCoreStoredToken()
        storedToken.update(with: token)
        let data = try NSKeyedArchiver.archivedData(withRootObject: storedToken,
                                                    requiringSecureCoding: true)
        try await keychain.setData(data, forKey: tokenKey, service: Self.keychainService,
                                   accessGroup: accessGroup)
        return token
      } else {
        try await keychain.removeData(forKey: tokenKey, service: Self.keychainService,
                                      accessGroup: accessGroup)
        return nil
      }
    } catch {
      throw AppCheckCoreErrorUtil.keychainError(with: error)
    }
  }
}
