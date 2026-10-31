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

@testable import FirebaseAuth
import Foundation
import Testing

/// Fixes ported from upstream 11.x–13.1 (see Docs/upstream/FirebaseAuth.md).
struct ActionCodeURLTests {
  @Test(arguments: [
    ("resetPassword", ActionCodeOperation.passwordReset),
    ("verifyEmail", .verifyEmail),
    ("recoverEmail", .recoverEmail),
    ("signIn", .emailLink),
    ("verifyAndChangeEmail", .verifyAndChangeEmail),
    ("revertSecondFactorAddition", .revertSecondFactorAddition),
    ("somethingElse", .unknown),
  ])
  func linksUseCamelCaseModes(mode: String, operation: ActionCodeOperation) throws {
    let url = try #require(ActionCodeURL(link: "https://example.com/?mode=\(mode)&oobCode=code"))
    #expect(url.operation == operation)
  }

  @Test func backendRequestTypesAreScreamingSnakeCase() {
    #expect(ActionCodeInfo.actionCodeOperation(forRequestType: "VERIFY_EMAIL") == .verifyEmail)
    #expect(ActionCodeInfo.actionCodeOperation(forRequestType: "EMAIL_SIGNIN") == .emailLink)
    #expect(ActionCodeInfo.actionCodeOperation(forRequestType: "verifyEmail") == .unknown)
  }

  @Test func readsTheLanguageFromLang() throws {
    let url = try #require(ActionCodeURL(link: "https://example.com/?mode=signIn&lang=da"))
    #expect(url.languageCode == "da")
  }

  @Test func ignoresParametersWithoutAValue() throws {
    // Used to index past the end of the split.
    let url = try #require(ActionCodeURL(link: "https://example.com/?mode=signIn&flag&oobCode=c"))
    #expect(url.code == "c")
  }
}

struct AuthTokenLifetimeTests {
  @Test func acceptsLifetimesUpToADay() throws {
    let date = AuthTokenLifetime.expirationDate(expiresIn: "3600")
    #expect(abs(date.timeIntervalSinceNow - 3600) < 5)
  }

  @Test(arguments: ["0", "-5", "1e300", "inf", "nan", "abc", "", "90000"])
  func replacesInvalidLifetimesWithAnHour(expiresIn: String) {
    let date = AuthTokenLifetime.expirationDate(expiresIn: expiresIn)
    #expect(abs(date.timeIntervalSinceNow - AuthTokenLifetime.standard) < 5)
  }

  @Test func boundsTheRefreshDelay() {
    #expect(AuthTokenLifetime.boundedRefreshDelay(.infinity) == 0)
    #expect(AuthTokenLifetime.boundedRefreshDelay(.nan) == 0)
    #expect(AuthTokenLifetime.boundedRefreshDelay(1e20) == 0)
    #expect(AuthTokenLifetime.boundedRefreshDelay(-10) == 0)
    #expect(AuthTokenLifetime.boundedRefreshDelay(600) == 600)
  }

  @Test func savedExpirationDatesFarAheadAreDropped() throws {
    let json = """
      {"accessToken": "token", "refreshToken": "refresh",
       "accessTokenExpirationDate": \(Date.distantFuture.timeIntervalSinceReferenceDate)}
      """
    let service = try JSONDecoder().decode(SecureTokenService.self, from: Data(json.utf8))
    #expect(service.accessTokenExpirationDate == nil)
  }
}

struct AuthErrorParsingTests {
  @Test func blockingFunctionErrorsReadTheEmbeddedJSON() {
    let message = "HTTP Cloud Function returned an error: " +
      #"{"error": {"message": "Who are you?", "status": "INVALID_ARGUMENT"}}"#
    let error = AuthErrorUtils.blockingCloudFunctionServerResponse(message: message) as NSError
    #expect(error.code == AuthErrorCode.blockingCloudFunctionError.rawValue)
    #expect(error.localizedDescription == "Who are you?")
  }

  @Test func authErrorCodesAreErrors() {
    let error: Error = AuthErrorCode.invalidHostingLinkDomain
    #expect((error as NSError).domain == AuthErrors.domain)
    #expect(AuthErrorCode.passwordDoesNotMeetRequirements.code == .passwordDoesNotMeetRequirements)
  }
}
