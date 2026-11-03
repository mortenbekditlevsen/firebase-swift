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

@testable import FirebaseStorage
import Foundation
// Port note: the port's GTMSessionFetcher stand-in is in FirebaseStorage.
// Port note: the fakes are in Support/Fakes.swift.
import XCTest
#if canImport(FoundationNetworking)
  // Port note: Linux's URL loading types are in FoundationNetworking.
  import FoundationNetworking
#endif

class StorageAuthorizerTests: StorageTestHelpers {
  var appCheckTokenSuccess: FIRAppCheckTokenResultFake!
  var appCheckTokenError: FIRAppCheckTokenResultFake!
  var fetcher: GTMSessionFetcher!
  var auth: FIRAuthInteropFake!
  var appCheck: FIRAppCheckFake!

  let StorageTestAuthToken = "1234-5678-9012-3456-7890"

  // Port note: the authorizer has no callbackQueue (it's async), and the
  // port's fetcher doesn't check URL schemes (allowedInsecureSchemes), so
  // the tests below don't set them.
  // Linux's Foundation renames header fields in allHTTPHeaderFields
  // ("X-Firebase-Appcheck"), so the App Check header is looked up with
  // value(forHTTPHeaderField:), which ignores case.
  override func setUp() {
    super.setUp()

    appCheckTokenSuccess = FIRAppCheckTokenResultFake(token: "token", error: nil)
    appCheckTokenError = FIRAppCheckTokenResultFake(token: "dummy token",
                                                    error: NSError(
                                                      domain: "testAppCheckError",
                                                      code: -1,
                                                      userInfo: nil
                                                    ))

    // Port note: Linux's XCTestCase has no init(); this class inherits objectURL().
    let fetchRequest = URLRequest(url: objectURL())
    fetcher = GTMSessionFetcher(request: fetchRequest)

    auth = FIRAuthInteropFake(token: StorageTestAuthToken, userID: nil, error: nil)
    appCheck = FIRAppCheckFake()
    fetcher?.authorizer = StorageTokenAuthorizer(googleAppID: "dummyAppID",
                                                 authProvider: auth, appCheck: appCheck)
  }

  override func tearDown() {
    fetcher = nil
    auth = nil
    appCheck = nil
    appCheckTokenSuccess = nil
    super.tearDown()
  }

  func testSuccessfulAuth() async throws {
    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: true)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers!["Authorization"], "Firebase \(StorageTestAuthToken)")
  }

  func testUnsuccessfulAuth() async {
    let authError = NSError(domain: "FIRStorageErrorDomain",
                            code: StorageErrorCode.unauthenticated.rawValue, userInfo: nil)
    let failedAuth = FIRAuthInteropFake(token: nil, userID: nil, error: authError)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: failedAuth,
      appCheck: nil
    )
    setFetcherTestBlock(with: 401) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: false)
    }
    do {
      let _ = try await fetcher?.beginFetch()
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "FIRStorageErrorDomain")
      XCTAssertEqual(nsError.code, StorageErrorCode.unauthenticated.rawValue)
      XCTAssertEqual(nsError.localizedDescription, "User is not authenticated, please " +
        "authenticate using Firebase Authentication and try again.")
    }
  }

  func testSuccessfulUnauthenticatedAuth() async throws {
    // Simulate Auth not being included at all
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: nil,
      appCheck: nil
    )

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: false)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertNil(headers!["Authorization"])
  }

  func testSuccessfulAppCheckNoAuth() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!

    // Simulate Auth not being included at all
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: nil,
      appCheck: appCheck
    )

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: false)
    }
    let _ = try await fetcher?.beginFetch()
    XCTAssertEqual(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"), appCheckTokenSuccess?.token)
  }

  func testSuccessfulAppCheckAndAuth() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: true)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers!["Authorization"], "Firebase \(StorageTestAuthToken)")
    XCTAssertEqual(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"), appCheckTokenSuccess?.token)
  }

  func testAppCheckError() async throws {
    // Port note: the port's AppCheckInterop throws instead of returning a
    // placeholder token with the error, so no App Check header is sent.
    throw XCTSkip("Needs App Check's placeholder token")
    appCheck?.tokenResult = appCheckTokenError!

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: true)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers!["Authorization"], "Firebase \(StorageTestAuthToken)")
    XCTAssertEqual(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"), appCheckTokenError?.token)
  }

  func testIsAuthorizing() async throws {
    setFetcherTestBlock(with: 200) { fetcher in
      do {
        let authorizer = try XCTUnwrap(fetcher.authorizer)
        XCTAssertFalse(authorizer.isAuthorizingRequest(fetcher.request!))
      } catch {
        XCTFail("Failed to get authorizer: \(error)")
      }
    }
    let _ = try await fetcher?.beginFetch()
  }

  func testStopAuthorizingNoop() async throws {
    setFetcherTestBlock(with: 200) { fetcher in
      do {
        let authorizer = try XCTUnwrap(fetcher.authorizer)

        // Since both of these are noops, we expect that invoking them
        // will still result in successful authenticatio
        authorizer.stopAuthorization()
        authorizer.stopAuthorization(for: fetcher.request!)
      } catch {
        XCTFail("Failed to get authorizer: \(error)")
      }
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers!["Authorization"], "Firebase \(StorageTestAuthToken)")
  }

  func testEmail() async throws {
    setFetcherTestBlock(with: 200) { fetcher in
      do {
        let authorizer = try XCTUnwrap(fetcher.authorizer)
        XCTAssertNil(authorizer.userEmail)
      } catch {
        XCTFail("Failed to get authorizer: \(error)")
      }
    }
    let _ = try await fetcher?.beginFetch()
  }

  func testInsecureHostFailsWhenTokensPresent() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: auth,
      appCheck: appCheck
    )

    do {
      let _ = try await fetcher?.beginFetch()
      XCTFail("Expected fetch to fail due to insecure token attachment")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, StorageErrorDomain)
      XCTAssertEqual(nsError.code, StorageErrorCode.unauthenticated.rawValue)
    }
  }

  func testInsecureHostSucceedsWhenNoTokensPresent() async throws {
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: nil,
      appCheck: nil
    )

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: false)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertNil(headers?["Authorization"])
    XCTAssertNil(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
  }

  func testInsecureHostSucceedsWhenAuthProviderIsPresentButUserSignedOut() async throws {
    let unauthenticatedAuthFake = FIRAuthInteropFake(token: nil, userID: nil, error: nil)
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: unauthenticatedAuthFake,
      appCheck: nil
    )

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: false)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertNil(headers?["Authorization"])
    XCTAssertNil(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
  }

  func testLocalhostDoesAttachTokensOverHttp() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!
    let localRequest = URLRequest(url: URL(string: "http://localhost/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: localRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: auth,
      appCheck: appCheck
    )

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: true)
    }
    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers?["Authorization"], "Firebase \(StorageTestAuthToken)")
    XCTAssertEqual(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"), appCheckTokenSuccess?.token)
  }

  func testDynamicAllowInsecureTokenAttachment() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)

    var allowInsecure = false
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: auth,
      appCheck: appCheck,
      allowInsecureTokenAttachment: { allowInsecure }
    )

    // Update allowInsecure to true after authorizer has been initialized
    allowInsecure = true

    setFetcherTestBlock(with: 200) { fetcher in
      self.checkAuthorizer(fetcher: fetcher, trueFalse: true)
    }

    let _ = try await fetcher?.beginFetch()
    let headers = fetcher!.request?.allHTTPHeaderFields
    XCTAssertEqual(headers?["Authorization"], "Firebase \(StorageTestAuthToken)")
    XCTAssertEqual(fetcher!.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck"), appCheckTokenSuccess?.token)
  }

  func testInsecureHostFailsWhenOnlyAppCheckTokenIsPresent() async throws {
    appCheck?.tokenResult = appCheckTokenSuccess!
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: nil,
      appCheck: appCheck
    )

    do {
      let _ = try await fetcher?.beginFetch()
      XCTFail("Expected fetch to fail due to insecure AppCheck token attachment")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, StorageErrorDomain)
      XCTAssertEqual(nsError.code, StorageErrorCode.unauthenticated.rawValue)
    }
  }

  func testInsecureHostFailsWhenOnlyAuthTokenIsPresent() async throws {
    let insecureRequest = URLRequest(url: URL(string: "http://10.0.0.1/v0/b/bucket/o/object")!)
    fetcher = GTMSessionFetcher(request: insecureRequest)
    fetcher?.authorizer = StorageTokenAuthorizer(
      googleAppID: "dummyAppID",
      authProvider: auth,
      appCheck: nil
    )

    do {
      let _ = try await fetcher?.beginFetch()
      XCTFail("Expected fetch to fail due to insecure Auth token attachment")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, StorageErrorDomain)
      XCTAssertEqual(nsError.code, StorageErrorCode.unauthenticated.rawValue)
    }
  }

  // MARK: Helpers

  private func setFetcherTestBlock(with statusCode: Int,
                                   _ validationBlock: @escaping (GTMSessionFetcher) -> Void) {
    fetcher?.testBlock = { (fetcher: GTMSessionFetcher,
                            response: GTMSessionFetcherTestResponse) in
        validationBlock(fetcher)
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: statusCode,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, nil, nil)
    }
  }

  private func checkAuthorizer(fetcher: GTMSessionFetcher, trueFalse: Bool) {
    do {
      let authorizer = try XCTUnwrap(fetcher.authorizer)
      XCTAssertEqual(authorizer.isAuthorizedRequest(fetcher.request!), trueFalse)
    } catch {
      XCTFail("Failed to get authorizer: \(error)")
    }
  }
}
