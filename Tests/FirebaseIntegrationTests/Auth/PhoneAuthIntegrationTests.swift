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

// Phone auth is iOS-only. Run these in the iOS Simulator with
// scripts/test-ios.sh, which starts the Auth emulator.
#if os(iOS)
  @testable import FirebaseAuth
  import Foundation
  import Testing

  @Suite(.enabled(if: Emulators.auth != nil, "Needs the Auth emulator"), .timeLimit(.minutes(1)))
  struct PhoneAuthIntegrationTests {
    /// A number nobody else uses, since every test shares the emulator's user store.
    private func newPhoneNumber() -> String {
      "+1555\(Int.random(in: 1_000_000 ... 9_999_999))"
    }

    /// An app set up for the emulator's test mode, which sends no app credential. The
    /// caller keeps `app` alive: Auth holds it weakly.
    private func phoneApp() throws
      -> (app: EmulatorApp, auth: Auth, provider: PhoneAuthProvider) {
      let app = try EmulatorApp()
      let auth = app.auth
      auth.settings?.appVerificationDisabledForTesting = true
      // The test runner has no Info.plist URL scheme and no app delegate to forward the
      // notification that checks for one.
      auth.mainBundleUrlTypes = [["CFBundleURLSchemes": ["app-1-123-ios-123ab"]]]
      try #require(auth.notificationManager).immediateCallbackForTestFaking = { true }
      return (app, auth, PhoneAuthProvider.provider(auth: auth))
    }

    /// Reads the code the emulator "sent" for `verificationID`.
    private func code(for verificationID: String) async throws -> String {
      let address = try #require(Emulators.auth)
      let url = try #require(URL(string: "http://\(address.host):\(address.port)" +
          "/emulator/v1/projects/\(Emulators.projectID)/verificationCodes"))
      let (data, _) = try await URLSession.shared.data(from: url)
      let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
      let codes = try #require(json["verificationCodes"] as? [[String: Any]])
      let match = try #require(codes.first { $0["sessionInfo"] as? String == verificationID })
      return try #require(match["code"] as? String)
    }

    private func credential(for phoneNumber: String, provider: PhoneAuthProvider,
                            session: MultiFactorSession? = nil) async throws
      -> PhoneAuthCredential {
      let verificationID = try await provider.verifyPhoneNumber(phoneNumber,
                                                                multiFactorSession: session)
      return try await provider.credential(withVerificationID: verificationID,
                                           verificationCode: code(for: verificationID))
    }

    @Test func signsInWithAPhoneNumber() async throws {
      let (app, auth, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let phoneNumber = newPhoneNumber()

      let first = try await auth.signIn(with: credential(for: phoneNumber, provider: provider))
      #expect(first.user.phoneNumber == phoneNumber)
      #expect(first.additionalUserInfo?.isNewUser == true)
      #expect(first.additionalUserInfo?.providerID == PhoneAuthProvider.id)

      try auth.signOut()
      let second = try await auth.signIn(with: credential(for: phoneNumber, provider: provider))
      #expect(second.user.uid == first.user.uid)
      #expect(second.additionalUserInfo?.isNewUser == false)
    }

    @Test func aWrongCodeIsRejected() async throws {
      let (app, auth, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let verificationID = try await provider.verifyPhoneNumber(newPhoneNumber())
      let wrong = provider.credential(withVerificationID: verificationID,
                                      verificationCode: "000000")
      let error = await #expect(throws: (any Error).self) {
        try await auth.signIn(with: wrong)
      }
      #expect((error as? NSError)?.code == AuthErrorCode.invalidVerificationCode.rawValue)
      #expect(auth.currentUser == nil)
    }

    @Test func anEmptyPhoneNumberIsRejected() async throws {
      let (app, _, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let error = await #expect(throws: (any Error).self) {
        try await provider.verifyPhoneNumber("")
      }
      #expect((error as? NSError)?.code == AuthErrorCode.missingPhoneNumber.rawValue)
    }

    @Test func linksAPhoneNumberToAnAnonymousUser() async throws {
      let (app, auth, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let user = try await auth.signInAnonymously().user
      let phoneNumber = newPhoneNumber()

      let linked = try await user.link(with: credential(for: phoneNumber, provider: provider))
      #expect(linked.user.uid == user.uid)
      #expect(auth.currentUser?.phoneNumber == phoneNumber)
      #expect(auth.currentUser?.isAnonymous == false)
    }

    @Test func linkingANumberInUseFails() async throws {
      let (app, auth, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let phoneNumber = newPhoneNumber()
      _ = try await auth.signIn(with: credential(for: phoneNumber, provider: provider))
      try auth.signOut()

      let user = try await auth.signInAnonymously().user
      let error = await #expect(throws: (any Error).self) {
        try await user.link(with: credential(for: phoneNumber, provider: provider))
      }
      #expect((error as? NSError)?.code == AuthErrorCode.credentialAlreadyInUse.rawValue)
    }

    @Test func enrollsAndSignsInWithAPhoneSecondFactor() async throws {
      let (app, auth, provider) = try phoneApp()
      defer { withExtendedLifetime(app) {} }
      let email = "mfa-\(UUID().uuidString.lowercased())@example.com"
      let password = "correct-horse-battery-staple"
      let user = try await auth.createUser(withEmail: email, password: password).user
      try await AuthEmulatorAdmin.verifyEmail(of: user)

      let phoneNumber = newPhoneNumber()
      let session = try await user.multiFactor.session()
      let enrollment = try await credential(for: phoneNumber, provider: provider,
                                            session: session)
      try await user.multiFactor.enroll(
        with: PhoneMultiFactorGenerator.assertion(with: enrollment),
        displayName: "Phone"
      )
      let enrolled = try #require(auth.currentUser?.multiFactor.enrolledFactors.first
        as? PhoneMultiFactorInfo)
      #expect(enrolled.phoneNumber == phoneNumber)
      #expect(enrolled.displayName == "Phone")

      try auth.signOut()
      let error = await #expect(throws: (any Error).self) {
        try await auth.signIn(withEmail: email, password: password)
      }
      let nsError = try #require(error as? NSError)
      #expect(nsError.code == AuthErrorCode.secondFactorRequired.rawValue, "\(nsError)")
      let resolver = try #require(
        nsError.userInfo[AuthErrors.userInfoMultiFactorResolverKey] as? MultiFactorResolver
      )
      let hint = try #require(resolver.hints.first as? PhoneMultiFactorInfo)
      #expect(hint.uid == enrolled.uid)

      let verificationID = try await provider.verifyPhoneNumber(
        with: hint, multiFactorSession: resolver.session
      )
      let signInCredential = try await provider.credential(
        withVerificationID: verificationID,
        verificationCode: code(for: verificationID)
      )
      let result = try await resolver.resolveSignIn(
        with: PhoneMultiFactorGenerator.assertion(with: signInCredential)
      )
      #expect(result.user.uid == user.uid)
      #expect(auth.currentUser?.uid == user.uid)
    }
  }
#endif
