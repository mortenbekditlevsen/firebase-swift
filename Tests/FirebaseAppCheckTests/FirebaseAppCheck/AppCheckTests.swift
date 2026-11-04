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

// Port note: a port of upstream's FIRAppCheckTests.m. Upstream mocks GACAppCheck with OCMock;
// here `AppCheck` runs on a real `AppCheckCore` built from the AppCheckCore fakes, and the
// notification checks count the posts once the awaited call returns, instead of using inverted
// expectations. Upstream's logger-level checks are left out: FirebaseCore's logger isn't ported.

@testable import FirebaseAppCheck
import FirebaseCore
import XCTest

/// The App Check token value returned when an error occurs.
private let kDummyToken = "eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ=="

final class AppCheckTests: XCTestCase {
  private var appName: String!
  private var storage: AppCheckCoreStorageFake!
  private var provider: AppCheckCoreProviderFake!
  private var userDefaults: UserDefaults!
  private var userDefaultsSuiteName: String!
  private var settings: AppCheckSettings!
  private var appCheck: AppCheck!
  private var tokenNotifications: [Notification] = []
  private var observer: NSObjectProtocol?

  override func setUp() {
    super.setUp()

    appName = "FIRAppCheckTests"
    storage = AppCheckCoreStorageFake()
    provider = AppCheckCoreProviderFake()
    userDefaultsSuiteName = "AppCheckTests.\(UUID().uuidString)"
    userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
    settings = AppCheckSettings(appName: appName, userDefaults: userDefaults)

    let tokenDelegate = TokenDelegate(appName: appName)
    let appCheckCore = AppCheckCore(serviceName: appName,
                                    appCheckProvider: provider,
                                    storage: storage,
                                    tokenRefresher: AppCheckCoreTokenRefresherFake(),
                                    settings: settings,
                                    tokenDelegate: tokenDelegate)
    appCheck = AppCheck(appName: appName, appCheckCore: appCheckCore, settings: settings,
                        tokenDelegate: tokenDelegate)

    tokenNotifications = []
    observer = NotificationCenter.default.addObserver(forName: .AppCheckTokenDidChange,
                                                      object: appCheck,
                                                      queue: nil) { [weak self] notification in
      self?.tokenNotifications.append(notification)
    }
  }

  override func tearDown() {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
    observer = nil
    appCheck = nil
    settings = nil
    userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    userDefaults = nil
    provider = nil
    storage = nil

    super.tearDown()
  }

  func testInitWithApp() throws {
    let options = appOptions(googleAppID: "testInitWithApp_googleAppID",
                             projectID: "testInitWithApp_projectID")
    let app = FirebaseApp(options: options, name: "testInitWithApp_appName")

    let factory = AppCheckProviderFactoryFake()
    AppCheck.setAppCheckProviderFactory(factory, keychain: AppCheckCoreKeychainStorageFake())

    XCTAssertNotNil(AppCheck(app: app))
    XCTAssertEqual(factory.createdProviderApps.map(\.name), [app.name])
  }

  func testAppCheckInstanceForApp() {
    AppCheck.setAppCheckProviderFactory(AppCheckProviderFactoryFake(),
                                        keychain: AppCheckCoreKeychainStorageFake())
    let app = FirebaseApp(options: appOptions(), name: "testAppCheckInstanceForApp")

    let appCheck = AppCheck.appCheck(app: app)

    XCTAssertNotNil(appCheck)
    // Port note: the instance is created once per app, as upstream's component is.
    XCTAssertTrue(appCheck === AppCheck.appCheck(app: app))
  }

  // Port note: upstream has no default factory to unset; these cover `init?(app:)`'s failures.
  func testAppCheckInstanceForAppWithoutProviderFactory() {
    AppCheck.setAppCheckProviderFactory(nil, keychain: AppCheckCoreKeychainStorageFake())
    let app = FirebaseApp(options: appOptions(), name: "testAppCheckInstanceForAppNoFactory")

    XCTAssertNil(AppCheck.appCheck(app: app))
  }

  func testAppCheckInstanceForAppWhenFactoryReturnsNoProvider() {
    let factory = AppCheckProviderFactoryFake()
    factory.returnsProvider = false
    AppCheck.setAppCheckProviderFactory(factory, keychain: AppCheckCoreKeychainStorageFake())
    let app = FirebaseApp(options: appOptions(), name: "testAppCheckInstanceForAppNoProvider")

    XCTAssertNil(AppCheck.appCheck(app: app))
  }

  // MARK: - Public Get Token

  func testGetToken_Success() async throws {
    let expectedToken = validToken()
    provider.tokenToReturn = expectedToken.internalToken

    let token = try await appCheck.token(forcingRefresh: false)

    XCTAssertEqual(token.token, expectedToken.token)
    assertTokenUpdateNotification(expectedToken: expectedToken.token)
  }

  func testGetToken_AppCheckProviderError() async {
    storage.getTokenHandler = { self.soonExpiringToken().internalToken }
    let providerError = NSError(domain: "FIRAppCheckTests", code: -1, userInfo: nil)
    provider.errorToReturn = providerError

    do {
      _ = try await appCheck.token(forcingRefresh: false)
      XCTFail("Expected an error")
    } catch {
      let error = error as NSError
      XCTAssertNotEqual(error, providerError)
      XCTAssertEqual(error.domain, AppCheckErrorDomain)
      XCTAssertEqual(error.userInfo[NSUnderlyingErrorKey] as? NSError, providerError)
    }
    XCTAssertEqual(tokenNotifications.count, 0)
  }

  func testGetToken_ServerUnreachableError() async {
    let serverError = appCheckCoreError(code: .serverUnreachable,
                                        failureReason: "API request error.",
                                        underlyingError: internalError())
    provider.errorToReturn = serverError

    do {
      _ = try await appCheck.token(forcingRefresh: false)
      XCTFail("Expected an error")
    } catch {
      let error = error as NSError
      XCTAssertEqual(error, AppCheckErrorUtil.publicDomainError(with: serverError))
      XCTAssertEqual(error.domain, AppCheckErrorDomain)
      XCTAssertEqual(error.code, AppCheckErrorCode.serverUnreachable.rawValue)
      XCTAssertEqual(error.userInfo as NSDictionary, serverError.userInfo as NSDictionary)
    }
    XCTAssertEqual(tokenNotifications.count, 0)
  }

  func testGetToken_UnsupportedError() async {
    let providerError = appCheckCoreError(code: .unsupported,
                                          failureReason: "AppAttestProvider unsupported",
                                          underlyingError: nil)
    provider.errorToReturn = providerError

    do {
      _ = try await appCheck.token(forcingRefresh: false)
      XCTFail("Expected an error")
    } catch {
      let error = error as NSError
      XCTAssertEqual(error, AppCheckErrorUtil.publicDomainError(with: providerError))
      XCTAssertEqual(error.domain, AppCheckErrorDomain)
      XCTAssertEqual(error.code, AppCheckErrorCode.unsupported.rawValue)
      XCTAssertEqual(error.userInfo as NSDictionary, providerError.userInfo as NSDictionary)
    }
    XCTAssertEqual(tokenNotifications.count, 0)
  }

  // MARK: - AppCheckInterop Get Token

  func testInteropGetTokenForcingRefresh_Success() async {
    let expectedToken = validToken()
    provider.tokenToReturn = expectedToken.internalToken

    let result = await appCheck.getToken(forcingRefresh: false)

    XCTAssertEqual(result.token, expectedToken.token)
    XCTAssertNil(result.error)
    assertTokenUpdateNotification(expectedToken: expectedToken.token)
  }

  func testInteropGetTokenForcingRefresh_AppCheckProviderError() async {
    storage.getTokenHandler = { self.soonExpiringToken().internalToken }
    let providerError = NSError(domain: "FIRAppCheckTests", code: -1, userInfo: nil)
    provider.errorToReturn = providerError

    let result = await appCheck.getToken(forcingRefresh: false)

    XCTAssertEqual(result.token, kDummyToken)
    XCTAssertEqual(result.error as NSError?, providerError)
    // Interop API does not wrap errors in public domain.
    XCTAssertNotEqual((result.error as NSError?)?.domain, AppCheckErrorDomain)
    XCTAssertEqual(tokenNotifications.count, 0)
  }

  func testLimitedUseTokenWithSuccess() async throws {
    let expectedToken = validToken()
    provider.limitedUseTokenToReturn = expectedToken.internalToken

    let token = try await appCheck.limitedUseToken()

    XCTAssertEqual(token.token, expectedToken.token)
    // Limited-use tokens aren't cached, so no token update notification.
    XCTAssertEqual(tokenNotifications.count, 0)
    XCTAssertNil(storage.lastSetToken)
  }

  func testLimitedUseToken_WhenTokenGenerationErrors() async {
    let providerError = appCheckCoreError(code: .keychain,
                                          failureReason: "Keychain access error.",
                                          underlyingError: internalError())
    provider.limitedUseErrorToReturn = providerError

    do {
      _ = try await appCheck.limitedUseToken()
      XCTFail("Expected an error")
    } catch {
      let error = error as NSError
      XCTAssertEqual(error, AppCheckErrorUtil.publicDomainError(with: providerError))
      XCTAssertEqual(error.domain, AppCheckErrorDomain)
      XCTAssertEqual(error.code, AppCheckErrorCode.keychain.rawValue)
      XCTAssertEqual(error.userInfo as NSDictionary, providerError.userInfo as NSDictionary)
    }
    XCTAssertEqual(provider.getTokenCallCount, 0)
    XCTAssertEqual(tokenNotifications.count, 0)
  }

  // Port note: the interop limited-use token has no upstream test.
  func testInteropGetLimitedUseToken_Error() async {
    let providerError = NSError(domain: "FIRAppCheckTests", code: -1, userInfo: nil)
    provider.limitedUseErrorToReturn = providerError

    let result = await appCheck.getLimitedUseToken()

    XCTAssertEqual(result.token, kDummyToken)
    XCTAssertEqual(result.error as NSError?, providerError)
  }

  // MARK: - Token update notifications

  func testTokenUpdateNotificationKeys() {
    XCTAssertEqual(appCheck.tokenDidChangeNotificationName,
                   "FIRAppCheckAppCheckTokenDidChangeNotification")
    XCTAssertEqual(appCheck.notificationAppNameKey, "FIRAppCheckAppNameNotificationKey")
    XCTAssertEqual(appCheck.notificationTokenKey, "FIRAppCheckTokenNotificationKey")
  }

  // MARK: - Auto-refresh enabled

  // Port note: upstream mocks the settings; here they're read back from the settings'
  // UserDefaults.
  func testIsTokenAutoRefreshEnabled() {
    settings.isTokenAutoRefreshEnabled = false
    XCTAssertFalse(appCheck.isTokenAutoRefreshEnabled)

    settings.isTokenAutoRefreshEnabled = true
    XCTAssertTrue(appCheck.isTokenAutoRefreshEnabled)
  }

  func testSetIsTokenAutoRefreshEnabled() {
    let key = AppCheckSettings.userDefaultsKeyPrefix + appName

    appCheck.isTokenAutoRefreshEnabled = true
    XCTAssertEqual(userDefaults.object(forKey: key) as? Bool, true)

    appCheck.isTokenAutoRefreshEnabled = false
    XCTAssertEqual(userDefaults.object(forKey: key) as? Bool, false)
  }

  // MARK: - Helpers

  private func appOptions(googleAppID: String = "1:100000000000:ios:aaaaaaaaaaaaaaaaaaaaaaaa",
                          projectID: String = "project_id") -> FirebaseOptions {
    var options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: "sender_id")
    options.apiKey = "api_key"
    options.projectID = projectID
    return options
  }

  private func internalError() -> NSError {
    NSError(domain: "com.internal.error", code: -1, userInfo: nil)
  }

  private func appCheckCoreError(code: AppCheckCoreErrorCode,
                                 failureReason: String?,
                                 underlyingError: NSError?) -> NSError {
    var userInfo: [String: Any] = [:]
    userInfo[NSUnderlyingErrorKey] = underlyingError
    userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
    return NSError(domain: "com.google.app_check_core", code: code.rawValue, userInfo: userInfo)
  }

  private func validToken() -> AppCheckToken {
    AppCheckToken(token: UUID().uuidString, expirationDate: .distantFuture)
  }

  private func soonExpiringToken() -> AppCheckToken {
    AppCheckToken(token: "valid", expirationDate: Date(timeIntervalSinceNow: 4.5 * 60))
  }

  private func assertTokenUpdateNotification(expectedToken: String,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
    XCTAssertEqual(tokenNotifications.count, 1, file: file, line: line)
    guard let notification = tokenNotifications.first else { return }
    XCTAssertEqual(notification.userInfo?[appCheck.notificationAppNameKey] as? String, appName,
                   file: file, line: line)
    XCTAssertEqual(notification.userInfo?[appCheck.notificationTokenKey] as? String,
                   expectedToken, file: file, line: line)
    XCTAssertTrue(notification.object as AnyObject === appCheck, file: file, line: line)
  }
}

// MARK: - Fakes

private final class AppCheckProviderFake: AppCheckProvider, @unchecked Sendable {
  func getToken() async throws -> AppCheckToken {
    AppCheckToken(token: "token", expirationDate: .distantFuture)
  }
}

private final class AppCheckProviderFactoryFake: AppCheckProviderFactory, @unchecked Sendable {
  var returnsProvider = true
  private(set) var createdProviderApps: [FirebaseApp] = []

  func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
    createdProviderApps.append(app)
    return returnsProvider ? AppCheckProviderFake() : nil
  }
}
