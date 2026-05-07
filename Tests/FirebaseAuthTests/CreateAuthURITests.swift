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
import XCTest

@testable import FirebaseAuth

@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
final class CreateAuthURITests: RPCBaseTests {
  /// The key for the "continueUri" value in the request.
  let kContinueURITestKey = "continueUri"

  /// Fake Continue URI used for testing.
  let kTestContinueURI = "ContinueUri"

  /// The expected URL for the test calls.
  let kExpectedAPIURL =
    "https://www.googleapis.com/identitytoolkit/v3/relyingparty/createAuthUri?key=APIKey"

  func testCreateAuthUriRequest() async throws {
    try await checkRequest(
      request: makeAuthURIRequest(),
      expected: kExpectedAPIURL,
      key: kContinueURITestKey,
      value: kTestContinueURI
    )
  }

  func testCreateAuthUriErrors() async throws {
    let kMissingContinueURIErrorMessage = "MISSING_CONTINUE_URI:"
    let kInvalidIdentifierErrorMessage = "INVALID_IDENTIFIER"
    let kInvalidEmailErrorMessage = "INVALID_EMAIL"
    try await checkBackendError(
      request: makeAuthURIRequest(),
      message: kMissingContinueURIErrorMessage,
      errorCode: AuthErrorCode.missingContinueURI
    )
    try await checkBackendError(
      request: makeAuthURIRequest(),
      message: kInvalidIdentifierErrorMessage,
      errorCode: AuthErrorCode.invalidEmail
    )
    try await checkBackendError(
      request: makeAuthURIRequest(),
      message: kInvalidEmailErrorMessage,
      errorCode: AuthErrorCode.invalidEmail
    )
  }

  func testSuccessfulCreateAuthURIResponse() async throws {
    let kAuthUriKey = "authUri"
    let kTestAuthUri = "AuthURI"

    let request = makeAuthURIRequest()
    let task = Task.detached { [request] in
      try await AuthBackend.post(withRequest: request)
    }
    await rpcIssuer?.waitForRequest()
    _ = try rpcIssuer?.respond(withJSON: [kAuthUriKey: kTestAuthUri])

    let response = try await task.value
    XCTAssertEqual(response.authURI, kTestAuthUri)
  }

  func testRequestAndResponseEncoding() async throws {
    let kTestExpectedKind = "identitytoolkit#CreateAuthUriResponse"
    let kTestProviderID1 = "google.com"
    let kTestProviderID2 = "facebook.com"

    let request = makeAuthURIRequest()
    let task = Task.detached { [request] in
      try await AuthBackend.post(withRequest: request)
    }
    await rpcIssuer?.waitForRequest()

    XCTAssertEqual(rpcIssuer?.requestURL?.absoluteString, kExpectedAPIURL)
    XCTAssertEqual(rpcIssuer?.decodedRequest?["identifier"] as? String, kTestIdentifier)
    XCTAssertEqual(rpcIssuer?.decodedRequest?["continueUri"] as? String, kTestContinueURI)

    _ = try rpcIssuer?.respond(withJSON: [
      "kind": kTestExpectedKind,
      "allProviders": [kTestProviderID1, kTestProviderID2],
    ])

    let response = try await task.value
    XCTAssertEqual(response.allProviders?.count, 2)
    XCTAssertEqual(response.allProviders?.first, kTestProviderID1)
    XCTAssertEqual(response.allProviders?[1], kTestProviderID2)
  }

  private func makeAuthURIRequest() -> CreateAuthURIRequest {
    return CreateAuthURIRequest(
      identifier: kTestIdentifier,
      continueURI: kTestContinueURI,
      requestConfiguration: makeRequestConfiguration()
    )
  }
}
