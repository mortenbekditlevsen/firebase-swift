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

/// Multi-factor auth on every platform. Phone factors are enrolled through the emulator's admin
/// API here: verifying a phone number takes `PhoneAuthProvider`, which is iOS-only (see
/// PhoneAuthIntegrationTests). The emulator doesn't support TOTP.
@Suite(.enabled(if: Emulators.auth != nil, "Needs the Auth emulator"), .timeLimit(.minutes(1)))
struct MultiFactorIntegrationTests {
  private let password = "correct-horse-battery-staple"

  /// A signed-in user with a verified email.
  private func newUser(_ auth: Auth) async throws -> (user: User, email: String) {
    let email = "mfa-\(UUID().uuidString.lowercased())@example.com"
    let user = try await auth.createUser(withEmail: email, password: password).user
    try await AuthEmulatorAdmin.verifyEmail(of: user)
    return (user, email)
  }

  @Test func enrolledFactorsAreListedAndCanBeRemoved() async throws {
    let app = try EmulatorApp()
    let (user, email) = try await newUser(app.auth)
    #expect(user.multiFactor.enrolledFactors.isEmpty)

    try await AuthEmulatorAdmin.enrollPhoneFactors(["+15550000001", "+15550000002"],
                                                   for: user.uid)
    try await user.reload()
    let factors = try #require(app.auth.currentUser?.multiFactor.enrolledFactors)
    #expect(factors.map(\.uid) == ["phone-0", "phone-1"])
    #expect(factors.map(\.factorID) == ["phone", "phone"])
    #expect(factors.map(\.displayName) == ["Phone 0", "Phone 1"])
    #expect((factors.first as? PhoneMultiFactorInfo)?.phoneNumber == "+15550000001")

    let current = try #require(app.auth.currentUser)
    try await current.multiFactor.unenroll(with: factors[0])
    let remaining = try #require(app.auth.currentUser?.multiFactor.enrolledFactors)
    #expect(remaining.map(\.uid) == ["phone-1"])

    try await app.auth.currentUser?.multiFactor.unenroll(withFactorUID: "phone-1")
    #expect(app.auth.currentUser?.multiFactor.enrolledFactors.isEmpty == true)

    // Without factors, signing in takes only the password again.
    try app.auth.signOut()
    let signedIn = try await app.auth.signIn(withEmail: email, password: password)
    #expect(signedIn.user.uid == user.uid)
  }

  @Test func signInAsksForTheSecondFactor() async throws {
    let app = try EmulatorApp()
    let (user, email) = try await newUser(app.auth)
    try await AuthEmulatorAdmin.enrollPhoneFactors(["+15550000003"], for: user.uid)
    try app.auth.signOut()

    let error = await #expect(throws: (any Error).self) {
      try await app.auth.signIn(withEmail: email, password: password)
    }
    let nsError = try #require(error as? NSError)
    #expect(nsError.code == AuthErrorCode.secondFactorRequired.rawValue, "\(nsError)")
    #expect(app.auth.currentUser == nil)

    let resolver = try #require(
      nsError.userInfo[AuthErrors.userInfoMultiFactorResolverKey] as? MultiFactorResolver
    )
    #expect(resolver.auth === app.auth)
    let hint = try #require(resolver.hints.first as? PhoneMultiFactorInfo)
    #expect(resolver.hints.count == 1)
    #expect(hint.uid == "phone-0")
    #expect(hint.factorID == PhoneMultiFactorInfo.PhoneMultiFactorID)
    #expect(hint.displayName == "Phone 0")
    // The backend masks the number in hints.
    #expect(hint.phoneNumber.hasSuffix("0003"))
  }

  @Test func aRejectedSecondFactorLeavesTheUserSignedOut() async throws {
    let app = try EmulatorApp()
    let (user, email) = try await newUser(app.auth)
    try await AuthEmulatorAdmin.enrollPhoneFactors(["+15550000004"], for: user.uid)
    try app.auth.signOut()
    let error = await #expect(throws: (any Error).self) {
      try await app.auth.signIn(withEmail: email, password: password)
    }
    let resolver = try #require(
      (error as? NSError)?.userInfo[AuthErrors.userInfoMultiFactorResolverKey]
        as? MultiFactorResolver
    )
    // A TOTP code for the phone factor; the emulator rejects it (it has no TOTP).
    let assertion = TOTPMultiFactorGenerator.assertionForSignIn(withEnrollmentID: "phone-0",
                                                                oneTimePassword: "123456")
    await #expect(throws: (any Error).self) {
      try await resolver.resolveSignIn(with: assertion)
    }
    #expect(app.auth.currentUser == nil)
  }
}
