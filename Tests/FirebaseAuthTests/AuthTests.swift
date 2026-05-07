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
import Synchronization
import XCTest

@testable import FirebaseAuth
@testable import FirebaseCoreSwift

/// Async-only Auth tests.
///
/// Tests run on the cooperative thread pool. If a particular test wants
/// continuations on the main actor for parity with the original ObjC SDK
/// callback contract, mark that test method `@MainActor`.
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
final class AuthTests: RPCBaseTests {
  static let kAccessToken = "TEST_ACCESS_TOKEN"
  static let kNewAccessToken = "NEW_ACCESS_TOKEN"
  static let kFakeAPIKey = "FAKE_API_KEY"
  static let kFakeGoogleAppID = "0:0000000000000:ios:0000000000000000"

  /// Far-future expiration so that `SecureTokenService.hasValidAccessToken`
  /// returns true and no SecureToken refresh round-trip is needed during
  /// sign-in flows.
  static let kFakeExpiresIn: TimeInterval = 60 * 60 * 24 * 365 * 10

  var auth: Auth!
  static let testNum: Mutex<Int> = .init(0)
  var testApp: FirebaseApp!

  override func setUp() {
    super.setUp()
    let n = AuthTests.testNum.withLock { current -> Int in
      current += 1
      return current
    }
    let options = FirebaseApp.Options(
      projectID: "myProjectID",
      googleAppID: AuthTests.kFakeGoogleAppID,
      apiKey: AuthTests.kFakeAPIKey,
      clientID: nil
    )
    testApp = FirebaseApp(options: options, name: "test-AuthTests-\(n)")
    auth = Auth(app: testApp, keychainStorageProvider: FakeAuthKeychainServices.self)
  }

  override func tearDown() {
    auth = nil
    testApp = nil
    super.tearDown()
  }

  // MARK: - fetchSignInMethods

  func testFetchSignInMethodsForEmailSuccess() async throws {
    let expected = ["emailLink", "facebook.com"]
    let task = Task.detached { [auth = self.auth!, kEmail] in
      try await auth.fetchSignInMethods(forEmail: kEmail)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? CreateAuthURIRequest)
    XCTAssertEqual(request.identifier, kEmail)
    XCTAssertEqual(request.endpoint, "createAuthUri")
    XCTAssertEqual(request.requestConfiguration.apiKey, AuthTests.kFakeAPIKey)

    try rpcIssuer?.respond(withJSON: ["signinMethods": expected])
    let methods = try await task.value
    XCTAssertEqual(methods, expected)
  }

  func testFetchSignInMethodsForEmailFailure() async throws {
    let task = Task.detached { [auth = self.auth!, kEmail] in
      try await auth.fetchSignInMethods(forEmail: kEmail)
    }
    await rpcIssuer?.waitForRequest()
    try rpcIssuer?.respond(serverErrorMessage: "TOO_MANY_ATTEMPTS_TRY_LATER")
    do {
      _ = try await task.value
      XCTFail("Expected tooManyRequests error")
    } catch {
      XCTAssertEqual((error as NSError).code, AuthErrorCode.tooManyRequests.rawValue)
    }
  }

  // MARK: - signIn(withEmail:password:)

  func testSignInWithEmailPasswordSuccess() async throws {
    setFakeGetAccountProvider()
    let task = Task.detached { [auth = self.auth!, kEmail, kFakePassword] in
      try await auth.signIn(withEmail: kEmail, password: kFakePassword)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? VerifyPasswordRequest)
    XCTAssertEqual(request.email, kEmail)
    XCTAssertEqual(request.password, kFakePassword)

    try rpcIssuer?.respond(withJSON: [
      "idToken": AuthTests.kAccessToken,
      "expiresIn": "\(AuthTests.kFakeExpiresIn)",
      "refreshToken": kRefreshToken,
    ])
    let result = try await task.value
    XCTAssertEqual(result.user.uid, kLocalID)
    XCTAssertEqual(result.user.email, kEmail)
    XCTAssertFalse(result.user.isAnonymous)
    XCTAssertEqual(auth.currentUser?.uid, kLocalID)
  }

  func testSignInWithEmailPasswordWrongPassword() async throws {
    let task = Task.detached { [auth = self.auth!, kEmail, kFakePassword] in
      try await auth.signIn(withEmail: kEmail, password: kFakePassword)
    }
    await rpcIssuer?.waitForRequest()
    try rpcIssuer?.respond(serverErrorMessage: "INVALID_PASSWORD")
    do {
      _ = try await task.value
      XCTFail("Expected wrongPassword")
    } catch {
      XCTAssertEqual((error as NSError).code, AuthErrorCode.wrongPassword.rawValue)
    }
    XCTAssertNil(auth.currentUser)
  }

  func testSignInWithEmptyPasswordFails() async throws {
    do {
      _ = try await auth.signIn(withEmail: kEmail, password: "")
      XCTFail("Expected wrongPassword")
    } catch {
      XCTAssertEqual((error as NSError).code, AuthErrorCode.wrongPassword.rawValue)
    }
    XCTAssertNil(auth.currentUser)
  }

  // MARK: - signInAnonymously

  func testSignInAnonymouslySuccess() async throws {
    setFakeGetAccountProviderAnonymous()
    let task = Task.detached { [auth = self.auth!] in
      try await auth.signInAnonymously()
    }
    await rpcIssuer?.waitForRequest()
    XCTAssertNotNil(rpcIssuer?.request as? SignUpNewUserRequest)
    try rpcIssuer?.respond(withJSON: [
      "idToken": AuthTests.kAccessToken,
      "expiresIn": "\(AuthTests.kFakeExpiresIn)",
      "refreshToken": kRefreshToken,
      "isNewUser": true,
    ])
    let result = try await task.value
    XCTAssertEqual(result.user.uid, kLocalID)
    XCTAssertTrue(result.user.isAnonymous)
    XCTAssertEqual(result.additionalUserInfo?.isNewUser, true)
    XCTAssertEqual(auth.currentUser?.uid, kLocalID)
  }

  // MARK: - signIn(withCustomToken:)

  func testSignInWithCustomTokenSuccess() async throws {
    setFakeGetAccountProvider()
    let task = Task.detached { [auth = self.auth!, kCustomToken] in
      try await auth.signIn(withCustomToken: kCustomToken)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? VerifyCustomTokenRequest)
    XCTAssertEqual(request.token, kCustomToken)

    try rpcIssuer?.respond(withJSON: [
      "idToken": AuthTests.kAccessToken,
      "expiresIn": "\(AuthTests.kFakeExpiresIn)",
      "refreshToken": kRefreshToken,
      "isNewUser": false,
    ])
    let result = try await task.value
    XCTAssertEqual(result.user.uid, kLocalID)
    XCTAssertFalse(result.user.isAnonymous)
  }

  // MARK: - createUser

  func testCreateUserWithEmailPasswordSuccess() async throws {
    setFakeGetAccountProvider()
    let task = Task.detached { [auth = self.auth!, kEmail, kFakePassword] in
      try await auth.createUser(withEmail: kEmail, password: kFakePassword)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? SignUpNewUserRequest)
    XCTAssertEqual(request.email, Optional(kEmail))
    XCTAssertEqual(request.password, Optional(kFakePassword))

    try rpcIssuer?.respond(withJSON: [
      "idToken": AuthTests.kAccessToken,
      "expiresIn": "\(AuthTests.kFakeExpiresIn)",
      "refreshToken": kRefreshToken,
    ])
    let result = try await task.value
    XCTAssertEqual(result.user.uid, kLocalID)
    XCTAssertEqual(result.additionalUserInfo?.providerID, EmailAuthProvider.id)
    XCTAssertEqual(result.additionalUserInfo?.isNewUser, true)
  }

  func testCreateUserEmptyPasswordFails() async throws {
    do {
      _ = try await auth.createUser(withEmail: kEmail, password: "")
      XCTFail("Expected weakPassword")
    } catch {
      XCTAssertEqual((error as NSError).code, AuthErrorCode.weakPassword.rawValue)
    }
  }

  func testCreateUserEmptyEmailFails() async throws {
    do {
      _ = try await auth.createUser(withEmail: "", password: kFakePassword)
      XCTFail("Expected missingEmail")
    } catch {
      XCTAssertEqual((error as NSError).code, AuthErrorCode.missingEmail.rawValue)
    }
  }

  // MARK: - signOut

  func testSignOutSucceedsWhenSignedIn() async throws {
    try await signInWithEmailHelper()
    XCTAssertNotNil(auth.currentUser)
    try auth.signOut()
    XCTAssertNil(auth.currentUser)
  }

  func testSignOutWhenNotSignedInIsNoOp() throws {
    XCTAssertNil(auth.currentUser)
    try auth.signOut()
    XCTAssertNil(auth.currentUser)
  }

  // MARK: - sendPasswordReset / sendSignInLink

  func testSendPasswordResetSuccess() async throws {
    let task = Task.detached { [auth = self.auth!, kEmail] in
      try await auth.sendPasswordReset(withEmail: kEmail)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? GetOOBConfirmationCodeRequest)
    XCTAssertEqual(request.email, Optional(kEmail))
    try rpcIssuer?.respond(withJSON: [:])
    try await task.value
  }

  func testSendSignInLinkSuccess() async throws {
    let settings = fakeActionCodeSettings()
    let task = Task.detached { [auth = self.auth!, kEmail, settings] in
      try await auth.sendSignInLink(toEmail: kEmail, actionCodeSettings: settings)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? GetOOBConfirmationCodeRequest)
    XCTAssertEqual(request.email, Optional(kEmail))
    try rpcIssuer?.respond(withJSON: [:])
    try await task.value
  }

  // MARK: - applyActionCode / checkActionCode / verifyPasswordResetCode

  func testApplyActionCodeSuccess() async throws {
    let task = Task.detached { [auth = self.auth!, kFakeOobCode] in
      try await auth.applyActionCode(kFakeOobCode)
    }
    await rpcIssuer?.waitForRequest()
    XCTAssertNotNil(rpcIssuer?.request as? SetAccountInfoRequest)
    try rpcIssuer?.respond(withJSON: [:])
    try await task.value
  }

  func testCheckActionCodeSuccess() async throws {
    let task = Task.detached { [auth = self.auth!, kFakeOobCode] in
      try await auth.checkActionCode(kFakeOobCode)
    }
    await rpcIssuer?.waitForRequest()
    let request = try XCTUnwrap(rpcIssuer?.request as? ResetPasswordRequest)
    XCTAssertEqual(request.oobCode, kFakeOobCode)
    try rpcIssuer?.respond(withJSON: [
      "email": kEmail,
      "requestType": "PASSWORD_RESET",
    ])
    let info = try await task.value
    XCTAssertEqual(info.email, kEmail)
  }

  func testVerifyPasswordResetCodeSuccess() async throws {
    let task = Task.detached { [auth = self.auth!, kFakeOobCode] in
      try await auth.verifyPasswordResetCode(kFakeOobCode)
    }
    await rpcIssuer?.waitForRequest()
    try rpcIssuer?.respond(withJSON: [
      "email": kEmail,
      "requestType": "PASSWORD_RESET",
    ])
    let email = try await task.value
    XCTAssertEqual(email, kEmail)
  }

  // MARK: - useEmulator

  func testUseEmulator() {
    auth.useEmulator(withHost: "127.0.0.1", port: 9099)
    XCTAssertEqual(auth.requestConfiguration.emulatorHostAndPort, "127.0.0.1:9099")
  }

  func testUseEmulatorIPv6() {
    auth.useEmulator(withHost: "::1", port: 9099)
    XCTAssertEqual(auth.requestConfiguration.emulatorHostAndPort, "[::1]:9099")
  }

  // MARK: - useAppLanguage

  func testUseAppLanguageSetsLanguageCode() {
    auth.useAppLanguage()
    XCTAssertNotNil(auth.requestConfiguration.languageCode)
  }

  // MARK: - listeners

  func testAuthStateDidChangeListenerFiresOnRegister() async throws {
    let exp = expectation(description: "listener fired with initial value")
    let handle = auth.addStateDidChangeListener { [weak auth] receivedAuth, _ in
      XCTAssertTrue(receivedAuth === auth)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
    auth.removeStateDidChangeListener(handle)
  }

  // MARK: - updateCurrentUser

  func testUpdateCurrentUserSameProjectSucceeds() async throws {
    try await signInWithEmailHelper()
    let user = try XCTUnwrap(auth.currentUser)
    try await auth.updateCurrentUser(user)
    XCTAssertEqual(auth.currentUser?.uid, user.uid)
  }

  // MARK: - Helpers

  /// Drives a successful email/password sign-in. Tests calling this should
  /// not have other RPCs in flight; the helper drives exactly one fake-backend
  /// round-trip for `VerifyPassword`.
  private func signInWithEmailHelper() async throws {
    setFakeGetAccountProvider()
    let task = Task.detached { [auth = self.auth!, kEmail, kFakePassword] in
      try await auth.signIn(withEmail: kEmail, password: kFakePassword)
    }
    await rpcIssuer?.waitForRequest()
    try rpcIssuer?.respond(withJSON: [
      "idToken": AuthTests.kAccessToken,
      "expiresIn": "\(AuthTests.kFakeExpiresIn)",
      "refreshToken": kRefreshToken,
    ])
    _ = try await task.value
  }
}
