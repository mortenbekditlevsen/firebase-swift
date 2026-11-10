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

import Foundation

/// What a scenario needs from a Realtime Database SDK. The port's and
/// upstream's benchmark executables each implement it with their own API.
public protocol BenchmarkClient: Sendable {
  /// Listens for the value at `path` and returns its number of children once
  /// the first value event arrives (the listener is then removed).
  func firstValue(at path: String) async throws -> Int

  /// As `firstValue(at:)`, then decodes the snapshot into `[String: BenchItem]`
  /// in the callback, as an app would. Returns the count and the decode time.
  func firstValueDecoded(at path: String) async throws -> (count: Int, decode: Duration)

  /// Listens for child-added events at `path`, calls `trigger` once the
  /// listener is registered, and returns after `count` events.
  func childAdded(at path: String, count: Int,
                  trigger: @escaping @Sendable () async throws -> Void) async throws

  /// Writes each item under `path`, waiting for each write's acknowledgement
  /// before the next.
  func writeSequentially(at path: String, items: [BenchItem]) async throws

  /// Starts all writes at once and waits for every acknowledgement.
  func writePipelined(at path: String, items: [BenchItem]) async throws

  /// Runs `count` concurrent transactions that each add one to the number at
  /// `path`, and returns the final value.
  func concurrentIncrements(at path: String, count: Int) async throws -> Int

  /// Keeps `path` synced (persistence scenarios).
  func keepSynced(at path: String) async

  /// Goes offline, so reads come from the local cache.
  func goOffline() async

  /// Shuts the client down (deletes its app).
  func close() async
}

public protocol BenchmarkDriver: Sendable {
  /// "port" or "upstream".
  var target: String { get }
  /// A variant of the target (e.g. "main-queue"); "default" if none.
  var variant: String { get }

  /// A new client on its own app named `name`, pointed at the emulator.
  func makeClient(name: String, persistence: Bool,
                  emulator: EmulatorDatabase) async throws -> any BenchmarkClient
}

extension BenchItem {
  /// The item as the Foundation value the SDKs' `setValue` takes.
  public var firebaseValue: [String: Any] {
    [
      "id": id, "name": name, "score": score, "rating": rating, "active": active,
      "tags": tags, "createdAt": createdAt, "latitude": latitude, "longitude": longitude,
      "note": note,
    ]
  }
}
