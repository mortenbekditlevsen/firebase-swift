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

/// An implementation of `AuthBackendRPCIssuer` used to test backend request,
/// response, and glue logic.
///
/// The fake captures each issued request and suspends `asyncPostToURL` on a
/// pending continuation. The test then inspects the captured request, calls
/// one of the `respond(...)` methods to drive the suspended task forward, and
/// awaits the resulting `AuthBackend.post(...)` value.
///
/// The test pattern is:
///
/// ```swift
/// async let task = AuthBackend.post(withRequest: makeRequest())
/// try await rpcIssuer.waitForRequest()
/// XCTAssertEqual(rpcIssuer.requestURL?.absoluteString, expected)
/// try rpcIssuer.respond(withJSON: [...])
/// let response = try await task
/// ```
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
final class FakeBackendRPCIssuer: AuthBackendRPCIssuer, @unchecked Sendable {
  // MARK: - Captured request data (most recent)

  private let _requestURL: Mutex<URL?> = .init(nil)
  private let _requestData: Mutex<Data?> = .init(nil)
  private let _decodedRequest: Mutex<[String: Any]?> = .init(nil)
  private let _contentType: Mutex<String?> = .init(nil)
  private let _request: Mutex<(any AuthRPCRequest)?> = .init(nil)

  var requestURL: URL? { _requestURL.withLock { $0 } }
  var requestData: Data? { _requestData.withLock { $0 } }
  var decodedRequest: [String: Any]? { _decodedRequest.withLock { $0 } }
  var contentType: String? { _contentType.withLock { $0 } }
  var request: (any AuthRPCRequest)? { _request.withLock { $0 } }

  // MARK: - Per-request inspection hooks

  private struct Hooks: @unchecked Sendable {
    var verifyRequester: ((SendVerificationCodeRequest) -> Void)?
    var verifyClientRequester: ((VerifyClientRequest) -> Void)?
    var projectConfigRequester: ((GetProjectConfigRequest) -> Void)?
    var verifyPasswordRequester: ((VerifyPasswordRequest) -> Void)?
    var verifyPhoneNumberRequester: ((VerifyPhoneNumberRequest) -> Void)?
  }

  private let _hooks: Mutex<Hooks> = .init(Hooks())

  var verifyRequester: ((SendVerificationCodeRequest) -> Void)? {
    get { _hooks.withLock { $0.verifyRequester } }
    set { _hooks.withLock { $0.verifyRequester = newValue } }
  }

  var verifyClientRequester: ((VerifyClientRequest) -> Void)? {
    get { _hooks.withLock { $0.verifyClientRequester } }
    set { _hooks.withLock { $0.verifyClientRequester = newValue } }
  }

  var projectConfigRequester: ((GetProjectConfigRequest) -> Void)? {
    get { _hooks.withLock { $0.projectConfigRequester } }
    set { _hooks.withLock { $0.projectConfigRequester = newValue } }
  }

  var verifyPasswordRequester: ((VerifyPasswordRequest) -> Void)? {
    get { _hooks.withLock { $0.verifyPasswordRequester } }
    set { _hooks.withLock { $0.verifyPasswordRequester = newValue } }
  }

  var verifyPhoneNumberRequester: ((VerifyPhoneNumberRequest) -> Void)? {
    get { _hooks.withLock { $0.verifyPhoneNumberRequester } }
    set { _hooks.withLock { $0.verifyPhoneNumberRequester = newValue } }
  }

  // MARK: - Canned responses for short-circuited request types

  private struct Canned: @unchecked Sendable {
    var fakeGetAccountProviderJSON: [[String: Any]]?
    var fakeSecureTokenServiceJSON: [String: Any]?
    var secureTokenNetworkError: NSError?
    var secureTokenErrorString: String?
  }

  private let _canned: Mutex<Canned> = .init(Canned())

  var fakeGetAccountProviderJSON: [[String: Any]]? {
    get { _canned.withLock { $0.fakeGetAccountProviderJSON } }
    set { _canned.withLock { $0.fakeGetAccountProviderJSON = newValue } }
  }

  var fakeSecureTokenServiceJSON: [String: Any]? {
    get { _canned.withLock { $0.fakeSecureTokenServiceJSON } }
    set { _canned.withLock { $0.fakeSecureTokenServiceJSON = newValue } }
  }

  var secureTokenNetworkError: NSError? {
    get { _canned.withLock { $0.secureTokenNetworkError } }
    set { _canned.withLock { $0.secureTokenNetworkError = newValue } }
  }

  var secureTokenErrorString: String? {
    get { _canned.withLock { $0.secureTokenErrorString } }
    set { _canned.withLock { $0.secureTokenErrorString = newValue } }
  }

  // MARK: - Pending request / response continuations

  private struct Pending {
    var requestArrived: [CheckedContinuation<Void, Never>] = []
    var pendingResponse: CheckedContinuation<Data, Error>?
  }

  private let _pending: Mutex<Pending> = .init(Pending())

  /// Waits until `asyncPostToURL` has captured a request. Returns immediately
  /// if a request is already pending response.
  func waitForRequest() async {
    let alreadyWaiting = _pending.withLock { $0.pendingResponse != nil }
    if alreadyWaiting { return }
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      let resumeNow = _pending.withLock { pending -> Bool in
        if pending.pendingResponse != nil { return true }
        pending.requestArrived.append(cont)
        return false
      }
      if resumeNow { cont.resume() }
    }
  }

  // MARK: - AuthBackendRPCIssuer

  func asyncPostToURL<T: AuthRPCRequest>(withRequest request: T,
                                         body: Data?,
                                         contentType: String) async throws -> Data {
    _contentType.withLock { $0 = contentType }
    _request.withLock { $0 = request }
    _requestURL.withLock { $0 = request.requestURL() }
    _requestData.withLock { $0 = body }
    if let body {
      _decodedRequest.withLock {
        $0 = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
      }
    } else {
      _decodedRequest.withLock { $0 = nil }
    }

    runHooks(for: request)

    if let canned = try shortCircuitResponse(for: request) {
      return canned
    }

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
      let waiters: [CheckedContinuation<Void, Never>] = _pending.withLock { pending in
        pending.pendingResponse = cont
        let drained = pending.requestArrived
        pending.requestArrived.removeAll()
        return drained
      }
      for w in waiters { w.resume() }
    }
  }

  // MARK: - respond(...)

  @discardableResult
  func respond(withJSON json: [String: Any], error: NSError? = nil) throws -> Data {
    let data = try JSONSerialization.data(
      withJSONObject: json,
      options: JSONSerialization.WritingOptions.prettyPrinted
    )
    try respond(withData: data, error: error)
    return data
  }

  @discardableResult
  func respond(serverErrorMessage errorMessage: String) throws -> Data {
    // Send the server error envelope as a successful HTTP body. The backend
    // implementation translates this to an AuthErrorCode; the fake mustn't
    // surface a network error here.
    return try respond(withJSON: ["error": ["message": errorMessage]])
  }

  @discardableResult
  func respond(serverErrorMessage errorMessage: String, error: NSError) throws -> Data {
    return try respond(withJSON: ["error": ["message": errorMessage]], error: error)
  }

  @discardableResult
  func respond(underlyingErrorMessage errorMessage: String,
               message: String = "See the reason") throws -> Data {
    return try respond(
      withJSON: ["error": [
        "message": message,
        "errors": [["reason": errorMessage]],
      ] as [String: Any]]
    )
  }

  func respond(withData data: Data?, error: NSError?) throws {
    let cont = _pending.withLock { pending -> CheckedContinuation<Data, Error>? in
      let c = pending.pendingResponse
      pending.pendingResponse = nil
      return c
    }
    guard let cont else {
      XCTFail("There is no pending RPC request.")
      return
    }
    XCTAssertTrue(
      data != nil || error != nil,
      "At least one of: data or error should be non-nil."
    )
    if let error {
      cont.resume(throwing: error)
    } else if let data {
      cont.resume(returning: data)
    } else {
      cont.resume(throwing: NSError(domain: "FakeBackendRPCIssuer", code: 0))
    }
  }

  // MARK: - Private

  private func runHooks<T: AuthRPCRequest>(for request: T) {
    let hooks = _hooks.withLock { $0 }
    if let h = hooks.verifyRequester, let r = request as? SendVerificationCodeRequest {
      h(r)
    } else if let h = hooks.verifyClientRequester, let r = request as? VerifyClientRequest {
      h(r)
    } else if let h = hooks.projectConfigRequester, let r = request as? GetProjectConfigRequest {
      h(r)
    } else if let h = hooks.verifyPasswordRequester, let r = request as? VerifyPasswordRequest {
      h(r)
    } else if let h = hooks.verifyPhoneNumberRequester,
              let r = request as? VerifyPhoneNumberRequest {
      h(r)
    }
  }

  private func shortCircuitResponse<T: AuthRPCRequest>(for request: T) throws -> Data? {
    if request is GetAccountInfoRequest, let json = fakeGetAccountProviderJSON {
      return try JSONSerialization.data(
        withJSONObject: ["users": json],
        options: .prettyPrinted
      )
    }
    if request is SecureTokenRequest {
      if let err = secureTokenNetworkError {
        throw err
      }
      if let msg = secureTokenErrorString {
        return try JSONSerialization.data(
          withJSONObject: ["error": ["message": msg]],
          options: .prettyPrinted
        )
      }
      if let json = fakeSecureTokenServiceJSON {
        return try JSONSerialization.data(
          withJSONObject: json,
          options: .prettyPrinted
        )
      }
    }
    return nil
  }
}
