// Copyright 2022 Google LLC
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

import FirebaseCore
@testable import FirebaseFunctions

// Port note: the interop protocols are in FirebaseCore, and the fakes in
// Support/Fakes.swift. The port has no Messaging, so there's no FCM token:
// the `messaging:` arguments are gone, and fcmToken is checked to be nil.

import XCTest

class ContextProviderTests: XCTestCase {
  let appCheckFake = FIRAppCheckFake()
  let appCheckTokenError = FIRAppCheckTokenResultFake(token: "dummy token",
                                                      error: NSError(
                                                        domain: "testAppCheckError",
                                                        code: -1,
                                                        userInfo: nil
                                                      ))
  let appCheckLimitedUseTokenError = FIRAppCheckTokenResultFake(token: "limited use token",
                                                                error: NSError(
                                                                  domain: "testAppCheckError",
                                                                  code: -1,
                                                                  userInfo: nil
                                                                ))
  let appCheckTokenSuccess = FIRAppCheckTokenResultFake(token: "valid_token", error: nil)

  func testAsyncContextWithAuth() async throws {
    let auth = FIRAuthInteropFake(token: "token", userID: "userID", error: nil)
    let provider = FunctionsContextProvider(auth: auth, appCheck: nil)

    let context = try await provider.context(options: nil)

    XCTAssertNotNil(context)
    XCTAssertEqual(context.authToken, "token")
    XCTAssertNil(context.fcmToken)
  }

  func testContextWithAuth() async throws {
    let auth = FIRAuthInteropFake(token: "token", userID: "userID", error: nil)
    let provider = FunctionsContextProvider(auth: auth, appCheck: nil)
    let context = try await provider.context(options: nil)
    XCTAssertEqual(context.authToken, "token")
    XCTAssertNil(context.fcmToken)
  }

  func testAsyncContextWithAuthError() async {
    let authError = NSError(domain: "com.functions.tests", code: 4, userInfo: nil)
    let auth = FIRAuthInteropFake(token: nil, userID: "userID", error: authError)
    let provider = FunctionsContextProvider(auth: auth, appCheck: nil)

    do {
      _ = try await provider.context(options: nil)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError, authError)
    }
  }

  func testContextWithAuthError() async throws {
    let authError = NSError(domain: "com.functions.tests", code: 4, userInfo: nil)
    let auth = FIRAuthInteropFake(token: nil, userID: "userID", error: authError)
    let provider = FunctionsContextProvider(auth: auth, appCheck: nil)
    do {
      _ = try await provider.context(options: nil)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError?, authError)
    }
  }

  func testAsyncContextWithoutAuth() async throws {
    let provider = FunctionsContextProvider(auth: nil, appCheck: nil)

    let context = try await provider.context(options: nil)

    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
  }

  func testContextWithoutAuth() async throws {
    let provider = FunctionsContextProvider(auth: nil, appCheck: nil)
    let context = try await provider.context(options: nil)
    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
  }

  func testAsyncContextWithAppCheckOnlySuccess() async throws {
    appCheckFake.tokenResult = appCheckTokenSuccess
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)

    let context = try await provider.context(options: nil)

    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    XCTAssertEqual(context.appCheckToken, appCheckTokenSuccess.token)
  }

  func testContextWithAppCheckOnlySuccess() async throws {
    appCheckFake.tokenResult = appCheckTokenSuccess
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)
    let context = try await provider.context(options: nil)
    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    XCTAssertEqual(context.appCheckToken, appCheckTokenSuccess.token)
  }

  func testAsyncContextWithAppCheckOnlyError() async throws {
    appCheckFake.tokenResult = appCheckTokenError
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)

    let context = try await provider.context(options: nil)

    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    // Port note: upstream sends App Check's placeholder token on an error;
    // the port's AppCheckInterop throws instead, so there's no token.
    XCTAssertNil(context.appCheckToken)
  }

  func testAsyncContextWithAppCheckOnlyError_LimitedUseToken() async throws {
    appCheckFake.limitedUseTokenResult = appCheckLimitedUseTokenError
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)

    let context = try await provider.context(options: .init(requireLimitedUseAppCheckTokens: true))

    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    // Port note: the port's AppCheckInterop has no limited-use tokens yet.
    XCTAssertNil(context.limitedUseAppCheckToken)
  }

  func testContextWithAppCheckOnlyError() async throws {
    appCheckFake.tokenResult = appCheckTokenError
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)
    let context = try await provider.context(options: nil)
    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    // Port note: upstream sends App Check's placeholder token on an error;
    // the port's AppCheckInterop throws instead, so there's no token.
    XCTAssertNil(context.appCheckToken)
  }

  func testContextWithAppCheckOnlyError_LimitedUseToken() async throws {
    appCheckFake.limitedUseTokenResult = appCheckLimitedUseTokenError
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheckFake)
    let context = try await provider
      .context(options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true))
    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    // Port note: the port's AppCheckInterop has no limited-use tokens yet.
    XCTAssertNil(context.limitedUseAppCheckToken)
  }

  func testAsyncContextWithAppCheckWithoutOptionalMethods() async throws {
    let appCheck = AppCheckFakeWithoutOptionalMethods(tokenResult: appCheckTokenSuccess)
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheck)

    let context = try await provider.context(options: .init(requireLimitedUseAppCheckTokens: true))

    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    XCTAssertNil(context.appCheckToken)
    // If the method for limited-use tokens is not implemented, the value should be `nil`:
    XCTAssertNil(context.limitedUseAppCheckToken)
  }

  func testContextWithAppCheckWithoutOptionalMethods() async throws {
    let appCheck = AppCheckFakeWithoutOptionalMethods(tokenResult: appCheckTokenSuccess)
    let provider = FunctionsContextProvider(auth: nil, appCheck: appCheck)
    let context = try await provider.context(options: .init(requireLimitedUseAppCheckTokens: true))
    XCTAssertNil(context.authToken)
    XCTAssertNil(context.fcmToken)
    XCTAssertNil(context.appCheckToken)
    // If the method for limited-use tokens is not implemented, the value should be `nil`:
    XCTAssertNil(context.limitedUseAppCheckToken)
  }

  func testAsyncAllContextsAvailableSuccess() async throws {
    appCheckFake.tokenResult = appCheckTokenSuccess
    let auth = FIRAuthInteropFake(token: "token", userID: "userID", error: nil)
    let provider = FunctionsContextProvider(
      auth: auth,
      appCheck: appCheckFake
    )

    let context = try await provider.context(options: nil)

    XCTAssertEqual(context.authToken, "token")
    XCTAssertNil(context.fcmToken)
    XCTAssertEqual(context.appCheckToken, appCheckTokenSuccess.token)
  }

  func testAllContextsAvailableSuccess() async throws {
    appCheckFake.tokenResult = appCheckTokenSuccess
    let auth = FIRAuthInteropFake(token: "token", userID: "userID", error: nil)
    let provider = FunctionsContextProvider(
      auth: auth,
      appCheck: appCheckFake
    )
    let context = try await provider.context(options: nil)
    XCTAssertEqual(context.authToken, "token")
    XCTAssertNil(context.fcmToken)
    XCTAssertEqual(context.appCheckToken, appCheckTokenSuccess.token)
  }

  func testAsyncAllContextsAuthAndAppCheckError() async {
    appCheckFake.tokenResult = appCheckTokenError
    let authError = NSError(domain: "com.functions.tests", code: 4, userInfo: nil)
    let auth = FIRAuthInteropFake(token: nil, userID: "userID", error: authError)
    let provider = FunctionsContextProvider(
      auth: auth,
      appCheck: appCheckFake
    )

    do {
      _ = try await provider.context(options: nil)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError, authError)
    }
  }

  func testAllContextsAuthAndAppCheckError() async throws {
    appCheckFake.tokenResult = appCheckTokenError
    let authError = NSError(domain: "com.functions.tests", code: 4, userInfo: nil)
    let auth = FIRAuthInteropFake(token: nil, userID: "userID", error: authError)
    let provider = FunctionsContextProvider(
      auth: auth,
      appCheck: appCheckFake
    )
    do {
      _ = try await provider.context(options: nil)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError?, authError)
    }
  }

  func testAllContextsAuthAndAppCheckError_LimitedUseToken() async throws {
    appCheckFake.limitedUseTokenResult = appCheckLimitedUseTokenError
    let authError = NSError(domain: "com.functions.tests", code: 4, userInfo: nil)
    let auth = FIRAuthInteropFake(token: nil, userID: "userID", error: authError)
    let provider = FunctionsContextProvider(
      auth: auth,
      appCheck: appCheckFake
    )
    do {
      _ = try await provider.context(options: .init(requireLimitedUseAppCheckTokens: true))
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as NSError?, authError)
    }
  }
}

// MARK: - Utilities

// Port note: the port's AppCheckInterop has only `getToken`, which is all this
// fake implements upstream too.
private final class AppCheckFakeWithoutOptionalMethods: AppCheckInterop, @unchecked Sendable {
  let tokenResult: FIRAppCheckTokenResultFake

  init(tokenResult: FIRAppCheckTokenResultFake) {
    self.tokenResult = tokenResult
  }

  func getToken(forcingRefresh: Bool) async throws -> String {
    if let error = tokenResult.error { throw error }
    return tokenResult.token
  }
}
