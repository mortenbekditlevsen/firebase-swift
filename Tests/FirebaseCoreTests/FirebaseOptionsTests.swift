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

import FirebaseCore
import Foundation
import Testing

/// Reading options from the files the Firebase console provides.
@Suite(.serialized)
struct FirebaseOptionsTests {
  @Test func readsGoogleServiceInfoPlist() throws {
    let plist: [String: Any] = [
      "API_KEY": "AIzaSy-plist",
      "BUNDLE_ID": "com.example.app",
      "CLIENT_ID": "123-abc.apps.googleusercontent.com",
      "GCM_SENDER_ID": "123",
      "GOOGLE_APP_ID": "1:123:ios:abc",
      "PROJECT_ID": "example",
      "DATABASE_URL": "https://example.firebaseio.com",
      "STORAGE_BUCKET": "example.appspot.com",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml,
                                                   options: 0)
    let options = try #require(FirebaseOptions(contentsOfFile: write(data)))
    var expected = FirebaseOptions(googleAppID: "1:123:ios:abc", gcmSenderID: "123")
    expected.apiKey = "AIzaSy-plist"
    expected.bundleID = "com.example.app"
    expected.clientID = "123-abc.apps.googleusercontent.com"
    expected.projectID = "example"
    expected.databaseURL = "https://example.firebaseio.com"
    expected.storageBucket = "example.appspot.com"
    #expect(options == expected)
  }

  @Test func readsGoogleServicesJSON() throws {
    let json = """
    {
      "project_info": {
        "project_number": "456",
        "firebase_url": "https://example.firebaseio.com",
        "project_id": "example",
        "storage_bucket": "example.appspot.com"
      },
      "client": [
        {
          "client_info": {
            "mobilesdk_app_id": "1:456:android:first",
            "android_client_info": { "package_name": "com.example.first" }
          },
          "api_key": [{ "current_key": "AIzaSy-first" }]
        },
        {
          "client_info": {
            "mobilesdk_app_id": "1:456:android:second",
            "android_client_info": { "package_name": "com.example.second" }
          },
          "api_key": [{ "current_key": "AIzaSy-second" }]
        }
      ],
      "configuration_version": "1"
    }
    """
    // The test runner's bundle identifier matches neither app, so the first is used.
    let options = try #require(FirebaseOptions(contentsOfFile: write(Data(json.utf8))))
    var expected = FirebaseOptions(googleAppID: "1:456:android:first", gcmSenderID: "456")
    expected.apiKey = "AIzaSy-first"
    expected.bundleID = "com.example.first"
    expected.projectID = "example"
    expected.databaseURL = "https://example.firebaseio.com"
    expected.storageBucket = "example.appspot.com"
    #expect(options == expected)
  }

  @Test func readsAWebAppConfig() throws {
    let json = """
    {
      "apiKey": "AIzaSy-web",
      "authDomain": "example.firebaseapp.com",
      "databaseURL": "https://example.firebaseio.com",
      "projectId": "example",
      "storageBucket": "example.appspot.com",
      "messagingSenderId": "789",
      "appId": "1:789:web:abc",
      "measurementId": "G-ABC"
    }
    """
    let options = try #require(FirebaseOptions(contentsOfFile: write(Data(json.utf8))))
    var expected = FirebaseOptions(googleAppID: "1:789:web:abc", gcmSenderID: "789")
    expected.apiKey = "AIzaSy-web"
    expected.projectID = "example"
    expected.databaseURL = "https://example.firebaseio.com"
    expected.storageBucket = "example.appspot.com"
    #expect(options == expected)
  }

  @Test func rejectsFilesWithoutAnAppID() throws {
    #expect(FirebaseOptions(contentsOfFile: "/nonexistent/GoogleService-Info.plist") == nil)
    #expect(FirebaseOptions(contentsOfFile: try write(Data("not options".utf8))) == nil)
    #expect(FirebaseOptions(contentsOfFile: try write(Data(#"{"projectId": "x"}"#.utf8))) == nil)
    #expect(FirebaseOptions(contentsOfFile: try write(Data(#"{"project_info": {}}"#.utf8)))
      == nil)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["PROJECT_ID": "x"],
                                                    format: .xml, options: 0)
    #expect(FirebaseOptions(contentsOfFile: try write(plist)) == nil)
  }

  @Test func defaultOptionsComeFromTheEnvironment() throws {
    let json = #"{"appId": "1:1:web:env", "apiKey": "key", "projectId": "from-env"}"#
    defer { unsetenv(FirebaseOptions.environmentVariable) }

    setenv(FirebaseOptions.environmentVariable, json, 1)
    #expect(FirebaseOptions.defaultOptions()?.projectID == "from-env")

    // Or from a file it names.
    setenv(FirebaseOptions.environmentVariable, try write(Data(json.utf8)), 1)
    #expect(FirebaseOptions.defaultOptions()?.googleAppID == "1:1:web:env")

    setenv(FirebaseOptions.environmentVariable, "{ not json", 1)
    #expect(FirebaseOptions.defaultOptions() == nil)
  }

  private func write(_ data: Data) throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("options-\(UUID().uuidString)")
    try data.write(to: url)
    return url.path
  }
}
