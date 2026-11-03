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

// Swift counterparts of the fakes in upstream's SharedTestUtilities, for the
// port's interop protocols, and a stand-in for GTMSessionFetcherService's
// test block, which upstream's tests use to answer requests.

import FirebaseCore
@testable import FirebaseFunctions
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import XCTest

final class FIRAuthInteropFake: AuthInterop, @unchecked Sendable {
  let token: String?
  let userID: String?
  let error: Error?

  init(token: String?, userID: String?, error: Error?) {
    self.token = token
    self.userID = userID
    self.error = error
  }

  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String? {
    if let error { throw error }
    return token
  }

  func getUserID() -> String? { userID }
}

final class FIRAppCheckTokenResultFake: @unchecked Sendable {
  let token: String
  let error: Error?

  init(token: String, error: Error?) {
    self.token = token
    self.error = error
  }
}

/// The port's AppCheckInterop throws where upstream's returns a result with
/// an error (and a placeholder token).
final class FIRAppCheckFake: AppCheckInterop, @unchecked Sendable {
  private let lock = NSLock()
  private var _tokenResult = FIRAppCheckTokenResultFake(token: "fake_valid_token", error: nil)
  private var _limitedUseTokenResult = FIRAppCheckTokenResultFake(
    token: "fake_limited_use_valid_token", error: nil
  )

  var tokenResult: FIRAppCheckTokenResultFake {
    get { lock.withLock { _tokenResult } }
    set { lock.withLock { _tokenResult = newValue } }
  }

  var limitedUseTokenResult: FIRAppCheckTokenResultFake {
    get { lock.withLock { _limitedUseTokenResult } }
    set { lock.withLock { _limitedUseTokenResult = newValue } }
  }

  func getToken(forcingRefresh: Bool) async throws -> String {
    let result = tokenResult
    if let error = result.error { throw error }
    return result.token
  }
}

/// Stands in for GTMSessionFetcher in upstream's test blocks.
struct GTMSessionFetcher {
  let request: URLRequest?
}

/// Stands in for GTMSessionFetcherService: requests through `session` go to
/// `testBlock` instead of the network.
final class GTMSessionFetcherService: @unchecked Sendable {
  typealias TestResponse = (HTTPURLResponse?, Data?, Error?) -> Void
  typealias TestBlock = (GTMSessionFetcher, @escaping TestResponse) -> Void

  var testBlock: TestBlock? {
    get { StubURLProtocol.testBlock }
    set { StubURLProtocol.testBlock = newValue }
  }

  let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }()
}

/// Answers requests with the current test block. Tests run one at a time, so
/// there is one block at a time, as with upstream's fetcher service.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var _testBlock: GTMSessionFetcherService.TestBlock?

  static var testBlock: GTMSessionFetcherService.TestBlock? {
    get { lock.withLock { _testBlock } }
    set { lock.withLock { _testBlock = newValue } }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let testBlock = Self.testBlock else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    // URLSession moves the body to a stream before protocols see it.
    var request = self.request
    if request.httpBody == nil, let stream = request.httpBodyStream {
      request.httpBody = Data(reading: stream)
    }
    testBlock(GTMSessionFetcher(request: request)) { [self] response, data, error in
      if let error {
        client?.urlProtocol(self, didFailWithError: error)
        return
      }
      // As GTMSessionFetcher, no response means 200.
      let response = response ?? HTTPURLResponse(url: request.url!, statusCode: 200,
                                                 httpVersion: "HTTP/1.1", headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if let data {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

private extension Data {
  init(reading stream: InputStream) {
    self.init()
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      append(buffer, count: count)
    }
  }
}

extension HTTPSCallable {
  /// Upstream's completion-handler form, which the port leaves out (it's async
  /// only), for upstream's tests. Like upstream's, it completes on the main
  /// queue.
  func call(_ data: Any? = nil,
            completion: @escaping @MainActor (HTTPSCallableResult?, Error?) -> Void) {
    nonisolated(unsafe) let data = data
    Task {
      do {
        let result = try await call(data)
        nonisolated(unsafe) let sendable = result
        await MainActor.run { completion(sendable, nil) }
      } catch {
        await MainActor.run { completion(nil, error) }
      }
    }
  }
}
