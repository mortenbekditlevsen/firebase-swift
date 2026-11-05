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

// Port of upstream's FirebaseDatabase/Tests/Unit/FUtilitiesTest.m (13.1.1).

@testable import FirebaseDatabase
import XCTest

class FUtilitiesTest: XCTestCase {
  func testUrlWithSchema() {
    var parsedUrl = FUtilities.parseUrl("https://repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.host, "repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "repo")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, FPath.empty)

    parsedUrl = FUtilities.parseUrl("wss://repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.host, "repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "repo")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, FPath.empty)
  }

  func testUrlParsedWithoutSchema() {
    let parsedUrl = FUtilities.parseUrl("repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.host, "repo.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "repo")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, FPath.empty)
  }

  func testUrlParsedUsesSpaceInsteadOfPlus() {
    let parsedUrl = FUtilities.parseUrl("repo.firebaseio.com/+")
    XCTAssertEqual(parsedUrl.path, PATH("/ "))
  }

  func testUrlParsedWithSpecialCharacters() {
    let parsedUrl = FUtilities.parseUrl("repo.firebaseio.com/a%b&c@d/space: /non-ascii:ø")
    XCTAssertEqual(parsedUrl.path, PATH("/a%b&c@d/space: /non-ascii:ø"))
  }

  func testUrlParsedWithNamespace() {
    var parsedUrl = FUtilities.parseUrl("localhost/?ns=mrschmidt")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "mrschmidt")

    parsedUrl = FUtilities.parseUrl("127.0.0.1:9000/?ns=mrschmidt")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "mrschmidt")
  }

  func testUrlParsedWithSslDetection() {
    // Hosts with custom ports are considered non-secure
    var parsedUrl = FUtilities.parseUrl("repo.firebaseio.com:9000")
    XCTAssertFalse(parsedUrl.repoInfo.secure)

    // Hosts with omitted ports are considered secure
    parsedUrl = FUtilities.parseUrl("repo.firebaseio.com")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
  }

  func testUrlParsedWithPathPartOfHost() {
    let parsedUrl = FUtilities.parseUrl("https://sample.firebaseio.com/a")
    XCTAssertEqual(parsedUrl.repoInfo.host, "sample.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "sample")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, PATH("a"))
  }

  func testUrlParsedWithPathPartOfHost2() {
    let parsedUrl = FUtilities.parseUrl("https://sample.firebaseio.com/")
    XCTAssertEqual(parsedUrl.repoInfo.host, "sample.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "sample")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, PATH(""))
  }

  func testUrlParsedWithPathPartOfHost3() {
    let parsedUrl = FUtilities.parseUrl("https://sample.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.host, "sample.firebaseio.com")
    XCTAssertEqual(parsedUrl.repoInfo.namespace, "sample")
    XCTAssertTrue(parsedUrl.repoInfo.secure)
    XCTAssertEqual(parsedUrl.path, PATH(""))
  }

  func testDefaultCacheSizeIs10MB() {
    XCTAssertEqual(FTestHelpers.defaultConfig().persistenceCacheSizeBytes, 10 * 1024 * 1024)
    XCTAssertEqual(FTestHelpers.configForName("test-config").persistenceCacheSizeBytes,
                   10 * 1024 * 1024)
  }

  func testSettingCacheSizeToHighOrToLowThrows() throws {
    // Port note: the port stops the process where upstream raises an
    // exception, so only the valid size is tested.
    var config = FTestHelpers.configForName("config-tests-config")
    config.persistenceCacheSizeBytes = 5 * 1024 * 1024 // Works fine
    XCTAssertEqual(config.persistenceCacheSizeBytes, 5 * 1024 * 1024)
  }

  func testSystemClockMatchesCurrentTime() {
    let currentTime = Date().timeIntervalSince1970
    // Accuracy within 10ms
    XCTAssertEqual(currentTime, FSystemClock.clock.currentTime, accuracy: 0.010)
  }

  // This test is here for a lack of a better place to put it
  func testUserAgentString() async {
    let agent = await FPersistentConnection.userAgent
    let parts = agent.components(separatedBy: "/")
    XCTAssertEqual(parts.count, 5)
    XCTAssertEqual(parts[0], "Firebase")
    XCTAssertEqual(parts[1], kWebsocketProtocolVersion) // Wire protocol version
    XCTAssertEqual(parts[2], Database.buildVersion) // Build version
  }

  func testKeyComparison() {
    let order = [
      "-2147483648", "0", "1", "2", "10", "2147483647", // Treated as integers
      "-2147483649", "-2147483650", "-a", "2147483648", "21474836480", "2147483649",
      "a", // treated as strings
    ]
    for i in 0 ..< order.count {
      for j in (i + 1) ..< order.count {
        let first = order[i]
        let second = order[j]
        XCTAssertEqual(FUtilities.compareKey(first, second), .orderedAscending,
                       "Expected \(first) < \(second)")
        XCTAssertEqual(FUtilities.compareKey(first, first), .orderedSame,
                       "Expected \(first) == \(first)")
        XCTAssertEqual(FUtilities.compareKey(second, first), .orderedDescending,
                       "Expected \(second) > \(first)")
      }
    }
  }

  // Enforce a > b, b < a, a != b, because this is apparently something that happens
  // semi-regularly
  func testUnicodeKeyComparison() {
    XCTAssertEqual(FUtilities.compareKey("유주연", "윤규완오빠"), .orderedAscending)
    XCTAssertEqual(FUtilities.compareKey("윤규완오빠", "유주연"), .orderedDescending)
    XCTAssertNotEqual(FUtilities.compareKey("윤규완오빠", "유주연"), .orderedSame)
  }
}
