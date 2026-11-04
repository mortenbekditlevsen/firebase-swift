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

@testable import FirebaseAppCheck
import FirebaseCore
import FirebaseFunctions
import Foundation
import Synchronization
import Testing

/// App Check's tokens reach a function. The emulator has no App Check backend, so the provider
/// makes the tokens; `appCheckTest` returns the `X-Firebase-AppCheck` header it got.
///
/// Each app gets App Check of its own instead of `AppCheck.setAppCheckProviderFactory`, which
/// would apply to the apps of every test running alongside.
struct FunctionsAppCheckIntegrationTests {
  private struct EmptyRequest: Encodable, Sendable {}

  private struct TokenResponse: Decodable {
    let token: String?
  }

  /// The token App Check returns to the SDKs when its provider fails.
  private static let placeholderToken = "eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ=="

  private let emulatorApp: EmulatorApp
  private let provider = TokenProvider()

  init() throws {
    emulatorApp = try EmulatorApp()
    let app = emulatorApp.app
    let appCheck = try #require(AppCheck(app: app,
                                         providerFactory: TokenProviderFactory(provider: provider),
                                         keychain: InMemoryKeychain()))
    app.appCheck = appCheck
  }

  private func appCheckTest(limitedUse: Bool = false) throws
    -> Callable<EmptyRequest, TokenResponse> {
    try emulatorApp.functions().httpsCallable(
      "appCheckTest",
      options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: limitedUse),
      requestAs: EmptyRequest.self,
      responseAs: TokenResponse.self
    )
  }

  @Test func sendsTheAppCheckToken() async throws {
    let function = try appCheckTest()

    #expect(try await function.call(EmptyRequest()).token == "token-1")
    // The token is cached until it's about to expire. The token refresher's first refresh, when
    // App Check is created, shares it too.
    #expect(try await function.call(EmptyRequest()).token == "token-1")
    #expect(provider.tokenCount == 1)
  }

  @Test func sendsALimitedUseTokenForEachCallWhenRequired() async throws {
    let function = try appCheckTest(limitedUse: true)

    #expect(try await function.call(EmptyRequest()).token == "limited-use-token-1")
    #expect(try await function.call(EmptyRequest()).token == "limited-use-token-2")
  }

  @Test func sendsThePlaceholderTokenWhenTheProviderFails() async throws {
    provider.fails = true
    let function = try appCheckTest()

    #expect(try await function.call(EmptyRequest()).token == Self.placeholderToken)
  }
}

private final class TokenProvider: AppCheckProvider, Sendable {
  private struct State {
    var tokenCount = 0
    var limitedUseTokenCount = 0
    var fails = false
  }

  private let state = Mutex(State())

  var tokenCount: Int { state.withLock { $0.tokenCount } }

  var fails: Bool {
    get { state.withLock { $0.fails } }
    set { state.withLock { $0.fails = newValue } }
  }

  func getToken() async throws -> AppCheckToken {
    let count = try state.withLock { state in
      if state.fails {
        throw URLError(.notConnectedToInternet)
      }
      state.tokenCount += 1
      return state.tokenCount
    }
    return AppCheckToken(token: "token-\(count)", expirationDate: Date(timeIntervalSinceNow: 3600))
  }

  func getLimitedUseToken() async throws -> AppCheckToken {
    let count = state.withLock { state in
      state.limitedUseTokenCount += 1
      return state.limitedUseTokenCount
    }
    return AppCheckToken(token: "limited-use-token-\(count)",
                         expirationDate: Date(timeIntervalSinceNow: 300))
  }
}

private final class TokenProviderFactory: AppCheckProviderFactory {
  private let provider: TokenProvider

  init(provider: TokenProvider) {
    self.provider = provider
  }

  func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
    provider
  }
}

/// Keeps App Check's stored token in memory.
private final class InMemoryKeychain: AppCheckKeychain {
  private let items = Mutex<[String: Data]>([:])

  private func key(_ key: String, _ service: String, _ accessGroup: String?) -> String {
    "\(service)|\(accessGroup ?? "")|\(key)"
  }

  func data(forKey key: String, service: String, accessGroup: String?) async throws -> Data? {
    items.withLock { $0[self.key(key, service, accessGroup)] }
  }

  func setData(_ data: Data, forKey key: String, service: String,
               accessGroup: String?) async throws {
    items.withLock { $0[self.key(key, service, accessGroup)] = data }
  }

  func removeData(forKey key: String, service: String, accessGroup: String?) async throws {
    _ = items.withLock { $0.removeValue(forKey: self.key(key, service, accessGroup)) }
  }
}
