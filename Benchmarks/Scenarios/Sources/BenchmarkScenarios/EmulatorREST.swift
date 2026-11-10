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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The Realtime Database emulator, which `firebase emulators:exec` announces in
/// `FIREBASE_DATABASE_EMULATOR_HOST`.
public struct EmulatorDatabase: Sendable {
  public static let projectID = "demo-firebase-swift"
  /// The namespace `firebase.json`'s rules apply to.
  public static let namespace = "\(projectID)-default-rtdb"
  public static let databaseURL = "https://\(namespace).firebaseio.com"

  public let host: String
  public let port: Int

  public init() throws {
    guard let value = ProcessInfo.processInfo.environment["FIREBASE_DATABASE_EMULATOR_HOST"],
          let colon = value.lastIndex(of: ":"),
          let port = Int(value[value.index(after: colon)...]) else {
      throw BenchmarkError("FIREBASE_DATABASE_EMULATOR_HOST isn't set; run under " +
        "`firebase emulators:exec --only database` (see Benchmarks/run.sh)")
    }
    host = String(value[..<colon])
    self.port = port
  }

  /// Writes `json` at `path` over REST, as the owner (bypassing rules).
  public func put(_ path: String, json: Data) async throws {
    try await send("PUT", path, json)
  }

  /// Merges `json` into `path` over REST.
  public func patch(_ path: String, json: Data) async throws {
    try await send("PATCH", path, json)
  }

  public func delete(_ path: String) async throws {
    try await send("DELETE", path, nil)
  }

  private func send(_ method: String, _ path: String, _ body: Data?) async throws {
    let url = URL(string: "http://\(host):\(port)/\(path).json?ns=\(Self.namespace)")!
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status)
    else {
      throw BenchmarkError("\(method) \(path) failed: \(response)")
    }
  }
}

public struct BenchmarkError: Error, CustomStringConvertible {
  public let description: String
  public init(_ description: String) { self.description = description }
}
