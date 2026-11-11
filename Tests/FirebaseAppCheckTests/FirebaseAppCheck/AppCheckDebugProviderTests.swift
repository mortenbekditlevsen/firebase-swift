// Copyright 2020 Google LLC
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

// Port note: a port of upstream's FIRAppCheckDebugProviderTests.m and
// FIRAppCheckDebugProviderFactoryTests.m. Upstream mocks GACAppCheckDebugProvider with OCMock;
// here the provider wraps a real AppCheckCoreDebugProvider on the AppCheckCore tests' fake API
// service.

@testable import FirebaseAppCheck
import FirebaseCore
import XCTest

private let kAppName = "test_app_name"
private let kAppID = "test_app_id"
private let kAPIKey = "test_api_key"
private let kProjectID = "test_project_id"
private let kProjectNumber = "123456789"
private let kDebugToken = "TEST_DebugToken"

final class AppCheckDebugProviderTests: XCTestCase {
  private var resourceName: String!
  private var apiService: MockAppCheckDebugProviderAPIService!
  private var provider: AppCheckDebugProvider!

  override func setUp() {
    super.setUp()
    resourceName = "projects/\(kProjectID)/apps/\(kAppID)"
    apiService = MockAppCheckDebugProviderAPIService()
    let debugProvider = AppCheckCoreDebugProvider(
      apiService: apiService,
      serviceName: kAppName,
      resourceName: resourceName,
      environment: ["FIRAAppCheckDebugToken": kDebugToken]
    )
    provider = AppCheckDebugProvider(debugProvider: debugProvider, projectID: nil,
                                     googleAppID: kAppID)
  }

  override func tearDown() {
    provider = nil
    apiService = nil
    super.tearDown()
  }

  // MARK: - Initialization

  func testInitWithValidApp() throws {
    var options = FirebaseOptions(googleAppID: kAppID, gcmSenderID: kProjectNumber)
    options.apiKey = kAPIKey
    options.projectID = kProjectID
    let app = FirebaseApp(options: options, name: kAppName)

    let provider = try XCTUnwrap(AppCheckDebugProvider(app: app))
    XCTAssertEqual(provider.projectID, kProjectID)
    XCTAssertEqual(provider.googleAppID, kAppID)
  }

  func testInitWithDebugProvider() {
    XCTAssertNil(provider.projectID)
    XCTAssertEqual(provider.googleAppID, kAppID)
  }

  func testInitWithIncompleteApp() {
    var options = FirebaseOptions(googleAppID: kAppID, gcmSenderID: kProjectNumber)
    options.projectID = kProjectID
    let missingAPIKeyApp = FirebaseApp(options: options, name: kAppName)

    XCTAssertNil(AppCheckDebugProvider(app: missingAPIKeyApp))

    options.projectID = nil
    options.apiKey = kAPIKey
    let missingProjectIDApp = FirebaseApp(options: options, name: kAppName)
    XCTAssertNil(AppCheckDebugProvider(app: missingProjectIDApp))
  }

  // MARK: - Current Debug token

  // Port note: upstream checks that the call is forwarded to the mock; here the token is the
  // environment's.
  func testCurrentTokenShim() {
    XCTAssertEqual(provider.currentDebugToken(), kDebugToken)
  }

  // MARK: - Local Debug Token

  func testLocalDebugToken() {
    let localToken = provider.localDebugToken()
    XCTAssertFalse(localToken.isEmpty)
    XCTAssertEqual(provider.localDebugToken(), localToken)
  }

  // MARK: - Debug token to FAC token exchange

  func testGetTokenSuccess() async throws {
    let validInternalToken = AppCheckCoreToken(token: "valid_token", expirationDate: Date(),
                                               receivedAt: Date())
    apiService.tokenResult = .success(validInternalToken)

    let token = try await provider.getToken()

    XCTAssertEqual(token.token, validInternalToken.token)
    XCTAssertEqual(token.expirationDate, validInternalToken.expirationDate)
    XCTAssertEqual(token.receivedAtDate, validInternalToken.receivedAtDate)
    XCTAssertEqual(apiService.passedDebugToken, kDebugToken)
    XCTAssertEqual(apiService.passedLimitedUse, false)
  }

  func testGetTokenAPIError() async {
    let expectedError = NSError(domain: "testGetTokenAPIError", code: -1, userInfo: nil)
    apiService.tokenResult = .failure(expectedError)

    do {
      _ = try await provider.getToken()
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError, expectedError)
    }
  }

  // MARK: - Limited-Use Token

  func testGetLimitedUseTokenSuccess() async throws {
    let validInternalToken = AppCheckCoreToken(token: "TEST_ValidToken", expirationDate: Date(),
                                               receivedAt: Date())
    apiService.limitedUseTokenResult = .success(validInternalToken)

    let token = try await provider.getLimitedUseToken()

    XCTAssertEqual(token.token, validInternalToken.token)
    XCTAssertEqual(token.expirationDate, validInternalToken.expirationDate)
    XCTAssertEqual(token.receivedAtDate, validInternalToken.receivedAtDate)
    XCTAssertEqual(apiService.passedLimitedUse, true)
  }

  func testGetLimitedUseTokenProviderError() async {
    let expectedError = NSError(domain: "TEST_LimitedUseToken_Error", code: -1, userInfo: nil)
    apiService.limitedUseTokenResult = .failure(expectedError)

    do {
      _ = try await provider.getLimitedUseToken()
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError, expectedError)
    }
  }

  // MARK: - Exchange failure messages (upstream 13.2.0, #17017)

  private func provider(source: AppCheckCoreDebugTokenSource,
                        projectID: String?) -> AppCheckDebugProvider {
    let debugProvider = AppCheckCoreDebugProvider(
      apiService: apiService,
      serviceName: kAppName,
      resourceName: resourceName,
      environment: source == .environmentVariable ? ["AppCheckDebugToken": kDebugToken] : [:],
      debugToken: source == .provided ? kDebugToken : nil
    )
    XCTAssertEqual(debugProvider.debugTokenSource, source)
    return AppCheckDebugProvider(debugProvider: debugProvider, projectID: projectID,
                                 googleAppID: kAppID)
  }

  func testConfigStoreExchangeFailureMessageSuggestsForceCreateAndRelaunch() throws {
    let error = NSError(domain: "testDomain", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Permission denied"])

    let message = try XCTUnwrap(provider(source: .provided, projectID: kProjectID)
      .debugTokenExchangeFailureMessage(for: error))

    XCTAssertTrue(message.contains("~/.config/configstore/firebase-appcheck.json"), message)
    XCTAssertTrue(message.contains("Permission denied"), message)
    XCTAssertTrue(message.contains(
      "`firebase appcheck:debugtokens:create --force --project \(kProjectID) --app \(kAppID)`"
    ), message)
    XCTAssertTrue(message.contains("relaunch the app"), message)
  }

  func testConfigStoreExchangeFailureMessageOmitsMissingProjectID() throws {
    let error = NSError(domain: "testDomain", code: -1)

    let message = try XCTUnwrap(provider(source: .provided, projectID: nil)
      .debugTokenExchangeFailureMessage(for: error))

    XCTAssertFalse(message.contains("--project"), message)
    XCTAssertTrue(message.contains("`firebase appcheck:debugtokens:create --force --app \(kAppID)`"),
                  message)
  }

  func testConfigStoreExchangeFailureMessagePrefersFailureReason() throws {
    let error = NSError(domain: "testDomain", code: -1,
                        userInfo: [NSLocalizedFailureReasonErrorKey: "The server responded with an error"])

    let message = try XCTUnwrap(provider(source: .provided, projectID: kProjectID)
      .debugTokenExchangeFailureMessage(for: error))

    XCTAssertTrue(message.contains(": The server responded with an error"), message)
    XCTAssertFalse(message.contains("couldn’t be completed"), message)
  }

  func testEnvironmentVariableExchangeFailureMessageNamesVariablesWithoutForce() throws {
    let error = NSError(domain: "testDomain", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Permission denied"])

    let message = try XCTUnwrap(provider(source: .environmentVariable, projectID: kProjectID)
      .debugTokenExchangeFailureMessage(for: error))

    XCTAssertTrue(message.contains("`AppCheckDebugToken`"), message)
    XCTAssertTrue(message.contains("`FIRAAppCheckDebugToken`"), message)
    XCTAssertTrue(message.contains("Permission denied"), message)
    XCTAssertTrue(message.contains(
      "`firebase appcheck:debugtokens:create <token> --project \(kProjectID) --app \(kAppID)`"
    ), message)
    // Provisioning a new config store token wouldn't help while the environment variable wins.
    XCTAssertFalse(message.contains("--force"), message)
    XCTAssertFalse(message.contains("firebase-appcheck.json"), message)
  }

  func testExchangeFailureMessageIsNilWhenServerUnreachable() {
    let error = NSError(domain: AppCheckCoreErrorDomain,
                        code: AppCheckCoreErrorCode.serverUnreachable.rawValue)

    XCTAssertNil(provider(source: .provided, projectID: kProjectID)
      .debugTokenExchangeFailureMessage(for: error))
    XCTAssertNil(provider(source: .environmentVariable, projectID: kProjectID)
      .debugTokenExchangeFailureMessage(for: error))
  }

  func testProvidedDebugTokenIsUsed() {
    XCTAssertEqual(provider(source: .provided, projectID: kProjectID).currentDebugToken(),
                   kDebugToken)
  }
}

final class AppCheckDebugProviderFactoryTests: XCTestCase {
  func testCreateProviderWithApp() throws {
    var options = FirebaseOptions(googleAppID: "app_id", gcmSenderID: "sender_id")
    options.apiKey = "api_key"
    options.projectID = "project_id"
    let app = FirebaseApp(options: options, name: "testInitWithValidApp")

    let factory = AppCheckDebugProviderFactory()

    let createdProvider = try XCTUnwrap(factory.createProvider(with: app))

    let debugProvider = try XCTUnwrap(createdProvider as? AppCheckDebugProvider)
    XCTAssertFalse(debugProvider.currentDebugToken().isEmpty)
  }
}
