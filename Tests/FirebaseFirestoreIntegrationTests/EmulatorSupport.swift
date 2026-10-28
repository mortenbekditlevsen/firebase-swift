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

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing

/// Emulator addresses, from the environment variables `firebase emulators:exec` sets.
enum Emulators {
  static let firestore = address(from: "FIRESTORE_EMULATOR_HOST")
  static let auth = address(from: "FIREBASE_AUTH_EMULATOR_HOST")

  static var available: Bool { firestore != nil && auth != nil }

  struct Address {
    let host: String
    let port: Int
  }

  private static func address(from variable: String) -> Address? {
    guard let value = ProcessInfo.processInfo.environment[variable],
          let colon = value.lastIndex(of: ":"),
          let port = Int(value[value.index(after: colon)...]) else { return nil }
    return Address(host: String(value[..<colon]), port: port)
  }
}

/// A fresh app wired to the emulators, so tests don't share Firestore or Auth state.
struct EmulatorFixture {
  let app: FirebaseApp
  let auth: Auth
  let db: Firestore
  /// A collection only this fixture uses, under the rules' open `public/` path.
  let collection: CollectionReference

  init() throws {
    let firestoreAddress = try #require(Emulators.firestore)
    let authAddress = try #require(Emulators.auth)
    let options = FirebaseApp.Options(
      projectID: "demo-firebase-swift",
      googleAppID: "1:123:ios:123ab",
      apiKey: "fake-api-key",
      clientID: nil,
      storageBucket: nil
    )
    app = FirebaseApp(options: options, name: "integration-\(UUID().uuidString)")

    // Auth must exist first: Firestore picks up `app.auth` when it's created.
    auth = Auth.auth(app: app)
    auth.useEmulator(withHost: authAddress.host, port: authAddress.port)

    db = Firestore.firestore(app: app)
    db.useEmulator(withHost: firestoreAddress.host, port: firestoreAddress.port)
    let settings = db.settings
    settings.isSSLEnabled = false
    settings.isPersistenceEnabled = false
    db.settings = settings

    collection = db.collection("public").document(UUID().uuidString).collection("items")
  }
}

struct Timeout: Error {}

/// Polls `condition` until it holds, for things that settle asynchronously.
func eventually(
  timeout: Duration = .seconds(10),
  _ condition: () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while try await !condition() {
    guard ContinuousClock.now < deadline else { throw Timeout() }
    try await Task.sleep(for: .milliseconds(50))
  }
}
