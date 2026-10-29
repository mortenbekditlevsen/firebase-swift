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
import Foundation
import Testing

@Suite(.enabled(if: Emulators.auth != nil, "Needs the Auth emulator"), .timeLimit(.minutes(1)))
struct AuthIntegrationTests {
  private let password = "correct-horse-battery-staple"

  /// A unique address, since every test shares the emulator's user store.
  private func newEmail() -> String {
    "user-\(UUID().uuidString.lowercased())@example.com"
  }

  @Test func createsAndSignsInWithEmailAndPassword() async throws {
    let auth = try EmulatorApp().auth
    let email = newEmail()
    let created = try await auth.createUser(withEmail: email, password: password).user
    #expect(auth.currentUser?.uid == created.uid)
    #expect(created.email == email)
    #expect(!created.isAnonymous)

    try auth.signOut()
    #expect(auth.currentUser == nil)

    let signedIn = try await auth.signIn(withEmail: email, password: password).user
    #expect(signedIn.uid == created.uid)
  }

  @Test func creatingADuplicateAccountFails() async throws {
    let auth = try EmulatorApp().auth
    let email = newEmail()
    _ = try await auth.createUser(withEmail: email, password: password)

    let error = await #expect(throws: NSError.self) {
      try await auth.createUser(withEmail: email, password: password)
    }
    #expect(error?.domain == AuthErrors.domain)
    #expect(error?.code == AuthErrorCode.emailAlreadyInUse.rawValue)
  }

  @Test func signingInWithAWrongPasswordFails() async throws {
    let auth = try EmulatorApp().auth
    let email = newEmail()
    _ = try await auth.createUser(withEmail: email, password: password)
    try auth.signOut()

    let error = await #expect(throws: NSError.self) {
      try await auth.signIn(withEmail: email, password: "wrong-password")
    }
    // Projects with email enumeration protection report invalidCredential instead.
    let expected = [AuthErrorCode.wrongPassword, .invalidCredential].map(\.rawValue)
    #expect(expected.contains(error?.code ?? 0))
    #expect(auth.currentUser == nil)
  }

  @Test func anonymousUsersGetIDTokens() async throws {
    let auth = try EmulatorApp().auth
    let user = try await auth.signInAnonymously().user
    #expect(user.isAnonymous)

    let token = try #require(try await user.getIDToken())
    #expect(!token.isEmpty)
    // What Firestore and Database ask for.
    #expect(try await auth.getToken(forcingRefresh: false) == token)
    #expect(auth.getUserID() == user.uid)

    let refreshed = try #require(try await user.getIDToken(forcingRefresh: true))
    #expect(!refreshed.isEmpty)
  }

  @Test func linkingAnEmailCredentialUpgradesAnAnonymousUser() async throws {
    let auth = try EmulatorApp().auth
    let anonymous = try await auth.signInAnonymously().user
    let email = newEmail()

    let credential = EmailAuthProvider.credential(withEmail: email, password: password)
    let linked = try await anonymous.link(with: credential).user

    #expect(linked.uid == anonymous.uid)
    #expect(!linked.isAnonymous)
    #expect(linked.email == email)
  }

  @Test func profileChangesAreSaved() async throws {
    let auth = try EmulatorApp().auth
    let user = try await auth.createUser(withEmail: newEmail(), password: password).user

    let change = user.createProfileChangeRequest()
    change.displayName = "Ada Lovelace"
    try await change.commitChanges()
    try await user.reload()

    #expect(auth.currentUser?.displayName == "Ada Lovelace")
  }

  @Test func updatedPasswordsAreUsedForSignIn() async throws {
    let auth = try EmulatorApp().auth
    let email = newEmail()
    let user = try await auth.createUser(withEmail: email, password: password).user

    try await user.updatePassword(to: "a-new-password")
    try auth.signOut()

    await #expect(throws: NSError.self) {
      try await auth.signIn(withEmail: email, password: self.password)
    }
    let signedIn = try await auth.signIn(withEmail: email, password: "a-new-password").user
    #expect(signedIn.uid == user.uid)
  }

  @Test func deletingTheUserSignsOutAndRemovesTheAccount() async throws {
    let auth = try EmulatorApp().auth
    let email = newEmail()
    let user = try await auth.createUser(withEmail: email, password: password).user

    try await user.delete()
    #expect(auth.currentUser == nil)

    let error = await #expect(throws: NSError.self) {
      try await auth.signIn(withEmail: email, password: self.password)
    }
    let expected = [AuthErrorCode.userNotFound, .invalidCredential].map(\.rawValue)
    #expect(expected.contains(error?.code ?? 0))
  }

  @Test func stateListenersSeeSignInAndSignOut() async throws {
    let auth = try EmulatorApp().auth
    let seen = Locked<[String?]>([])
    let handle = auth.addStateDidChangeListener { _, user in
      seen.withLock { $0.append(user?.uid) }
    }
    defer { auth.removeStateDidChangeListener(handle) }

    // The listener fires once on registration, with no user.
    try await eventually { seen.withLock { $0 } == [nil] }

    let uid = try await auth.signInAnonymously().user.uid
    try await eventually { seen.withLock { $0 } == [nil, uid] }

    try auth.signOut()
    try await eventually { seen.withLock { $0 } == [nil, uid, nil] }
  }
}
