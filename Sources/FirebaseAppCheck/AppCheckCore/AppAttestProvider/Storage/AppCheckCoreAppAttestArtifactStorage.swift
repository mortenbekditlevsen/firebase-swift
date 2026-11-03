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

// firebase-swift: App Attest is Apple-only (DeviceCheck).
#if canImport(DeviceCheck)

import Foundation

protocol AppCheckCoreAppAttestArtifactStorageProtocol: NSObjectProtocol {
  func setArtifact(_ artifact: Data?, forKey keyID: String) async throws -> Data?
  func getArtifact(forKey keyID: String) async throws -> Data?
}

final class AppCheckCoreAppAttestArtifactStorage: NSObject,
  AppCheckCoreAppAttestArtifactStorageProtocol {
  /// Storage service name for Keychain.
  /// Internal scope exists for testing purposes.
  /// Do not rename: retains value for compatibility with existing stored data from v11 or lower.
  static let keychainService = "com.firebase.app_check.app_attest_artifact_storage"

  private let keySuffix: String
  // firebase-swift: the app's `AppCheckKeychain` instead of GoogleUtilities' `GULKeychainStorage`,
  // which archived the stored objects itself; here they're archived below.
  private let keychain: any AppCheckKeychain
  private let accessGroup: String?

  init(keySuffix: String, keychain: any AppCheckKeychain, accessGroup: String?) {
    self.keySuffix = keySuffix
    self.keychain = keychain
    self.accessGroup = accessGroup
    super.init()
  }

  func getArtifact(forKey keyID: String) async throws -> Data? {
    AppCheckCoreAppAttestStoredArtifact.registerArchivedClassName()
    do {
      guard let data = try await keychain.data(forKey: artifactKey,
                                               service: Self.keychainService,
                                               accessGroup: accessGroup) else {
        return nil
      }
      let storedArtifact = try NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreAppAttestStoredArtifact.self,
        from: data
      )

      if let artifact = storedArtifact,
         artifact.keyID == keyID {
        return artifact.artifact
      } else {
        return nil
      }
    } catch {
      throw AppCheckCoreErrorUtil.keychainError(with: error)
    }
  }

  func setArtifact(_ artifact: Data?, forKey keyID: String) async throws -> Data? {
    if let artifact = artifact {
      return try await storeArtifact(artifact, forKey: keyID)
    } else {
      do {
        try await keychain.removeData(forKey: artifactKey, service: Self.keychainService,
                                      accessGroup: accessGroup)
        return nil
      } catch {
        throw AppCheckCoreErrorUtil.keychainError(with: error)
      }
    }
  }

  private func storeArtifact(_ artifact: Data, forKey keyID: String) async throws -> Data {
    AppCheckCoreAppAttestStoredArtifact.registerArchivedClassName()
    let storedArtifact = AppCheckCoreAppAttestStoredArtifact(keyID: keyID, artifact: artifact)

    do {
      let data = try NSKeyedArchiver.archivedData(withRootObject: storedArtifact,
                                                  requiringSecureCoding: true)
      try await keychain.setData(data, forKey: artifactKey, service: Self.keychainService,
                                 accessGroup: accessGroup)
      return artifact
    } catch {
      throw AppCheckCoreErrorUtil.keychainError(with: error)
    }
  }

  private var artifactKey: String {
    return "app_check_app_attest_artifact.\(keySuffix)"
  }
}

#endif // canImport(DeviceCheck)
