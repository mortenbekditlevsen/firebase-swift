// Copyright 2021 Google LLC
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

// Port note: a port of upstream's FIRAppCheckSettingsTests.m. Upstream mocks GULUserDefaults, the
// main bundle and the app; here the settings get their own UserDefaults suite and a bundle
// directory written by the test. `FirebaseApp.isDataCollectionDefaultEnabled` isn't ported and is
// true, so the fallback is true, and upstream's test for a deallocated app (fallback false) is
// left out: the settings don't hold the app.

@testable import FirebaseAppCheck
import XCTest

final class AppCheckSettingsTests: XCTestCase {
  private let appName = "FIRAppCheckSettingsTestsAppName"
  private var userDefaultKey: String!
  private var userDefaultsSuiteName: String!
  private var userDefaults: UserDefaults!
  private var bundleURL: URL!
  private var settings: AppCheckSettings!

  override func setUpWithError() throws {
    try super.setUpWithError()

    userDefaultKey = AppCheckSettings.userDefaultsKeyPrefix + appName
    userDefaultsSuiteName = "AppCheckSettingsTests.\(UUID().uuidString)"
    userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName))
    bundleURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppCheckSettingsTests-\(UUID().uuidString).bundle")
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
    settings = try makeSettings(infoPlistValue: nil)
  }

  override func tearDownWithError() throws {
    settings = nil
    userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
    userDefaults = nil
    try? FileManager.default.removeItem(at: bundleURL)

    try super.tearDownWithError()
  }

  func testIsTokenAutoRefreshEnabledWhenDidNotExplicitlySet() {
    // Port note: `FirebaseApp.isDataCollectionDefaultEnabled` is true here.
    XCTAssertTrue(settings.isTokenAutoRefreshEnabled)
    XCTAssertNil(userDefaults.object(forKey: userDefaultKey))
  }

  func testIsTokenAutoRefreshEnabledWhenSetThisAppRun() {
    settings.isTokenAutoRefreshEnabled = false

    XCTAssertFalse(settings.isTokenAutoRefreshEnabled)
    XCTAssertEqual(userDefaults.object(forKey: userDefaultKey) as? Bool, false)

    // The value set this run is used, not the saved one.
    userDefaults.set(true, forKey: userDefaultKey)
    XCTAssertFalse(settings.isTokenAutoRefreshEnabled)
  }

  func testIsTokenAutoRefreshEnabledWhenSetDuringPreviousLaunch() throws {
    userDefaults.set(false, forKey: userDefaultKey)
    // The Info.plist value isn't used when there's a saved one.
    settings = try makeSettings(infoPlistValue: true)

    XCTAssertFalse(settings.isTokenAutoRefreshEnabled)
  }

  func testIsTokenAutoRefreshEnabledWhenSetInInfoPlist() throws {
    settings = try makeSettings(infoPlistValue: false)

    XCTAssertFalse(settings.isTokenAutoRefreshEnabled)
  }

  func testSetIsTokenAutoRefreshEnabled() {
    settings.isTokenAutoRefreshEnabled = true
    XCTAssertTrue(settings.isTokenAutoRefreshEnabled)
    XCTAssertEqual(userDefaults.object(forKey: userDefaultKey) as? Bool, true)

    settings.isTokenAutoRefreshEnabled = false
    XCTAssertFalse(settings.isTokenAutoRefreshEnabled)
    XCTAssertEqual(userDefaults.object(forKey: userDefaultKey) as? Bool, false)
  }

  // MARK: - Helpers

  /// Settings reading a bundle whose Info.plist has `infoPlistValue`, if it's set.
  private func makeSettings(infoPlistValue: Bool?) throws -> AppCheckSettings {
    var infoDictionary: [String: Any] = ["CFBundleIdentifier": "com.google.AppCheckSettingsTests"]
    infoDictionary[AppCheckSettings.infoPlistKey] = infoPlistValue
    let data = try PropertyListSerialization.data(fromPropertyList: infoDictionary,
                                                  format: .xml, options: 0)
    // A new directory each time: bundles are cached by path.
    let url = bundleURL.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try data.write(to: url.appendingPathComponent("Info.plist"))
    let bundle = try XCTUnwrap(Bundle(url: url))
    return AppCheckSettings(appName: appName, userDefaults: userDefaults, mainBundle: bundle)
  }
}
