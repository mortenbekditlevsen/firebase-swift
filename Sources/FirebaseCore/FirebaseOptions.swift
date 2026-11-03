// Copyright 2017 Google LLC
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

/// The options used to configure a `FirebaseApp`: which Firebase project and app it talks to.
///
/// Unlike upstream's class, this is a value type, so changing a copy (such as
/// `FirebaseApp.options`) never changes the options an app was configured with.
public struct FirebaseOptions: Hashable, Sendable {
  /// The environment variable `defaultOptions()` reads first: either the options themselves, as
  /// JSON, or the path of a file in any format `init(contentsOfFile:)` reads.
  public static let environmentVariable = "FIREBASE_OPTIONS"

  /// The options for the app, from (in this order):
  ///
  /// 1. The `FIREBASE_OPTIONS` environment variable: either JSON in one of the formats
  ///    `init(contentsOfFile:)` reads, or the path of such a file.
  /// 2. `GoogleService-Info.plist` in the main bundle, as upstream.
  ///
  /// Returns nil if neither is there, or if what's there isn't valid.
  public static func defaultOptions() -> FirebaseOptions? {
    if let value = ProcessInfo.processInfo.environment[environmentVariable] {
      if value.first == "{" {
        return FirebaseOptions(fileContents: Data(value.utf8))
      }
      return FirebaseOptions(contentsOfFile: value)
    }
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      return nil
    }
    return FirebaseOptions(contentsOfFile: path)
  }

  /// The API key that identifies the app to Google servers.
  public var apiKey: String?

  /// The bundle ID for the application. Defaults to the main bundle's identifier, and to an empty
  /// string where there is none.
  public var bundleID: String

  /// The OAuth2 client ID for Apple applications, used to authenticate Google users, for example
  /// with Google Sign-In.
  public var clientID: String?

  /// The Project Number from the Google Developer's console, for example "012345678901", used to
  /// configure Firebase Cloud Messaging.
  public var gcmSenderID: String

  /// The Project ID from the Firebase console, for example "abc-xyz-123".
  public var projectID: String?

  /// The Google App ID that is used to uniquely identify an instance of an app.
  public var googleAppID: String

  /// The realtime database root URL, for example "http://abc-xyz-123.firebaseio.com".
  public var databaseURL: String?

  /// The Google Cloud Storage bucket name, for example "abc-xyz-123.storage.firebase.com".
  public var storageBucket: String?

  /// The App Group identifier to share data between the application and the application
  /// extensions. The App Group must be configured in the application and on the Apple Developer
  /// Portal. Default value `nil`.
  public var appGroupID: String?

  /// Creates options with the given Google App ID and GCM sender ID; set the other properties
  /// before configuring an app with them.
  public init(googleAppID: String, gcmSenderID: String) {
    self.googleAppID = googleAppID
    self.gcmSenderID = gcmSenderID
    bundleID = Bundle.main.bundleIdentifier ?? ""
  }

  /// Reads the options from a file that the Firebase console provides, in one of these formats:
  ///
  /// - `GoogleService-Info.plist`, from an Apple app, as upstream.
  /// - `google-services.json`, from an Android app. When it holds several apps, the one whose
  ///   package name is the main bundle's identifier, or else the first.
  /// - The `firebaseConfig` object from a web app, as JSON (`apiKey`, `appId`, `projectId`, …).
  ///   Apps on platforms the console doesn't list, such as Linux, can register as web apps.
  ///
  /// Returns nil if the file can't be read, isn't in one of these formats, or has no app ID.
  public init?(contentsOfFile path: String) {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    self.init(fileContents: data)
  }

  init?(fileContents data: Data) {
    let isJSON = data.first(where: { !" \t\r\n".utf8.contains($0) }) == UInt8(ascii: "{")
    if isJSON {
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
      }
      if json["project_info"] != nil {
        self.init(googleServicesJSON: json)
      } else {
        self.init(webConfig: json)
      }
    } else {
      guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any] else {
        return nil
      }
      self.init(serviceInfo: plist)
    }
  }

  /// From `GoogleService-Info.plist`.
  private init?(serviceInfo plist: [String: Any]) {
    guard let googleAppID = plist["GOOGLE_APP_ID"] as? String else { return nil }
    self.init(googleAppID: googleAppID, gcmSenderID: plist["GCM_SENDER_ID"] as? String ?? "")
    apiKey = plist["API_KEY"] as? String
    clientID = plist["CLIENT_ID"] as? String
    projectID = plist["PROJECT_ID"] as? String
    databaseURL = plist["DATABASE_URL"] as? String
    storageBucket = plist["STORAGE_BUCKET"] as? String
    if let bundleID = plist["BUNDLE_ID"] as? String {
      self.bundleID = bundleID
    }
  }

  /// From `google-services.json`.
  private init?(googleServicesJSON json: [String: Any]) {
    let project = json["project_info"] as? [String: Any] ?? [:]
    let clients = json["client"] as? [[String: Any]] ?? []
    func packageName(_ client: [String: Any]) -> String? {
      let info = client["client_info"] as? [String: Any]
      let android = info?["android_client_info"] as? [String: Any]
      return android?["package_name"] as? String
    }
    let bundleIdentifier = Bundle.main.bundleIdentifier
    guard let client = clients.first(where: { packageName($0) == bundleIdentifier })
      ?? clients.first,
      let info = client["client_info"] as? [String: Any],
      let googleAppID = info["mobilesdk_app_id"] as? String else {
      return nil
    }
    self.init(googleAppID: googleAppID, gcmSenderID: project["project_number"] as? String ?? "")
    let apiKeys = client["api_key"] as? [[String: Any]]
    apiKey = apiKeys?.first?["current_key"] as? String
    projectID = project["project_id"] as? String
    databaseURL = project["firebase_url"] as? String
    storageBucket = project["storage_bucket"] as? String
    if let packageName = packageName(client) {
      bundleID = packageName
    }
  }

  /// From a web app's `firebaseConfig`.
  private init?(webConfig json: [String: Any]) {
    guard let googleAppID = json["appId"] as? String else { return nil }
    self.init(googleAppID: googleAppID, gcmSenderID: json["messagingSenderId"] as? String ?? "")
    apiKey = json["apiKey"] as? String
    projectID = json["projectId"] as? String
    databaseURL = json["databaseURL"] as? String
    storageBucket = json["storageBucket"] as? String
  }
}
