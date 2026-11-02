// Copyright 2023 Google LLC
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
#if os(iOS)
  import Foundation
  import Synchronization

  /// Manages app credentials, backed by the keychain.
  final class AuthAppCredentialManager: Sendable {
    private struct AppCredentials: Codable {
      let credential: AuthAppCredential?
      let pendingReceipts: [String]?
    }

    private let kKeychainDataKey = "app_credentials"

    /// The maximum (but not necessarily the minimum) number of pending receipts to be kept.
    let maximumNumberOfPendingReceipts = 32

    private struct State {
      /// The keychain for app credentials to load from and to save to.
      let keychainServices: AuthStorage
      /// The full credential (which has a secret) to be used by the app, if one is available.
      var credential: AuthAppCredential?
      /// Pending receipts, in the order they were recorded.
      var pendingReceipts: [String] = []
      var waiting: [String: [CheckedContinuation<AuthAppCredential, Never>]] = [:]
      /// Only for testing.
      var fakeCredential: AuthAppCredential?
    }

    private let state: Mutex<State>

    init(withKeychain keychain: AuthStorage) {
      var initial = State(keychainServices: keychain)
      if let encodedData = try? keychain.data(forKey: kKeychainDataKey),
         let saved = try? JSONDecoder().decode(AppCredentials.self, from: encodedData) {
        initial.credential = saved.credential
        initial.pendingReceipts = saved.pendingReceipts ?? []
      }
      state = Mutex(initial)
    }

    /// The full credential (which has a secret) to be used by the app, if one is available.
    var credential: AuthAppCredential? {
      state.withLock { $0.credential }
    }

    var fakeCredential: AuthAppCredential? {
      get { state.withLock { $0.fakeCredential } }
      set { state.withLock { $0.fakeCredential = newValue } }
    }

    /// Records `receipt` and waits for its secret to arrive in a notification, or for
    /// `timeout`. Returns the full credential, or one with only the receipt on timeout.
    func didStartVerification(withReceipt receipt: String,
                              timeout: TimeInterval) async -> AuthAppCredential {
      await withCheckedContinuation { continuation in
        state.withLock { state in
          state.pendingReceipts.removeAll { $0 == receipt }
          if state.pendingReceipts.count >= maximumNumberOfPendingReceipts {
            state.pendingReceipts.removeFirst()
          }
          state.pendingReceipts.append(receipt)
          state.waiting[receipt, default: []].append(continuation)
          saveData(state)
        }
        kAuthGlobalWorkQueue.asyncAfter(deadline: .now() + timeout) {
          self.finishVerification(withReceipt: receipt)
        }
      }
    }

    /// Completes the verification of `receipt` with the secret from a notification.
    /// Returns false if the receipt isn't pending.
    func canFinishVerification(withReceipt receipt: String, secret: String) -> Bool {
      let pending = state.withLock { state in
        guard state.pendingReceipts.contains(receipt) else { return false }
        state.pendingReceipts.removeAll { $0 == receipt }
        state.credential = AuthAppCredential(receipt: receipt, secret: secret)
        saveData(state)
        return true
      }
      if pending {
        finishVerification(withReceipt: receipt)
      }
      return pending
    }

    func clearCredential() {
      state.withLock { state in
        state.credential = nil
        saveData(state)
      }
    }

    // MARK: Internal methods

    private func saveData(_ state: State) {
      let appCredentials = AppCredentials(credential: state.credential,
                                          pendingReceipts: state.pendingReceipts)
      if let data = try? JSONEncoder().encode(appCredentials) {
        try? state.keychainServices.setData(data, forKey: kKeychainDataKey)
      }
    }

    private func finishVerification(withReceipt receipt: String) {
      let (waiting, credential) = state.withLock { state in
        let waiting = state.waiting.removeValue(forKey: receipt) ?? []
        let credential = state.fakeCredential ?? state.credential
          ?? AuthAppCredential(receipt: receipt, secret: nil)
        return (waiting, credential)
      }
      for continuation in waiting {
        continuation.resume(returning: credential)
      }
    }
  }
#endif
