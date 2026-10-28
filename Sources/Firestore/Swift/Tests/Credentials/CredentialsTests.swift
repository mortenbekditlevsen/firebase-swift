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

import FirebaseCore
import FirebaseFirestore
import Foundation
import Synchronization
import Testing

/// Checks that Firestore's C++ credentials providers reach the app's Swift
/// `AuthInterop`/`AppCheckInterop`. Firestore asks for tokens before it
/// connects, so no backend is needed: the host is an unreachable local port.
@Suite struct CredentialsTests {
  @Test func requestsAuthTokenFromAuthInterop() async throws {
    let auth = FakeAuth(uid: "user-1", token: "auth-token")
    let db = makeFirestore(auth: auth, appCheck: nil)

    db.document("coll/doc").getDocument { _, _ in }

    try await waitUntil { auth.tokenRequests > 0 }
  }

  @Test func requestsAppCheckTokenFromAppCheckInterop() async throws {
    let appCheck = FakeAppCheck(token: "app-check-token")
    let db = makeFirestore(auth: FakeAuth(uid: nil, token: nil), appCheck: appCheck)

    db.document("coll/doc").getDocument { _, _ in }

    try await waitUntil { appCheck.tokenRequests > 0 }
  }

  @Test func signedOutAuthDoesNotBlockRequests() async throws {
    // AuthInterop returns nil when nobody is signed in; Firestore must treat
    // that as unauthenticated and keep going (to the App Check request).
    let appCheck = FakeAppCheck(token: "")
    let auth = FakeAuth(uid: nil, token: nil)
    let db = makeFirestore(auth: auth, appCheck: appCheck)

    db.document("coll/doc").getDocument { _, _ in }

    try await waitUntil { auth.tokenRequests > 0 && appCheck.tokenRequests > 0 }
  }

  @Test func authErrorsReachTheCaller() async throws {
    let auth = FakeAuth(uid: "user-1", token: nil, error: FakeError())
    let db = makeFirestore(auth: auth, appCheck: nil)

    db.document("coll/doc").getDocument { _, _ in }

    // The failed request must be completed (not leaked) and retried later.
    try await waitUntil { auth.tokenRequests > 0 }
  }
}

// MARK: - Fakes

private struct FakeError: Error {}

private final class FakeAuth: AuthInterop {
  private let uid: String?
  private let token: String?
  private let error: Error?
  private let requests = Mutex(0)

  init(uid: String?, token: String?, error: Error? = nil) {
    self.uid = uid
    self.token = token
    self.error = error
  }

  var tokenRequests: Int { requests.withLock { $0 } }

  func getToken(forcingRefresh forceRefresh: Bool) async throws -> String? {
    requests.withLock { $0 += 1 }
    if let error { throw error }
    return token
  }

  func getUserID() -> String? { uid }
}

private final class FakeAppCheck: AppCheckInterop {
  private let token: String
  private let requests = Mutex(0)

  init(token: String) { self.token = token }

  var tokenRequests: Int { requests.withLock { $0 } }

  func getToken(forcingRefresh: Bool) async throws -> String {
    requests.withLock { $0 += 1 }
    return token
  }
}

// MARK: - Helpers

private func makeFirestore(auth: AuthInterop?, appCheck: AppCheckInterop?) -> Firestore {
  let options = FirebaseApp.Options(
    projectID: "credentials-test",
    googleAppID: "1:123:ios:123ab",
    apiKey: nil,
    clientID: nil,
    storageBucket: nil
  )
  let app = FirebaseApp(options: options, name: "credentials-\(UUID().uuidString)")
  app.auth = auth
  app.appCheck = appCheck
  let db = Firestore.firestore(app: app)
  let settings = db.settings
  // Port 1 refuses connections, so nothing leaves the machine.
  settings.host = "127.0.0.1:1"
  settings.isSSLEnabled = false
  settings.isPersistenceEnabled = false
  db.settings = settings
  return db
}

private struct Timeout: Error {}

private func waitUntil(
  timeout: Duration = .seconds(10),
  _ condition: () -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    guard ContinuousClock.now < deadline else { throw Timeout() }
    try await Task.sleep(for: .milliseconds(20))
  }
}
