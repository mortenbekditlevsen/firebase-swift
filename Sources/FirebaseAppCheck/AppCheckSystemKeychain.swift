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

#if canImport(Security)

  import Foundation
  import Security
  import Synchronization

  /// The default `AppCheckKeychain` on Apple platforms: the data protection keychain, as upstream
  /// stores App Check's items (GoogleUtilities' `GULKeychainStorage`).
  ///
  /// Items are generic passwords with the service as `kSecAttrService` and the key as
  /// `kSecAttrAccount`, readable after the first unlock and not synced or restored to other
  /// devices (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Items the Firebase iOS SDK
  /// stored are read, so tokens survive a switch to this port.
  ///
  /// Processes without the entitlement the data protection keychain needs, such as unsigned
  /// command line tools and `swift test` runners on macOS, keep the items in memory instead, so
  /// they aren't kept between launches. Upstream fails every token request there.
  public final class AppCheckSystemKeychain: AppCheckKeychain {
    /// Items kept in memory when the process can't use the data protection keychain.
    private let memoryItems = Mutex<[String: Data]>([:])

    /// Whether items go to the data protection keychain. Tests on macOS use the file-based
    /// keychain instead, which unsigned processes can use.
    private let usesDataProtectionKeychain: Bool

    public convenience init() {
      self.init(usesDataProtectionKeychain: true)
    }

    init(usesDataProtectionKeychain: Bool) {
      self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    /// Whether items are kept in memory, because the process can't use the data protection
    /// keychain.
    private var usesMemory: Bool {
      usesDataProtectionKeychain && !Self.isDataProtectionKeychainAvailable
    }

    public func data(forKey key: String, service: String,
                     accessGroup: String?) async throws -> Data? {
      guard !usesMemory else {
        return memoryItems.withLock { $0[Self.memoryKey(key, service, accessGroup)] }
      }
      var query = itemQuery(key: key, service: service, accessGroup: accessGroup)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      switch status {
      case errSecSuccess:
        return result as? Data
      case errSecItemNotFound:
        return nil
      default:
        throw Self.error(function: "SecItemCopyMatching", status: status)
      }
    }

    public func setData(_ data: Data, forKey key: String, service: String,
                        accessGroup: String?) async throws {
      guard !usesMemory else {
        memoryItems.withLock { $0[Self.memoryKey(key, service, accessGroup)] = data }
        return
      }
      let query = itemQuery(key: key, service: service, accessGroup: accessGroup)
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      var function = "SecItemAdd"
      var status = SecItemAdd(item as CFDictionary, nil)
      if status == errSecDuplicateItem {
        function = "SecItemUpdate"
        status = SecItemUpdate(query as CFDictionary,
                               [kSecValueData as String: data] as CFDictionary)
      }
      guard status == errSecSuccess else {
        throw Self.error(function: function, status: status)
      }
    }

    public func removeData(forKey key: String, service: String,
                           accessGroup: String?) async throws {
      guard !usesMemory else {
        _ = memoryItems.withLock { $0.removeValue(forKey: Self.memoryKey(key, service, accessGroup)) }
        return
      }
      let query = itemQuery(key: key, service: service, accessGroup: accessGroup)
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw Self.error(function: "SecItemDelete", status: status)
      }
    }

    /// Whether this process can use the data protection keychain. Checked once per process, with
    /// a write: lookups of missing items succeed without the entitlement.
    static let isDataProtectionKeychainAvailable: Bool = {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.firebase.app_check.keychain_availability_check",
        kSecAttrAccount as String: "com.firebase.app_check.keychain_availability_check",
        kSecUseDataProtectionKeychain as String: true,
      ]
      var item = query
      item[kSecValueData as String] = Data([0])
      let status = SecItemAdd(item as CFDictionary, nil)
      SecItemDelete(query as CFDictionary)
      guard status != errSecMissingEntitlement else {
        logger.warning("""
        I-FAA005002: This process can't use the data protection keychain (it isn't signed with \
        a keychain entitlement), so App Check keeps its token in memory and gets a new one each \
        launch.
        """)
        return false
      }
      return true
    }()

    /// As `GULKeychainStorage`'s query.
    private func itemQuery(key: String, service: String, accessGroup: String?) -> [String: Any] {
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]
      query[kSecAttrAccessGroup as String] = accessGroup
      if usesDataProtectionKeychain {
        query[kSecUseDataProtectionKeychain as String] = true
      }
      return query
    }

    private static func memoryKey(_ key: String, _ service: String,
                                  _ accessGroup: String?) -> String {
      "\(service)|\(accessGroup ?? "")|\(key)"
    }

    private static func error(function: String, status: OSStatus) -> NSError {
      var reason = "\(function) (\(status))"
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        reason += ": \(message)"
      }
      return NSError(domain: "com.firebase.appCheck.keychain", code: Int(status),
                     userInfo: [NSLocalizedFailureReasonErrorKey: reason])
    }
  }

#endif // canImport(Security)
