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
import FirebaseFirestore
import Foundation
import Testing

/// Uses the rules in Tests/Emulator/firestore.rules: only the signed-in user
/// may read or write `users/{uid}`. That makes the Auth token Firestore sends,
/// and which user it belongs to, visible to the test.
@Suite(.enabled(if: Emulators.firestore != nil && Emulators.auth != nil, "Needs the Firestore and Auth emulators"), .timeLimit(.minutes(1)))
struct FirestoreAuthIntegrationTests {
  @Test func unauthenticatedWritesToProtectedPathsFail() async throws {
    let fixture = try EmulatorFixture()
    await #expect(throws: (any Error).self) {
      try await fixture.db.document("users/nobody/notes/n").setData(["x": Int64(1)])
    }
  }

  @Test func rulesSeeTheSignedInUser() async throws {
    let fixture = try EmulatorFixture()
    let uid = try await fixture.auth.signInAnonymously().user.uid

    let mine = fixture.db.document("users/\(uid)/notes/n")
    try await mine.setData(["text": "hello"])
    #expect(try await mine.getDocument(source: .server).get("text") as? String == "hello")

    await #expect(throws: (any Error).self) {
      try await fixture.db.document("users/someone-else/notes/n").setData(["x": Int64(1)])
    }
  }

  @Test func signingOutRevokesAccess() async throws {
    let fixture = try EmulatorFixture()
    let uid = try await fixture.auth.signInAnonymously().user.uid
    let mine = fixture.db.document("users/\(uid)/notes/n")
    try await mine.setData(["text": "hello"])

    try fixture.auth.signOut()

    // Firestore learns about the sign-out asynchronously, via Auth's internal
    // state notification; then the server starts rejecting reads.
    try await eventually {
      do {
        _ = try await mine.getDocument(source: .server)
        return false
      } catch {
        return true
      }
    }
  }

  @Test func switchingUsersSwitchesAccess() async throws {
    let fixture = try EmulatorFixture()
    let first = try await fixture.auth.signInAnonymously().user.uid
    let firstDoc = fixture.db.document("users/\(first)/notes/n")
    try await firstDoc.setData(["owner": first])

    try fixture.auth.signOut()
    let second = try await fixture.auth.signInAnonymously().user.uid
    #expect(first != second)

    let secondDoc = fixture.db.document("users/\(second)/notes/n")
    try await eventually {
      do {
        try await secondDoc.setData(["owner": second])
        return true
      } catch {
        return false
      }
    }
    // The first user's data is no longer readable.
    await #expect(throws: (any Error).self) {
      _ = try await firstDoc.getDocument(source: .server)
    }
  }
}
