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
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

/// Emulator addresses, from the environment variables `firebase emulators:exec` sets.
enum Emulators {
  static let projectID = "demo-firebase-swift"

  static let auth = address(from: "FIREBASE_AUTH_EMULATOR_HOST")
  static let database = address(from: "FIREBASE_DATABASE_EMULATOR_HOST")
  static let firestore = address(from: "FIRESTORE_EMULATOR_HOST")
  static let storage = address(from: "FIREBASE_STORAGE_EMULATOR_HOST")
  /// `emulators:exec` sets no variable for Functions, so ask the emulator hub.
  static let functions = address(from: "FUNCTIONS_EMULATOR_HOST") ?? hubAddress(of: "functions")

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

  /// Looks `emulator` up in the hub's `/emulators` listing, which maps each
  /// running emulator's name to its `host` and `port`.
  private static func hubAddress(of emulator: String) -> Address? {
    guard let hub = address(from: "FIREBASE_EMULATOR_HUB"),
          let url = URL(string: "http://\(hub.host):\(hub.port)/emulators") else { return nil }
    let listing = Locked<Data?>(nil)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: url) { data, _, _ in
      listing.withLock { $0 = data }
      done.signal()
    }.resume()
    guard done.wait(timeout: .now() + 10) == .success,
          let data = listing.withLock({ $0 }),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let info = json[emulator] as? [String: Any],
          let host = info["host"] as? String,
          let port = info["port"] as? Int else { return nil }
    return Address(host: host, port: port)
  }
}

/// A fresh app with Auth wired to the emulator, so tests don't share state.
/// Each service comes from its own factory, which points it at its emulator.
struct EmulatorApp {
  let app: FirebaseApp
  let auth: Auth

  /// - Parameter name: Apps with the same name share Auth's stored user,
  ///   so a second one acts like the app relaunching.
  init(name: String = "integration-\(UUID().uuidString)") throws {
    let authAddress = try #require(Emulators.auth)
    let options = FirebaseApp.Options(
      projectID: Emulators.projectID,
      googleAppID: "1:123:ios:123ab",
      apiKey: "fake-api-key",
      clientID: nil,
      storageBucket: "\(Emulators.projectID).appspot.com"
    )
    app = FirebaseApp(options: options, name: name)

    // Auth must exist before the other services: they pick up `app.auth`
    // when they're created.
    auth = Auth.auth(app: app)
    auth.useEmulator(withHost: authAddress.host, port: authAddress.port)
  }

  func firestore() throws -> Firestore {
    let address = try #require(Emulators.firestore)
    let db = Firestore.firestore(app: app)
    db.useEmulator(withHost: address.host, port: address.port)
    let settings = db.settings
    settings.isSSLEnabled = false
    settings.isPersistenceEnabled = false
    db.settings = settings
    return db
  }

  func database() throws -> Database {
    let address = try #require(Emulators.database)
    // The emulator serves any namespace; this one gets the rules from firebase.json.
    let database = Database.database(
      app: app, url: "https://\(Emulators.projectID)-default-rtdb.firebaseio.com"
    )
    database.useEmulator(withHost: address.host, port: address.port)
    return database
  }

  func storage() throws -> Storage {
    let address = try #require(Emulators.storage)
    let storage = Storage.storage(app: app)
    storage.useEmulator(withHost: address.host, port: address.port)
    return storage
  }

  func functions() throws -> Functions {
    let address = try #require(Emulators.functions)
    let functions = Functions.functions(app: app)
    functions.useEmulator(withHost: address.host, port: address.port)
    return functions
  }
}

/// An `EmulatorApp` with Firestore, and a collection only this fixture uses
/// (under the rules' open `public/` path).
struct EmulatorFixture {
  let app: FirebaseApp
  let auth: Auth
  let db: Firestore
  let collection: CollectionReference

  init() throws {
    let emulatorApp = try EmulatorApp()
    app = emulatorApp.app
    auth = emulatorApp.auth
    db = try emulatorApp.firestore()
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

/// A value shared with callbacks that run on other threads.
final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}
