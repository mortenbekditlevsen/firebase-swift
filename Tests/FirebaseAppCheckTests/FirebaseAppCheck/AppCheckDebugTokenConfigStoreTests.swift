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

// Port note: a port of upstream's FIRAppCheckDebugTokenConfigStoreTests.m (13.2.0). Upstream runs
// them in a Simulator only; here they read a config store under a temporary "host home" on every
// platform. The error classification tests are covered by the file cases.

@testable import FirebaseAppCheck
import XCTest

private let kAppID = "1:123:ios:abc"

final class AppCheckDebugTokenConfigStoreTests: XCTestCase {
  private var hostHome: URL!

  override func setUpWithError() throws {
    hostHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: hostHome, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: hostHome)
  }

  private var configStoreURL: URL {
    hostHome.appendingPathComponent(AppCheckDebugTokenConfigStore.relativePath)
  }

  private func writeConfigStore(_ contents: String) throws {
    try FileManager.default.createDirectory(at: configStoreURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: configStoreURL)
  }

  private func debugToken(_ appID: String = kAppID) -> String? {
    AppCheckDebugTokenConfigStore.debugToken(forGoogleAppID: appID, hostHome: hostHome.path)
  }

  func testRelativePath() {
    XCTAssertEqual(AppCheckDebugTokenConfigStore.relativePath,
                   ".config/configstore/firebase-appcheck.json")
  }

  func testDebugTokenForAppInConfigStore() throws {
    try writeConfigStore(#"{"tokens": {"\#(kAppID)": "token", "other": "other-token"}}"#)
    XCTAssertEqual(debugToken(), "token")
  }

  func testDebugTokenForAppMissingFromConfigStore() throws {
    try writeConfigStore(#"{"tokens": {"other": "other-token"}}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenConfigStoreFileMissing() {
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenConfigStoreMalformed() throws {
    try writeConfigStore("{not json")
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenTokensNotADictionary() throws {
    try writeConfigStore(#"{"tokens": ["token"]}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenTokensKeyMissing() throws {
    try writeConfigStore(#"{"other": {}}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenConfigStoreIsEmptyObject() throws {
    try writeConfigStore("{}")
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenTokenNotAString() throws {
    try writeConfigStore(#"{"tokens": {"\#(kAppID)": 42}}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenTokenEmpty() throws {
    try writeConfigStore(#"{"tokens": {"\#(kAppID)": ""}}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenTokenIsNull() throws {
    try writeConfigStore(#"{"tokens": {"\#(kAppID)": null}}"#)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenGoogleAppIDEmpty() throws {
    try writeConfigStore(#"{"tokens": {"": "token"}}"#)
    XCTAssertNil(debugToken(""))
  }

  func testDebugTokenWhenTopLevelJSONIsAnArray() throws {
    try writeConfigStore("[]")
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenSimulatorHostHomeHasTrailingSlash() throws {
    try writeConfigStore(#"{"tokens": {"\#(kAppID)": "token"}}"#)
    XCTAssertEqual(AppCheckDebugTokenConfigStore.debugToken(forGoogleAppID: kAppID,
                                                            hostHome: hostHome.path + "/"),
                   "token")
  }

  func testDebugTokenWhenConfigStorePathIsADirectory() throws {
    try FileManager.default.createDirectory(at: configStoreURL, withIntermediateDirectories: true)
    XCTAssertNil(debugToken())
  }

  func testDebugTokenWhenConfigStoreParentIsAFile() throws {
    try Data().write(to: hostHome.appendingPathComponent(".config"))
    XCTAssertNil(debugToken())
  }

  #if !targetEnvironment(simulator)
    func testDebugTokenIsNilOutsideSimulator() throws {
      try writeConfigStore(#"{"tokens": {"\#(kAppID)": "token"}}"#)
      XCTAssertNil(AppCheckDebugTokenConfigStore.debugToken(
        forGoogleAppID: kAppID, environment: ["SIMULATOR_HOST_HOME": hostHome.path]
      ))
    }
  #endif
}
