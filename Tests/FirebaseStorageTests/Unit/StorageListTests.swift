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
import XCTest
#if canImport(FoundationNetworking)
  // Port note: Linux's URL loading types are in FoundationNetworking.
  import FoundationNetworking
#endif

class StorageListTests: StorageTestHelpers {
  // Port note: list and listAll are async only, so these tests await them
  // instead of waiting for completion handlers. An async call returns once,
  // so "called once" holds by construction.
  func testValidatesInput() async {
    let ref = storage().reference(withPath: "object")
    for (maxResults, pageToken) in [(Int64(0), nil), (1001, nil), (0, "foo"), (1001, "foo")]
      as [(Int64, String?)] {
      do {
        if let pageToken {
          _ = try await ref.list(maxResults: maxResults, pageToken: pageToken)
        } else {
          _ = try await ref.list(maxResults: maxResults)
        }
        XCTFail("Listing \(maxResults) results succeeded")
      } catch {
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, "FIRStorageErrorDomain")
        XCTAssertEqual(nsError.code, StorageErrorCode.invalidArgument.rawValue)
      }
    }
  }

  func testListAllCallbackOnlyCalledOnce() async {
    // Port note: upstream reaches the network and fails there; the test
    // block fails the request instead.
    await StorageFetcherService.shared.updateTestBlock { _, response in
      response(nil, nil, NSError(domain: "test", code: -1))
    }
    let ref = storage().reference(withPath: "object")
    do {
      _ = try await ref.listAll()
      XCTFail("listAll succeeded")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "FIRStorageErrorDomain")
      XCTAssertEqual(nsError.code, StorageErrorCode.unknown.rawValue)
    }
  }

  func testDefaultList() async throws {
    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let url = fetcher.request!.url!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "firebasestorage.googleapis.com")
        XCTAssertEqual(url.port, 443)
        XCTAssertEqual(url.path, "/v0/b/bucket/o")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(queryItems.count, 3)
        for item in queryItems {
          switch item.name {
          case "prefix": XCTAssertEqual(item.value, "object/")
          case "delimiter": XCTAssertEqual(item.value, "/")
          case "maxResults": XCTAssertEqual(item.value, "10")
          default: XCTFail("Unexpected URLComponent Query Item")
          }
        }
        XCTAssertEqual(fetcher.request?.httpMethod, "GET")
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, nil, nil)
    }
    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage().reference(withPath: "object")
    do {
      let _ = try await ref.list(maxResults: 10)
    } catch {
      // All testing is in test block.
    }
  }

  func testDefaultListWithEmulator() async throws {
    let storage = self.storage()
    storage.useEmulator(withHost: "localhost", port: 8080)

    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let url = fetcher.request!.url!
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 8080)
        XCTAssertEqual(url.path, "/v0/b/bucket/o")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(queryItems.count, 3)
        for item in queryItems {
          switch item.name {
          case "prefix": XCTAssertEqual(item.value, "object/")
          case "delimiter": XCTAssertEqual(item.value, "/")
          case "maxResults": XCTAssertEqual(item.value, "123")
          default: XCTFail("Unexpected URLComponent Query Item")
          }
        }
        XCTAssertEqual(fetcher.request?.httpMethod, "GET")
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, "{}".data(using: .utf8), nil)
    }
    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage.reference(withPath: "object")
    let result = try await ref.list(maxResults: 123)
    XCTAssertEqual(result.items, [])
  }

  func testListWithPageSizeAndPageToken() async throws {
    let storage = self.storage()
    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let url = fetcher.request!.url!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "firebasestorage.googleapis.com")
        XCTAssertEqual(url.port, 443)
        XCTAssertEqual(url.path, "/v0/b/bucket/o")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(queryItems.count, 4)
        for item in queryItems {
          switch item.name {
          case "prefix": XCTAssertEqual(item.value, "object/")
          case "delimiter": XCTAssertEqual(item.value, "/")
          case "pageToken": XCTAssertEqual(item.value, "foo")
          case "maxResults": XCTAssertEqual(item.value, "42")
          default: XCTFail("Unexpected URLComponent Query Item")
          }
        }
        XCTAssertEqual(fetcher.request?.httpMethod, "GET")
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, nil, nil)
    }

    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage.reference(withPath: "object")
    do {
      let _ = try await ref.list(maxResults: 42, pageToken: "foo")
    } catch {
      // All testing is in test block.
    }
  }

  func testPercentEncodesPlusToken() async {
    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let url = fetcher.request!.url!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "firebasestorage.googleapis.com")
        XCTAssertEqual(url.port, 443)
        XCTAssertEqual(url.path, "/v0/b/bucket/o")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(queryItems.count, 3)
        for item in queryItems {
          switch item.name {
          case "prefix": XCTAssertEqual(item.value, "+foo/")
          case "delimiter": XCTAssertEqual(item.value, "/")
          case "maxResults": XCTAssertEqual(item.value, "97")
          default: XCTFail("Unexpected URLComponent Query Item")
          }
        }
        XCTAssertEqual(fetcher.request?.httpMethod, "GET")
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, nil, nil)
    }

    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let storage = storage()
    let ref = storage.reference(withPath: "+foo")
    do {
      let _ = try await ref.list(maxResults: 97)
    } catch {
      // All testing is in test block.
    }
  }

  func testListWithResponse() async throws {
    let jsonString = "{\n" +
      "  \"prefixes\": [\n" +
      "    \"object/prefixWithoutSlash\",\n" +
      "    \"object/prefixWithSlash/\"\n" +
      "  ],\n" +
      "  \"items\": [\n" +
      "    {\n" +
      "      \"name\": \"object/data1.dat\",\n" +
      "      \"bucket\": \"bucket.appspot.com\"\n" +
      "    },\n" +
      "    {\n" +
      "      \"name\": \"object/data2.dat\",\n" +
      "      \"bucket\": \"bucket.appspot.com\"\n" +
      "    },\n" +
      "  ],\n" +
      "  \"nextPageToken\": \"foo\"" +
      "}"
    let responseData = try XCTUnwrap(jsonString.data(using: .utf8))

    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, responseData, nil)
    }

    let storage = storage()
    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage.reference(withPath: "object")
    let result = try await ref.list(maxResults: 1000)
    XCTAssertEqual(result.items, [ref.child("data1.dat"), ref.child("data2.dat")])
    XCTAssertEqual(
      result.prefixes,
      [ref.child("prefixWithoutSlash"), ref.child("prefixWithSlash")]
    )
    XCTAssertEqual(result.pageToken, "foo")
  }

  func testListWithErrorResponse() async {
    let error = NSError(domain: "com.google.firebase.storage", code: 404)

    let testBlock = { (fetcher: GTMSessionFetcher,
                       response: GTMSessionFetcherTestResponse) in
        let httpResponse = HTTPURLResponse(url: (fetcher.request?.url)!,
                                           statusCode: 403,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, nil, error)
    }

    let storage = storage()
    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage.reference(withPath: "object")
    do {
      let _ = try await ref.list(maxResults: 1000)
    } catch {
      XCTAssertEqual((error as NSError).domain, "FIRStorageErrorDomain")
      XCTAssertEqual((error as NSError).code, StorageErrorCode.objectNotFound.rawValue)
    }
  }

  func testListAllReleasesCompletionAfterError() async throws {
    let firstPage = try XCTUnwrap("""
    {
      "items": [{"name": "object/data1.dat", "bucket": "bucket"}],
      "nextPageToken": "page2"
    }
    """.data(using: .utf8))
    let errorBlock = unauthorizedBlock()
    let testBlock: GTMSessionFetcherTestBlock = { fetcher, response in
      let url = fetcher.request!.url!
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      if queryItems?.contains(where: { $0.name == "pageToken" }) == true {
        // The second page fails.
        errorBlock(fetcher, response)
      } else {
        let httpResponse = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)
        response(httpResponse, firstPage, nil)
      }
    }
    await StorageFetcherService.shared.updateTestBlock(testBlock)
    let ref = storage().reference(withPath: "object")

    // Port note: listAll is async, so there's no completion to release;
    // what's left to check is that the second page's error is thrown.
    do {
      _ = try await ref.listAll()
      XCTFail("listAll succeeded")
    } catch {
      XCTAssertEqual((error as NSError).code, StorageErrorCode.unauthorized.rawValue)
    }
  }
}

/// Calls `onDeinit` when it is deallocated.
private final class DeallocationTracker {
  private let onDeinit: () -> Void

  init(onDeinit: @escaping () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }
}
