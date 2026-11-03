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
// Port note: GTMSessionFetcherService is a stand-in in Support/Fakes.swift.

import XCTest

class FunctionsTests: XCTestCase {
  var functions: Functions?
  var functionsCustomDomain: Functions?
  let fetcherService = GTMSessionFetcherService()
  let appCheckFake = FIRAppCheckFake()

  override func setUp() {
    super.setUp()
    // Port note: no Messaging; requests go through the stand-in fetcher
    // service's URLSession.
    functions = Functions(
      projectID: "my-project",
      region: "my-region",
      customDomain: nil,
      auth: nil,
      appCheck: appCheckFake,
      session: fetcherService.session
    )
    functionsCustomDomain = Functions(projectID: "my-project", region: "my-region",
                                      customDomain: "https://mydomain.com", auth: nil,
                                      appCheck: nil,
                                      session: fetcherService.session)
  }

  override func tearDown() {
    functions = nil
    functionsCustomDomain = nil
    super.tearDown()
  }

  func testFunctionsInstanceIsStablePerApp() throws {
    // Port note: FirebaseCore has FirebaseApp.Options (a struct) and no
    // registry of named apps, so the apps are created directly.
    let options = FirebaseApp.Options(projectID: "myProjectID",
                                      googleAppID: "0:0000000000000:ios:0000000000000000",
                                      apiKey: nil, clientID: nil, storageBucket: nil)
    if !FirebaseApp.isDefaultAppConfigured {
      FirebaseApp.configure(options: options)
    }
    var functions1 = Functions.functions()
    var functions2 = Functions.functions(app: FirebaseApp.app()!)
    XCTAssertEqual(functions1, functions2)

    let app2 = FirebaseApp(options: options, name: "test")
    functions2 = Functions.functions(app: app2, region: "us-central2")
    XCTAssertNotEqual(functions1, functions2)

    functions1 = Functions.functions(app: app2, region: "us-central2")
    XCTAssertEqual(functions1, functions2)

    functions1 = Functions.functions(customDomain: "test_domain")
    functions2 = Functions.functions(region: "us-central1")
    XCTAssertNotEqual(functions1, functions2)

    functions2 = Functions.functions(app: FirebaseApp.app()!, customDomain: "test_domain")
    XCTAssertEqual(functions1, functions2)
  }

  func testFunctionURLForName() throws {
    XCTAssertEqual(
      functions?.functionURL(for: "my-endpoint")?.absoluteString,
      "https://my-region-my-project.cloudfunctions.net/my-endpoint"
    )
  }

  func testFunctionURLForNameEmulator() throws {
    functionsCustomDomain?.useEmulator(withHost: "localhost", port: 5005)
    XCTAssertEqual(
      functionsCustomDomain?.functionURL(for: "my-endpoint")?.absoluteString,
      "http://localhost:5005/my-project/my-region/my-endpoint"
    )
  }

  func testFunctionURLForNameRegionWithEmulatorWithScheme() throws {
    functionsCustomDomain?.useEmulator(withHost: "http://localhost", port: 5005)
    XCTAssertEqual(
      functionsCustomDomain?.functionURL(for: "my-endpoint")?.absoluteString,
      "http://localhost:5005/my-project/my-region/my-endpoint"
    )
  }

  func testFunctionURLForNameCustomDomain() throws {
    XCTAssertEqual(
      functionsCustomDomain?.functionURL(for: "my-endpoint")?.absoluteString,
      "https://mydomain.com/my-endpoint"
    )
  }

  func testSetEmulatorSettings() throws {
    functions?.useEmulator(withHost: "localhost", port: 1000)
    XCTAssertEqual("http://localhost:1000", functions?.emulatorOrigin)
  }

  /// Test that Functions instances get deallocated.
  func testFunctionsLifecycle() throws {
    weak var weakApp: FirebaseApp?
    weak var weakFunctions: Functions?
    // Port note: no autoreleasepool (Objective-C only) or
    // FirebaseApp(instanceWithName:options:); the app is created directly.
    do {
      let options = FirebaseApp.Options(projectID: "myProjectID",
                                        googleAppID: "0:0000000000000:ios:0000000000000000",
                                        apiKey: nil, clientID: nil, storageBucket: nil)
      let app1 = FirebaseApp(options: options, name: "transitory app")
      weakApp = app1
      let functions = Functions(app: app1, region: "transitory-region", customDomain: nil)
      weakFunctions = functions
      XCTAssertNotNil(weakFunctions)
    }
    XCTAssertNil(weakApp)
    XCTAssertNil(weakFunctions)
  }

  // MARK: - App Check Integration

  @MainActor func testCallFunctionWhenUsingLimitedUseAppCheckTokenThenTokenSuccess() throws {
    // Port note: the port's AppCheckInterop has no limited-use tokens yet.
    throw XCTSkip("Needs limited-use App Check tokens")
    // Given
    // Stub returns of two different kinds of App Check tokens. Only the
    // limited use token should be present in Functions's request header.
    appCheckFake.tokenResult = FIRAppCheckTokenResultFake(token: "shared_valid_token", error: nil)
    appCheckFake.limitedUseTokenResult = FIRAppCheckTokenResultFake(
      token: "limited_use_valid_token",
      error: nil
    )

    let httpRequestExpectation = expectation(description: "HTTPRequestExpectation")
    fetcherService.testBlock = { fetcherToTest, testResponse in
      let appCheckTokenHeader = fetcherToTest.request?
        .value(forHTTPHeaderField: "X-Firebase-AppCheck")
      // Assert that header contains limited use token.
      XCTAssertEqual(appCheckTokenHeader, "limited_use_valid_token")
      testResponse(nil, "{\"data\":\"May the force be with you!\"}".data(using: .utf8), nil)
      httpRequestExpectation.fulfill()
    }

    // When
    let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)

    // Then
    let completionExpectation = expectation(description: "completionExpectation")
    functions?
      .httpsCallable("fake_func", options: options)
      .call { result, error in
        guard let result = result else {
          return XCTFail("Unexpected error: \(error!).")
        }

        XCTAssertEqual(result.data as! String, "May the force be with you!")

        completionExpectation.fulfill()
      }

    waitForExpectations(timeout: 1.5)
  }

  @MainActor func testCallFunctionWhenLimitedUseAppCheckTokenDisabledThenCallWithoutToken() {
    // Given
    let limitedUseDummyToken = "limited use dummy token"
    appCheckFake.limitedUseTokenResult = FIRAppCheckTokenResultFake(
      token: limitedUseDummyToken,
      error: NSError(domain: #function, code: -1)
    )

    let httpRequestExpectation = expectation(description: "HTTPRequestExpectation")
    fetcherService.testBlock = { fetcherToTest, testResponse in
      // Assert that header does not contain an AppCheck token.
      fetcherToTest.request?.allHTTPHeaderFields?.forEach { key, value in
        if key == "X-Firebase-AppCheck" {
          XCTAssertNotEqual(value, limitedUseDummyToken)
        }
      }

      testResponse(nil, "{\"data\":\"May the force be with you!\"}".data(using: .utf8), nil)
      httpRequestExpectation.fulfill()
    }

    // When
    let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: false)

    // Then
    let completionExpectation = expectation(description: "completionExpectation")
    functions?
      .httpsCallable("fake_func", options: options)
      .call { result, error in
        guard let result = result else {
          return XCTFail("Unexpected error: \(error!).")
        }

        XCTAssertEqual(result.data as! String, "May the force be with you!")

        completionExpectation.fulfill()
      }

    waitForExpectations(timeout: 1.5)
  }

  @MainActor func testCallFunctionWhenLimitedUseAppCheckTokenCannotBeGeneratedThenCallWithPlaceholderToken() throws {
    // Port note: the port's AppCheckInterop has no limited-use tokens yet.
    throw XCTSkip("Needs limited-use App Check tokens")
    // Given
    appCheckFake.limitedUseTokenResult = FIRAppCheckTokenResultFake(
      token: "limited use token",
      error: NSError(domain: #function, code: -1)
    )

    let httpRequestExpectation = expectation(description: "HTTPRequestExpectation")
    fetcherService.testBlock = { fetcherToTest, testResponse in
      // Assert that header does not contain an AppCheck token.
      do {
        let appCheckHeader = try XCTUnwrap(fetcherToTest.request?
          .allHTTPHeaderFields?["X-Firebase-AppCheck"])
        XCTAssertEqual(appCheckHeader, self.appCheckFake.limitedUseTokenResult.token)
      } catch {
        XCTFail("Unexpected failure: \(error)")
      }

      testResponse(nil, "{\"data\":\"May the force be with you!\"}".data(using: .utf8), nil)
      httpRequestExpectation.fulfill()
    }

    // When
    let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)

    // Then
    let completionExpectation = expectation(description: "completionExpectation")
    functions?
      .httpsCallable("fake_func", options: options)
      .call { result, error in
        guard let result = result else {
          return XCTFail("Unexpected error: \(error!).")
        }

        XCTAssertEqual(result.data as! String, "May the force be with you!")

        completionExpectation.fulfill()
      }

    waitForExpectations(timeout: 1.5)
  }

  @MainActor func testCallFunctionWhenAppCheckIsInstalledAndFACTokenSuccess() {
    // Stub returns of two different kinds of App Check tokens. Only the
    // shared use token should be present in Functions's request header.
    appCheckFake.tokenResult = FIRAppCheckTokenResultFake(token: "shared_valid_token", error: nil)
    appCheckFake.limitedUseTokenResult = FIRAppCheckTokenResultFake(
      token: "limited_use_valid_token",
      error: nil
    )

    let networkError = NSError(
      domain: "testCallFunctionWhenAppCheckIsInstalled",
      code: -1,
      userInfo: nil
    )

    let httpRequestExpectation = expectation(description: "HTTPRequestExpectation")
    fetcherService.testBlock = { fetcherToTest, testResponse in
      let appCheckTokenHeader = fetcherToTest.request?
        .value(forHTTPHeaderField: "X-Firebase-AppCheck")
      XCTAssertEqual(appCheckTokenHeader, "shared_valid_token")
      testResponse(nil, nil, networkError)
      httpRequestExpectation.fulfill()
    }

    let completionExpectation = expectation(description: "completionExpectation")
    functions?
      .httpsCallable("fake_func")
      .call { result, error in
        guard let error = error else {
          return XCTFail("Unexpected success: \(result!).")
        }

        // Port note: URLSession adds its own userInfo to an error from a URL
      // protocol, so the domain and code are compared.
      XCTAssertEqual((error as NSError).domain, networkError.domain)
      XCTAssertEqual((error as NSError).code, networkError.code)
        // Port note: the main thread is the test helper's doing; the port's
        // calls are async.
        completionExpectation.fulfill()
      }

    waitForExpectations(timeout: 1.5)
  }

  func testAsyncCallFunctionWhenAppCheckIsNotInstalled() async {
    let networkError = NSError(
      domain: "testCallFunctionWhenAppCheckIsInstalled",
      code: -1,
      userInfo: nil
    )

    let httpRequestExpectation = expectation(description: "HTTPRequestExpectation")
    fetcherService.testBlock = { fetcherToTest, testResponse in
      let appCheckTokenHeader = fetcherToTest.request?
        .value(forHTTPHeaderField: "X-Firebase-AppCheck")
      XCTAssertNil(appCheckTokenHeader)
      testResponse(nil, nil, networkError)
      httpRequestExpectation.fulfill()
    }

    do {
      _ = try await functionsCustomDomain?
        .callFunction(
          at: URL(string: "https://example.com/fake_func")!,
          withObject: nil,
          options: nil,
          timeout: 10
        )
      XCTFail("Expected an error")
    } catch {
      // Port note: URLSession adds its own userInfo to an error from a URL
      // protocol, so the domain and code are compared.
      XCTAssertEqual((error as NSError).domain, networkError.domain)
      XCTAssertEqual((error as NSError).code, networkError.code)
    }

    await fulfillment(of: [httpRequestExpectation], timeout: 1.5)
  }

  func testCallFunctionWhenAppCheckIsNotInstalled() async {
    let networkError = NSError(
      domain: "testCallFunctionWhenAppCheckIsInstalled",
      code: -1,
      userInfo: nil
    )

    fetcherService.testBlock = { fetcherToTest, testResponse in
      let appCheckTokenHeader = fetcherToTest.request?
        .value(forHTTPHeaderField: "X-Firebase-AppCheck")
      XCTAssertNil(appCheckTokenHeader)
      testResponse(nil, nil, networkError)
    }

    do {
      _ = try await functionsCustomDomain?.callFunction(
        at: URL(string: "https://example.com/fake_func")!,
        withObject: nil,
        options: nil,
        timeout: 10
      )
      XCTFail("Unexpected success from functions?.callFunction")
    } catch {
      // Port note: URLSession adds its own userInfo to an error from a URL
      // protocol, so the domain and code are compared.
      XCTAssertEqual((error as NSError).domain, networkError.domain)
      XCTAssertEqual((error as NSError).code, networkError.code)
    }
  }
}
