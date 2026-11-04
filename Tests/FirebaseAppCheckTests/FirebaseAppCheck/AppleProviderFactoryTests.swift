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

// Port note: ports of upstream's FIRDeviceCheckProviderFactoryTests.m and
// AppAttestProviderFactoryTests.swift. DeviceCheck and App Attest are Apple-only.

#if canImport(DeviceCheck)

  @testable import FirebaseAppCheck
  import FirebaseCore
  import XCTest

  final class DeviceCheckProviderFactoryTests: XCTestCase {
    func testCreateProviderWithApp() throws {
      let app = FirebaseApp(options: testOptions(), name: "testInitWithValidApp")

      let factory = DeviceCheckProviderFactory()

      let createdProvider = try XCTUnwrap(factory.createProvider(with: app))
      XCTAssertTrue(createdProvider is DeviceCheckProvider)
    }
  }

  final class AppAttestProviderFactoryTests: XCTestCase {
    func testCreateProviderWithApp() throws {
      // Port note: App Attest stores its artifact in the app's keychain.
      AppCheck.setAppCheckProviderFactory(nil, keychain: AppCheckCoreKeychainStorageFake())
      let app = FirebaseApp(options: testOptions(), name: "test_app_name")

      let factory = AppAttestProviderFactory()

      let provider = try XCTUnwrap(factory.createProvider(with: app))
      XCTAssertTrue(provider is AppAttestProvider)
    }
  }

  private func testOptions() -> FirebaseOptions {
    var options = FirebaseOptions(googleAppID: "app_id", gcmSenderID: "sender_id")
    options.apiKey = "api_key"
    options.projectID = "project_id"
    return options
  }

#endif // canImport(DeviceCheck)
