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

// firebase-swift: AppCheckCore is part of FirebaseAppCheck.
@testable import FirebaseAppCheck
import Foundation

/// Lets a test hold an in-flight operation open until it chooses to release
/// it, so coalescing behavior can be exercised deterministically.
actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let resumable = waiters
    waiters = []
    for continuation in resumable {
      continuation.resume()
    }
  }
}

class AppCheckCoreStorageFake: NSObject, AppCheckCoreStorageProtocol {
  var getTokenHandler: (() async throws -> AppCheckCoreToken?)?
  var setTokenHandler: ((AppCheckCoreToken?) async throws -> AppCheckCoreToken?)?
  var lastSetToken: AppCheckCoreToken?

  func getToken() async throws -> AppCheckCoreToken? {
    if let handler = getTokenHandler {
      return try await handler()
    }
    return nil
  }

  func setToken(_ token: AppCheckCoreToken?) async throws -> AppCheckCoreToken? {
    lastSetToken = token
    if let handler = setTokenHandler {
      return try await handler(token)
    }
    return token
  }
}

class AppCheckCoreProviderFake: NSObject, AppCheckCoreProvider {
  var tokenToReturn: AppCheckCoreToken?
  var errorToReturn: Error?
  var limitedUseTokenToReturn: AppCheckCoreToken?
  var limitedUseErrorToReturn: Error?
  var getTokenCallCount = 0
  var getLimitedUseTokenCallCount = 0

  func getToken(completion: @escaping (AppCheckCoreToken?, Error?) -> Void) {
    getTokenCallCount += 1
    completion(tokenToReturn, errorToReturn)
  }

  func getLimitedUseToken(completion: @escaping (AppCheckCoreToken?, Error?) -> Void) {
    getLimitedUseTokenCallCount += 1
    completion(limitedUseTokenToReturn, limitedUseErrorToReturn)
  }
}

class AppCheckCoreTokenRefresherFake: NSObject, AppCheckCoreTokenRefresherProtocol {
  var updateWithRefreshResultCallCount = 0
  var tokenRefreshHandler: AppCheckCoreTokenRefreshBlock?
  var lastToken: AppCheckCoreToken?
  var lastUpdateStateTokenHandler: AppCheckCoreTokenRefreshBlock?

  func updateWithRefreshResult(_ refreshResult: AppCheckCoreTokenRefreshResult) {
    updateWithRefreshResultCallCount += 1
  }
}

class AppCheckCoreSettingsFake: NSObject, AppCheckCoreSettingsProtocol {
  var isTokenAutoRefreshEnabled: Bool = true
}

class AppCheckCoreTokenDelegateFake: NSObject, AppCheckCoreTokenDelegate {
  var tokenDidUpdateCallCount = 0
  var lastToken: AppCheckCoreToken?

  func tokenDidUpdate(_ token: AppCheckCoreToken, serviceName: String) {
    tokenDidUpdateCallCount += 1
    lastToken = token
  }
}

class AppCheckCoreFakeTimer: NSObject, AppCheckCoreTimerProtocol {
  var handler: (() -> Void)?
  var createHandler: ((Date) -> Void)?
  var isInvalidated = false
  var fireDate: Date?

  func fakeTimerProvider() -> AppCheckCoreTimerProvider {
    return { fireDate, queue, handler in
      self.fireDate = fireDate
      self.handler = handler
      self.createHandler?(fireDate)
      return self
    }
  }

  func start() {
    // do nothing
  }

  func invalidate() {
    isInvalidated = true
  }

  func fire() {
    handler?()
  }
}

// firebase-swift: upstream's fake subclasses GoogleUtilities' `GULKeychainStorage`; here the
// keychain is the app's `AppCheckKeychain`, so the fake is one, in memory.
final class AppCheckCoreKeychainStorageFake: AppCheckKeychain, @unchecked Sendable {
  private let lock = NSLock()
  private var _keychainError: Error?
  private var items: [String: Data] = [:]

  var keychainError: Error? {
    get { lock.withLock { _keychainError } }
    set { lock.withLock { _keychainError = newValue } }
  }

  func data(forKey key: String, service: String, accessGroup: String?) async throws -> Data? {
    try lock.withLock {
      if let error = _keychainError {
        throw error
      }
      return items[itemKey(key, service, accessGroup)]
    }
  }

  func setData(_ data: Data, forKey key: String, service: String,
               accessGroup: String?) async throws {
    try lock.withLock {
      if let error = _keychainError {
        throw error
      }
      items[itemKey(key, service, accessGroup)] = data
    }
  }

  func removeData(forKey key: String, service: String, accessGroup: String?) async throws {
    try lock.withLock {
      if let error = _keychainError {
        throw error
      }
      items[itemKey(key, service, accessGroup)] = nil
    }
  }

  private func itemKey(_ key: String, _ service: String, _ accessGroup: String?) -> String {
    "\(service)|\(accessGroup ?? "")|\(key)"
  }
}
