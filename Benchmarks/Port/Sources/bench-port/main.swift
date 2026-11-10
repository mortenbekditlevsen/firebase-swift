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
import Synchronization

struct PortDriver: BenchmarkDriver {
  let target = "port"
  let variant = "default"

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
    let ref = ref(path)
    return try await withCheckedThrowingContinuation { continuation in
      ref.observeSingleEventOfType(.value, withBlock: { snapshot in
        continuation.resume(returning: Int(snapshot.childrenCount))
      }, withCancelBlock: { error in
        continuation.resume(throwing: error)
      })
    }
  }

  func firstValueDecoded(at path: String) async throws -> (count: Int, decode: Duration) {
    let ref = ref(path)
    return try await withCheckedThrowingContinuation { continuation in
      ref.observeSingleEventOfType(.value, withBlock: { snapshot in
        let start = ContinuousClock.now
        do {
          let items = try snapshot.data(as: [String: BenchItem].self)
          continuation.resume(returning: (items.count, ContinuousClock.now - start))
        } catch {
          continuation.resume(throwing: error)
        }
      }, withCancelBlock: { error in
        continuation.resume(throwing: error)
      })
    }
  }

  func childAdded(at path: String, count: Int,
                  trigger: @escaping @Sendable () async throws -> Void) async throws {
    let ref = ref(path)
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let seen = Mutex(0)
    let handle = ref.observeEventType(.childAdded) { _ in
      if seen.withLock({ $0 += 1; return $0 }) == count {
        continuation.finish()
      }
    }
    defer { ref.removeObserverWithHandle(handle) }
    try await withThrowingTaskGroup { group in
      group.addTask { try await trigger() }
      for await _ in events {}
      try await group.waitForAll()
    }
  }

  func writeSequentially(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    for item in items {
      _ = try await ref.child(item.id).setValue(item.firebaseValue)
    }
  }

  func writePipelined(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    try await withThrowingDiscardingTaskGroup { group in
      for item in items {
        group.addTask { _ = try await ref.child(item.id).setValue(item.firebaseValue) }
      }
    }
  }

  func concurrentIncrements(at path: String, count: Int) async throws -> Int {
    let ref = ref(path)
    try await withThrowingDiscardingTaskGroup { group in
      for _ in 0 ..< count {
        group.addTask {
          _ = try await ref.runTransactionBlock { data in
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
