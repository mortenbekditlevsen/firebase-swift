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

// Upstream's test macros (FirebaseDatabase/Tests/Helpers/FTestHelpers.h).

@testable import FirebaseDatabase
import Foundation

func NODE(_ value: Any?) -> FNode {
  FSnapshotUtilities.nodeFrom(value)
}

func PATH(_ pathString: String) -> FPath {
  FPath(with: pathString)
}

/// A context provider without Auth or App Check tokens (upstream's tests use
/// FIRAuthInteropFake and FIRAppCheckFake for this).
struct FakeContextProvider: DatabaseConnectionContextProviderProtocol {
  func fetchContextForcingRefresh(_ forceRefresh: Bool) async throws
    -> DatabaseConnectionContext {
    DatabaseConnectionContext(authToken: nil, appCheckToken: nil)
  }

  func listenForAuthTokenChanges(_ listener: @escaping @DatabaseActor (String?) -> Void) {}

  func listenForAppCheckTokenChanges(_ listener: @escaping @DatabaseActor (String) -> Void) {}
}

enum FTestHelpers {
  static func defaultConfig() -> DatabaseConfig {
    configForName("default")
  }

  static func configForName(_ name: String) -> DatabaseConfig {
    DatabaseConfig(sessionIdentifier: name, googleAppID: "fake-app-id",
                   contextProvider: FakeContextProvider())
  }

  static func leafNodeOfSize(_ size: Int) -> FNode {
    let pattern = "abdefghijklmopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    // The pattern is ASCII, so characters are bytes.
    let string = String(repeating: pattern, count: size / pattern.count)
      + pattern.prefix(size % pattern.count)
    return NODE(string)
  }
}

/// So that dictionary literals get a type (upstream's are NSDictionaries).
func NODE(_ dictionary: [String: Any]) -> FNode {
  FSnapshotUtilities.nodeFrom(dictionary)
}
