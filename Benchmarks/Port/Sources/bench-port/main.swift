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

// The shared scenarios against firebase-swift's Database.

import BenchmarkScenarios
import FirebaseCore
import FirebaseDatabase
import Foundation

struct PortDriver: BenchmarkDriver {
  let target = "port"
  /// The transport: BENCHMARK_DATABASE_TRANSPORT (nio, networkFramework or
  /// urlSession), or the default.
  let variant = ProcessInfo.processInfo.environment["BENCHMARK_DATABASE_TRANSPORT"] ?? "default"

  func makeClient(name: String, persistence: Bool,
                  emulator: EmulatorDatabase) async throws -> any BenchmarkClient {
    var options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
    options.projectID = EmulatorDatabase.projectID
    options.apiKey = "fake-api-key"
    options.databaseURL = EmulatorDatabase.databaseURL
    FirebaseApp.configure(name: name, options: options)
    guard let app = FirebaseApp.app(name: name) else { throw BenchmarkError("no app \(name)") }
    let database = Database.database(app: app, url: EmulatorDatabase.databaseURL)
    database.isPersistenceEnabled = persistence
    database.useEmulator(withHost: emulator.host, port: emulator.port)
    switch variant {
    case "nio": database.transport = NIODatabaseTransport()
    #if canImport(Darwin)
      case "networkFramework": database.transport = NIOTSDatabaseTransport()
      case "urlSession": database.transport = URLSessionDatabaseTransport()
    #endif
    default: break
    }
    return PortClient(app: app, database: database)
  }
}

final class PortClient: BenchmarkClient {
  let app: FirebaseApp
  let database: Database

  init(app: FirebaseApp, database: Database) {
    self.app = app
    self.database = database
  }

  private func ref(_ path: String) -> DatabaseReference {
    database.reference().child(path)
  }

  func firstValue(at path: String) async throws -> Int {
    Int(try await ref(path).firstValue().childrenCount)
  }

  func firstValueDecoded(at path: String) async throws -> (count: Int, decode: Duration) {
    let snapshot = try await ref(path).firstValue()
    let start = ContinuousClock.now
    let items = try snapshot.data(as: [String: BenchItem].self)
    return (items.count, ContinuousClock.now - start)
  }

  func childAdded(at path: String, count: Int,
                  trigger: @escaping @Sendable () async throws -> Void) async throws {
    // Children that exist when listening starts arrive as `.added` too, so
    // the count doesn't depend on which comes first.
    let ref = ref(path)
    try await withThrowingTaskGroup { group in
      group.addTask { try await trigger() }
      var seen = 0
      for try await _ in ref.childEvents([.added]) {
        seen += 1
        if seen == count { break }
      }
      try await group.waitForAll()
    }
  }

  func writeSequentially(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    for item in items {
      try await ref.child(item.id).setValueAndWait(item.firebaseValue)
    }
  }

  func writePipelined(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    try await withThrowingDiscardingTaskGroup { group in
      for item in items {
        group.addTask { try await ref.child(item.id).setValueAndWait(item.firebaseValue) }
      }
    }
  }

  func concurrentIncrements(at path: String, count: Int) async throws -> Int {
    let ref = ref(path)
    try await withThrowingDiscardingTaskGroup { group in
      for _ in 0 ..< count {
        group.addTask {
          try await ref.runTransaction { data in
            data.value = ((data.value as? NSNumber)?.intValue ?? 0) + 1
            return .success(withValue: data)
          }
        }
      }
    }
    let snapshot = try await ref.getData()
    return (snapshot.value as? NSNumber)?.intValue ?? 0
  }

  func keepSynced(at path: String) async {
    ref(path).keepSynced(true)
  }

  func goOffline() async {
    database.goOffline()
  }

  func close() async {
    _ = await app.delete()
  }
}

await BenchmarkRunner.main(driver: PortDriver())
