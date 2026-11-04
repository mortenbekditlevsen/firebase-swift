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

  @testable import FirebaseAppCheck
  import FirebaseCore
  import Security
  import XCTest

  /// The port's default keychain. Test runners aren't signed with a keychain entitlement, so
  /// they can't use the data protection keychain, and these run against the in-memory fallback.
  /// `AppCheckFileKeychainTests` runs them against the keychain.
  class AppCheckSystemKeychainTests: XCTestCase {
    fileprivate var keychain: AppCheckSystemKeychain!
    fileprivate var service: String!

    /// Whether the keychain under test is the data protection keychain.
    fileprivate var usesDataProtectionKeychain: Bool { true }

    fileprivate func makeKeychain() -> AppCheckSystemKeychain {
      AppCheckSystemKeychain()
    }

    override func setUp() async throws {
      try await super.setUp()
      keychain = makeKeychain()
      service = "AppCheckSystemKeychainTests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
      AppCheck.resetConfiguration()
      for key in ["key", "other"] {
        try await keychain.removeData(forKey: key, service: service, accessGroup: nil)
      }
      keychain = nil
      try await super.tearDown()
    }

    func testMissingItemIsNil() async throws {
      let data = try await keychain.data(forKey: "key", service: service, accessGroup: nil)
      XCTAssertNil(data)
    }

    func testSetGetReplaceAndRemove() async throws {
      try await keychain.setData(Data("first".utf8), forKey: "key", service: service,
                                 accessGroup: nil)
      var data = try await keychain.data(forKey: "key", service: service, accessGroup: nil)
      XCTAssertEqual(data, Data("first".utf8))

      try await keychain.setData(Data("second".utf8), forKey: "key", service: service,
                                 accessGroup: nil)
      data = try await keychain.data(forKey: "key", service: service, accessGroup: nil)
      XCTAssertEqual(data, Data("second".utf8))

      try await keychain.removeData(forKey: "key", service: service, accessGroup: nil)
      data = try await keychain.data(forKey: "key", service: service, accessGroup: nil)
      XCTAssertNil(data)
    }

    func testRemovingAMissingItemIsNotAnError() async throws {
      try await keychain.removeData(forKey: "key", service: service, accessGroup: nil)
    }

    func testItemsAreSeparateByKeyAndService() async throws {
      try await keychain.setData(Data("a".utf8), forKey: "key", service: service,
                                 accessGroup: nil)
      try await keychain.setData(Data("b".utf8), forKey: "other", service: service,
                                 accessGroup: nil)

      let other = try await keychain.data(forKey: "other", service: service, accessGroup: nil)
      XCTAssertEqual(other, Data("b".utf8))
      let otherService = try await keychain.data(forKey: "key", service: service + ".other",
                                                 accessGroup: nil)
      XCTAssertNil(otherService)
    }

    /// Items stored as `GULKeychainStorage` stores them are read, and the other way around.
    func testItemsAreUpstreamItems() async throws {
      try XCTSkipUnless(!usesDataProtectionKeychain
        || AppCheckSystemKeychain.isDataProtectionKeychainAvailable,
        "This process can't use the data protection keychain.")
      var upstreamQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service!,
        kSecAttrAccount as String: "key",
      ]
      if usesDataProtectionKeychain {
        upstreamQuery[kSecUseDataProtectionKeychain as String] = true
      }
      var item = upstreamQuery
      item[kSecValueData as String] = Data("upstream".utf8)
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)

      let data = try await keychain.data(forKey: "key", service: service, accessGroup: nil)
      XCTAssertEqual(data, Data("upstream".utf8))

      try await keychain.setData(Data("port".utf8), forKey: "key", service: service,
                                 accessGroup: nil)
      var query = upstreamQuery
      query[kSecReturnAttributes as String] = true
      query[kSecReturnData as String] = true
      var result: CFTypeRef?
      XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
      let attributes = try XCTUnwrap(result as? [String: Any])
      XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("port".utf8))
      // Only the data protection keychain has accessibility classes.
      if usesDataProtectionKeychain {
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
      }
    }

    /// Upstream's `setAppCheckProviderFactory(_:)` stores tokens in the keychain.
    func testSetAppCheckProviderFactoryWithoutKeychainUsesTheKeychain() {
      AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())

      XCTAssertTrue(AppCheck.keychain is AppCheckSystemKeychain)
    }
  }

  #if os(macOS)
    /// The tests against macOS's file-based keychain, which unsigned processes can use: the same
    /// `SecItem` calls as the data protection keychain, without `kSecUseDataProtectionKeychain`.
    /// Skipped where there's no usable default keychain, as on CI runners.
    final class AppCheckFileKeychainTests: AppCheckSystemKeychainTests {
      override fileprivate var usesDataProtectionKeychain: Bool { false }

      override fileprivate func makeKeychain() -> AppCheckSystemKeychain {
        AppCheckSystemKeychain(usesDataProtectionKeychain: false)
      }

      override func setUp() async throws {
        try await super.setUp()
        do {
          try await keychain.setData(Data([0]), forKey: "key", service: service, accessGroup: nil)
          try await keychain.removeData(forKey: "key", service: service, accessGroup: nil)
        } catch {
          throw XCTSkip("The default keychain isn't usable: \(error)")
        }
      }
    }
  #endif // os(macOS)

#endif // canImport(Security)
