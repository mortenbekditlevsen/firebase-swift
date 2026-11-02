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
  import UIKit

  // Protocol to help with unit tests.
  protocol AuthNotificationApplication: Sendable {
    @MainActor var delegate: UIApplicationDelegate? { get }

    /// The `UIApplication` to pass to `UIApplicationDelegate` callbacks.
    @MainActor var applicationForDelegate: UIApplication { get }
  }

  extension UIApplication: AuthNotificationApplication {
    var applicationForDelegate: UIApplication { self }
  }

  /// Handles the remote notifications that deliver app credential secrets.
  ///
  /// There's no app delegate swizzling in this port: the app passes remote notifications to
  /// `Auth.canHandleNotification(_:)`.
  final class AuthNotificationManager: Sendable {
    /// The key to locate payload data in the remote notification.
    private let kNotificationDataKey = "com.google.firebase.auth"

    /// The key for the receipt in the remote notification payload data.
    private let kNotificationReceiptKey = "receipt"

    /// The key for the secret in the remote notification payload data.
    private let kNotificationSecretKey = "secret"

    /// The key for marking the prober in the remote notification payload data.
    private let kNotificationProberKey = "warning"

    private let application: AuthNotificationApplication

    /// The object to handle app credentials delivered via notification.
    private let appCredentialManager: AuthAppCredentialManager

    /// The timeout for checking for notification forwarding.
    let timeout: TimeInterval

    private struct State {
      var hasCheckedNotificationForwarding = false
      var isNotificationBeingForwarded = false
      var waiting: [CheckedContinuation<Bool, Never>] = []
      /// Disables the check, for tests.
      var immediateCallbackForTestFaking: (@Sendable () -> Bool)?
    }

    private let state = Mutex(State())

    init(withApplication application: AuthNotificationApplication,
         appCredentialManager: AuthAppCredentialManager,
         timeout: TimeInterval = 1) {
      self.application = application
      self.appCredentialManager = appCredentialManager
      self.timeout = timeout
    }

    var immediateCallbackForTestFaking: (@Sendable () -> Bool)? {
      get { state.withLock { $0.immediateCallbackForTestFaking } }
      set { state.withLock { $0.immediateCallbackForTestFaking = newValue } }
    }

    /// Checks whether remote notifications are forwarded to this class, by sending a
    /// fake one to the app delegate.
    func checkNotificationForwarding() async -> Bool {
      await withCheckedContinuation { continuation in
        enum Action { case resume(Bool), wait, probe }
        let action: Action = state.withLock { state in
          if let fake = state.immediateCallbackForTestFaking {
            return .resume(fake())
          }
          if state.hasCheckedNotificationForwarding {
            return .resume(state.isNotificationBeingForwarded)
          }
          state.waiting.append(continuation)
          return state.waiting.count == 1 ? .probe : .wait
        }
        switch action {
        case let .resume(forwarded):
          continuation.resume(returning: forwarded)
        case .wait:
          break
        case .probe:
          probe()
        }
      }
    }

    private func probe() {
      let application = self.application
      let proberNotification = [kNotificationDataKey: [kNotificationProberKey:
          "This fake notification should be forwarded to Firebase Auth."]]
      Task { @MainActor in
        let selector = #selector(UIApplicationDelegate
          .application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        if let delegate = application.delegate, delegate.responds(to: selector) {
          delegate.application?(application.applicationForDelegate,
                                didReceiveRemoteNotification: proberNotification) { _ in }
        } else {
          AuthLog.logWarning(
            code: "I-AUT000015",
            message: "The UIApplicationDelegate must handle " +
              "remote notification for phone number authentication to work."
          )
        }
        kAuthGlobalWorkQueue.asyncAfter(deadline: .now() + self.timeout) {
          self.finishCheck(forwarded: false)
        }
      }
    }

    /// Records the result of the check, unless one is recorded already.
    private func finishCheck(forwarded: Bool) {
      let (waiting, result): ([CheckedContinuation<Bool, Never>], Bool) = state.withLock { state in
        if !state.hasCheckedNotificationForwarding {
          state.hasCheckedNotificationForwarding = true
          state.isNotificationBeingForwarded = forwarded
        }
        defer { state.waiting = [] }
        return (state.waiting, state.isNotificationBeingForwarded)
      }
      for continuation in waiting {
        continuation.resume(returning: result)
      }
    }

    /// Attempts to handle the remote notification.
    /// - Parameter notification: The notification in question.
    /// - Returns: Whether or the notification has been handled.
    func canHandle(notification: [AnyHashable: Any]) -> Bool {
      var stringDictionary: [String: Any]?
      let data = notification[kNotificationDataKey]
      if let jsonString = data as? String {
        // Deserialize in case the data is a JSON string.
        guard let jsonData = jsonString.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
          return false
        }
        stringDictionary = dictionary
      }
      guard let dictionary = stringDictionary ?? data as? [String: Any] else {
        return false
      }
      if dictionary[kNotificationProberKey] != nil {
        let alreadyChecked = state.withLock { $0.hasCheckedNotificationForwarding }
        if alreadyChecked {
          return false
        }
        finishCheck(forwarded: true)
        return true
      }
      guard let receipt = dictionary[kNotificationReceiptKey] as? String,
            let secret = dictionary[kNotificationSecretKey] as? String else {
        return false
      }
      return appCredentialManager.canFinishVerification(withReceipt: receipt, secret: secret)
    }
  }
#endif
