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

// firebase-swift: AppCheckCore is part of FirebaseAppCheck.
@testable import FirebaseAppCheck
import XCTest

class AppCheckCoreStoredTokenTests: XCTestCase {
  // Port note: the Objective-C class name is registered with the archivers, not with `@objc`.
  override func setUp() {
    super.setUp()
    AppCheckCoreStoredToken.registerArchivedClassName()
  }

  // IMMUTABLE TEST: Do not edit, update, or remove under any circumstance.
  // This test locks in an immutable backwards compatibility contract with App Check 11.
  // If this test fails, revert changes to the implementation instead of modifying this test.
  func testKeychainService_MatchesContract() {
    XCTAssertEqual(
      AppCheckCoreStorage.keychainService,
      "com.google.app_check_core.token_storage",
      "Keychain service name mismatch breaks App Check 11 migration compatibility."
    )
  }

  func testLegacyStoredTokenCompatibility() throws {
    let fixtureData = try AppCheckCoreFixtureLoader.loadFixture(named: "GACAppCheckStoredToken.bin")

    let unarchived = try XCTUnwrap(
      NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: fixtureData
      ),
      "Failed to unarchive legacy GACAppCheckStoredToken binary fixture."
    )

    XCTAssertEqual(
      unarchived.token,
      "test_legacy_app_check_token_value",
      "Token mismatch when unarchiving legacy GACAppCheckStoredToken."
    )
    XCTAssertEqual(
      unarchived.expirationDate,
      Date(timeIntervalSince1970: 1_800_000_000),
      "Expiration date mismatch when unarchiving legacy GACAppCheckStoredToken."
    )
    XCTAssertEqual(
      unarchived.receivedAtDate,
      Date(timeIntervalSince1970: 1_700_000_000),
      "Received at date mismatch when unarchiving legacy GACAppCheckStoredToken."
    )
    XCTAssertEqual(
      unarchived.storageVersion,
      2,
      "Storage version mismatch when unarchiving legacy GACAppCheckStoredToken."
    )

    let appCheckToken = try XCTUnwrap(unarchived.appCheckToken())
    XCTAssertEqual(appCheckToken.token, "test_legacy_app_check_token_value")
    XCTAssertEqual(appCheckToken.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
    XCTAssertEqual(appCheckToken.receivedAtDate, Date(timeIntervalSince1970: 1_700_000_000))
  }

  func testSecureCoding() throws {
    let tokenToArchive = AppCheckCoreStoredToken()
    tokenToArchive.token = "some_token"
    tokenToArchive.expirationDate = Date()
    tokenToArchive.receivedAtDate = tokenToArchive.expirationDate?.addingTimeInterval(-10)

    let archivedToken = try NSKeyedArchiver.archivedData(withRootObject: tokenToArchive,
                                                         requiringSecureCoding: true)
    XCTAssertNotNil(archivedToken)

    let unarchivedToken = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: AppCheckCoreStoredToken.self,
      from: archivedToken
    )
    XCTAssertNotNil(unarchivedToken)
    XCTAssertEqual(unarchivedToken?.token, tokenToArchive.token)
    XCTAssertEqual(unarchivedToken?.expirationDate, tokenToArchive.expirationDate)
    XCTAssertEqual(unarchivedToken?.receivedAtDate, tokenToArchive.receivedAtDate)
    XCTAssertEqual(unarchivedToken?.storageVersion, tokenToArchive.storageVersion)
  }

  func testConvertingToAndFromAppCheckCoreToken() {
    let date = Date()
    let originalToken = AppCheckCoreToken(token: "___",
                                          expirationDate: date,
                                          receivedAt: date)

    let storedToken = AppCheckCoreStoredToken()
    storedToken.update(with: originalToken)
    XCTAssertEqual(originalToken.token, storedToken.token)
    XCTAssertEqual(originalToken.expirationDate, storedToken.expirationDate)
    XCTAssertEqual(originalToken.receivedAtDate, storedToken.receivedAtDate)

    let recoveredToken = storedToken.appCheckToken()
    XCTAssertNotNil(recoveredToken)
    XCTAssertEqual(recoveredToken?.token, storedToken.token)
    XCTAssertEqual(recoveredToken?.expirationDate, storedToken.expirationDate)
    XCTAssertEqual(recoveredToken?.receivedAtDate, storedToken.receivedAtDate)
  }

  func testAppCheckToken_ReturnsNilWhenPropertiesAreMissing() {
    let storedToken = AppCheckCoreStoredToken()
    XCTAssertNil(storedToken.appCheckToken(), "Should return nil when all fields are nil.")

    storedToken.token = "token"
    storedToken.expirationDate = Date()
    storedToken.receivedAtDate = nil
    XCTAssertNil(storedToken.appCheckToken(), "Should return nil when receivedAtDate is nil.")

    storedToken.receivedAtDate = Date()
    storedToken.expirationDate = nil
    XCTAssertNil(storedToken.appCheckToken(), "Should return nil when expirationDate is nil.")

    storedToken.expirationDate = Date()
    storedToken.token = nil
    XCTAssertNil(storedToken.appCheckToken(), "Should return nil when token is nil.")
  }

  func testSecureCoding_WithNilProperties() throws {
    let tokenToArchive = AppCheckCoreStoredToken()

    let archivedData = try NSKeyedArchiver.archivedData(
      withRootObject: tokenToArchive,
      requiringSecureCoding: true
    )

    let unarchived = try XCTUnwrap(
      NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: archivedData
      )
    )
    XCTAssertNil(unarchived.token)
    XCTAssertNil(unarchived.expirationDate)
    XCTAssertNil(unarchived.receivedAtDate)
    XCTAssertEqual(unarchived.storageVersion, 2)
  }

  func testUnarchiving_CorruptedDataFailsGracefully() {
    let corruptedBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01])
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: corruptedBytes
      )
    )

    let truncatedBytes = Data("bplist00".utf8)
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: truncatedBytes
      )
    )
  }

  func testDowngradeCompatibility_RuntimeClassNameAndEncodedPropertyTypes() throws {
    let tokenToArchive = AppCheckCoreStoredToken()
    tokenToArchive.token = "test_token"
    tokenToArchive.expirationDate = Date()
    tokenToArchive.receivedAtDate = Date()

    // Port note: there's no Objective-C runtime name, so this checks the name in the archive.
    // corelibs ignores `NSKeyedArchiver.setClassName` when encoding, so on Linux and Android the
    // archive has the Swift name (unarchiving `GACAppCheckStoredToken` works everywhere).
    #if canImport(ObjectiveC)
      XCTAssertNotNil(
        try NSKeyedArchiver.archivedData(withRootObject: tokenToArchive,
                                         requiringSecureCoding: true)
          .range(of: Data("GACAppCheckStoredToken".utf8)),
        "Runtime class name must equal GACAppCheckStoredToken for Objective-C 11 unarchiving."
      )
    #endif

    let archivedData = try NSKeyedArchiver.archivedData(
      withRootObject: tokenToArchive,
      requiringSecureCoding: true
    )

    let unarchived = try XCTUnwrap(
      NSKeyedUnarchiver.unarchivedObject(
        ofClass: AppCheckCoreStoredToken.self,
        from: archivedData
      )
    )
    XCTAssertTrue((unarchived.token as Any) is String)
    XCTAssertTrue((unarchived.expirationDate as Any) is Date)
    XCTAssertTrue((unarchived.receivedAtDate as Any) is Date)
    XCTAssertTrue((unarchived.storageVersion as Any) is Int)
  }
}
