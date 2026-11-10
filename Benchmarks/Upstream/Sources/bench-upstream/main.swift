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

// The shared scenarios against upstream's Database. Upstream calls back on the
// main queue by default; `BENCH_CALLBACK_QUEUE=background` gives it a serial
// background queue instead.

import BenchmarkScenarios
import FirebaseCore
import FirebaseDatabase
import Foundation

struct UpstreamDriver: BenchmarkDriver {
  let target = "upstream"
  let backgroundQueue = ProcessInfo.processInfo.environment["BENCH_CALLBACK_QUEUE"] == "background"
  var variant: String { backgroundQueue ? "background-queue" : "main-queue" }

  func makeClient(name: String, persistence: Bool,
                  emulator: EmulatorDatabase) async throws -> any BenchmarkClient {
    let options = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
    options.projectID = EmulatorDatabase.projectID
    options.apiKey = "fake-api-key"
    options.databaseURL = EmulatorDatabase.databaseURL
    FirebaseApp.configure(name: name, options: options)
    guard let app = FirebaseApp.app(name: name) else { throw BenchmarkError("no app \(name)") }
    let database = Database.database(app: app, url: EmulatorDatabase.databaseURL)
    database.isPersistenceEnabled = persistence
    if backgroundQueue {
      database.callbackQueue = DispatchQueue(label: "bench.database.callbacks")
    }
    database.useEmulator(withHost: emulator.host, port: emulator.port)
    return UpstreamClient(app: app, database: database)
  }
}

final class UpstreamClient: BenchmarkClient, @unchecked Sendable {
  let app: FirebaseApp
  let database: Database

  init(app: FirebaseApp, database: Database) {
    self.app = app
    self.database = database
  }

  private func ref(_ path: String) -> DatabaseReference {
    database.reference(withPath: path)
  }

  func firstValue(at path: String) async throws -> Int {
    let ref = ref(path)
    return try await withCheckedThrowingContinuation { continuation in
      ref.observeSingleEvent(of: .value, with: { snapshot in
        continuation.resume(returning: Int(snapshot.childrenCount))
      }, withCancel: { error in
        continuation.resume(throwing: error)
      })
    }
  }

  func firstValueDecoded(at path: String) async throws -> (count: Int, decode: Duration) {
    let ref = ref(path)
    return try await withCheckedThrowingContinuation { continuation in
      ref.observeSingleEvent(of: .value, with: { snapshot in
        let start = ContinuousClock.now
        do {
          let items = try snapshot.data(as: [String: BenchItem].self)
          continuation.resume(returning: (items.count, ContinuousClock.now - start))
        } catch {
          continuation.resume(throwing: error)
        }
      }, withCancel: { error in
        continuation.resume(throwing: error)
      })
    }
  }

  func childAdded(at path: String, count: Int,
                  trigger: @escaping @Sendable () async throws -> Void) async throws {
    let ref = ref(path)
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let seen = NSLock()
    var counted = 0
    let handle = ref.observe(.childAdded) { _ in
      seen.lock()
      counted += 1
      let done = counted == count
      seen.unlock()
      if done { continuation.finish() }
    }
    defer { ref.removeObserver(withHandle: handle) }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await trigger() }
      for await _ in events {}
      try await group.waitForAll()
    }
  }

  private func write(_ ref: DatabaseReference, _ item: BenchItem) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      ref.child(item.id).setValue(item.firebaseValue) { error, _ in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  func writeSequentially(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    for item in items {
      try await write(ref, item)
    }
  }

  func writePipelined(at path: String, items: [BenchItem]) async throws {
    let ref = ref(path)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for item in items {
        group.addTask { try await self.write(ref, item) }
      }
      try await group.waitForAll()
    }
  }

  func concurrentIncrements(at path: String, count: Int) async throws -> Int {
    let ref = ref(path)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0 ..< count {
        group.addTask {
          try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.runTransactionBlock({ data in
              data.value = ((data.value as? NSNumber)?.intValue ?? 0) + 1
              return .success(withValue: data)
            }, andCompletionBlock: { error, _, _ in
              if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
          }
        }
      }
      try await group.waitForAll()
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
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      app.delete { _ in continuation.resume() }
    }
  }
}

await BenchmarkRunner.main(driver: UpstreamDriver())
