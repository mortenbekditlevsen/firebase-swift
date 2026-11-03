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
import Testing

/// Each SDK's instances for an app, and what deleting the app does to them.
@Suite(.enabled(if: Emulators.firestore != nil && Emulators.auth != nil, "Needs the Firestore and Auth emulators"), .timeLimit(.minutes(1)))
struct AppIntegrationTests {
  @Test func eachSDKHasOneInstancePerApp() throws {
    let fixture = try EmulatorApp()
    #expect(Auth.auth(app: fixture.app) === fixture.auth)
    #expect(try fixture.database() === fixture.database())
    #expect(try fixture.firestore() === fixture.firestore())
    #expect(try fixture.storage() === fixture.storage())
    #expect(try fixture.functions() === fixture.functions())

    let other = try EmulatorApp()
    #expect(other.auth !== fixture.auth)
    #expect(try other.firestore() !== fixture.firestore())
  }

  @Test func deletingAnAppForgetsItsSignedInUser() async throws {
    let name = "deleted-\(UUID().uuidString)"
    let first = try EmulatorApp(name: name, configured: true)
    try await first.auth.signInAnonymously()
    #expect(await first.app.delete())
    #expect(FirebaseApp.app(name: name) == nil)
    #expect(await first.app.delete() == false)

    // As upstream, the stored user is removed, so the next app of this name starts signed out.
    let second = try EmulatorApp(name: name, configured: true)
    #expect(second.app != first.app)
    #expect(second.auth !== first.auth)
    #expect(second.auth.currentUser == nil)
    #expect(await second.app.delete())
  }

  @Test func deletingAnAppTerminatesItsFirestore() async throws {
    let name = "deleted-\(UUID().uuidString)"
    let first = try EmulatorApp(name: name, configured: true)
    let db = try first.firestore(cacheSettings: PersistentCacheSettings())
    let doc = db.collection("public").document(UUID().uuidString)
      .collection("items").document("kept")
    try await doc.setData(["n": 1])
    #expect(await first.app.delete())

    // A new app of the same name gets a new instance, which can only open the cache once the
    // old one has released it.
    let second = try EmulatorApp(name: name, configured: true)
    let secondDB = try second.firestore(cacheSettings: PersistentCacheSettings())
    #expect(secondDB !== db)
    let cached = try await secondDB.document(doc.path).getDocument(source: .cache)
    #expect(cached.get("n") as? Int == 1)

    #expect(await second.app.delete())
    try await secondDB.clearPersistence()
  }
}
