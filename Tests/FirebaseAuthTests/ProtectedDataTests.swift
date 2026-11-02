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
#if os(iOS) || os(tvOS)
  @testable import FirebaseAuth
  import FirebaseCore
  import Foundation
  import Synchronization
  import Testing
  import UIKit

  /// Storage that fails like the keychain of a prewarmed app before the device is unlocked.
  private final class LockableStorage: AuthStorage {
    static let items = Mutex<[String: Data]>([:])
    static let isLocked = Mutex(false)

    init(service: String) {}

    static func storage(identifier: String) -> Self { Self(service: identifier) }

    private func checkUnlocked() throws {
      if Self.isLocked.withLock({ $0 }) {
        throw AuthErrorUtils.keychainError(function: "SecItemCopyMatching",
                                           status: errSecInteractionNotAllowed)
      }
    }

    func data(forKey key: String) throws -> Data? {
      try checkUnlocked()
      return Self.items.withLock { $0[key] }
    }

    func setData(_ data: Data, forKey key: String) throws {
      try checkUnlocked()
      Self.items.withLock { $0[key] = data }
    }

    func removeData(forKey key: String) throws {
      try checkUnlocked()
      Self.items.withLock { _ = $0.removeValue(forKey: key) }
    }
  }

  /// Upstream 2495c2019: a user saved in the keychain is loaded once protected data becomes
  /// available, when the keychain couldn't be read at launch.
  @Suite(.serialized)
  struct ProtectedDataTests {
    private func makeApp(_ name: String) -> FirebaseApp {
      FirebaseApp(options: FirebaseApp.Options(projectID: "project", googleAppID: "1:1:ios:1",
                                               apiKey: "key", clientID: nil,
                                               storageBucket: nil),
                  name: name)
    }

    @Test func theSavedUserIsLoadedOnceTheDeviceIsUnlocked() async throws {
      let name = "protected-data-\(UUID().uuidString)"
      let firstApp = makeApp(name)
      let first = Auth(app: firstApp, keychainStorageProvider: LockableStorage.self)
      var userData = UserData(withTokenService: SecureTokenService(
        withRequestConfiguration: first.requestConfiguration,
        accessToken: "access", accessTokenExpirationDate: Date(timeIntervalSinceNow: 3600),
        refreshToken: "refresh"
      ))
      userData.uid = "saved-user"
      userData.requestConfiguration = first.requestConfiguration
      let user = User(userData: userData)
      try await first.updateCurrentUser(user)
      #expect(!LockableStorage.items.withLock { $0.isEmpty })

      LockableStorage.isLocked.withLock { $0 = true }
      let relaunchedApp = makeApp(name)
      let relaunched = Auth(app: relaunchedApp, keychainStorageProvider: LockableStorage.self)
      #expect(relaunched.currentUser == nil)

      LockableStorage.isLocked.withLock { $0 = false }
      NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification,
                                      object: nil)
      #expect(relaunched.currentUser?.uid == user.uid)
      withExtendedLifetime((firstApp, relaunchedApp)) {}
    }
  }
#endif
