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
import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// The shared secret of a TOTP second factor that's being enrolled.
public final class TOTPSecret: Sendable {
  /// The secret key, for entering in an authenticator app by hand.
  public func sharedSecretKey() -> String {
    secretKey
  }

  /// An `otpauth://` URL for the secret, to show as a QR code or open in an authenticator app.
  /// Returns an empty string if the backend didn't send the algorithm or code length.
  /// - Parameter accountName: The account name to show in the app, such as the user's email.
  /// - Parameter issuer: The issuer to show in the app, such as your app's name.
  public func generateQRCodeURL(withAccountName accountName: String, issuer: String) -> String {
    guard let hashingAlgorithm, codeLength > 0 else {
      return ""
    }
    // Unlike upstream, the name and issuer are escaped: they often contain spaces.
    var components = URLComponents()
    components.scheme = "otpauth"
    components.host = "totp"
    components.path = "/\(issuer):\(accountName)"
    components.queryItems = [
      URLQueryItem(name: "secret", value: secretKey),
      URLQueryItem(name: "issuer", value: issuer),
      URLQueryItem(name: "algorithm", value: hashingAlgorithm),
      URLQueryItem(name: "digits", value: String(codeLength)),
    ]
    return components.string ?? ""
  }

  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    /// Opens `qrCodeURL` (from `generateQRCodeURL(withAccountName:issuer:)`) in an
    /// authenticator app. Does nothing in app extensions.
    @MainActor
    public func openInOTPApp(withQRCodeURL qrCodeURL: String) {
      guard let url = URL(string: qrCodeURL) else {
        AuthLog.logError(code: "I-AUT000019", message: "URL: \(qrCodeURL) cannot be opened")
        return
      }
      #if os(macOS)
        NSWorkspace.shared.open(url)
      #else
        // Through reflection, as upstream does, to build in app extensions.
        let selector = NSSelectorFromString("sharedApplication")
        guard !Bundle.main.bundlePath.hasSuffix(".appex"),
              UIApplication.responds(to: selector),
              let application = UIApplication.perform(selector)?.takeUnretainedValue()
              as? UIApplication else {
          return
        }
        if application.canOpenURL(url) {
          application.open(url)
        } else {
          AuthLog.logError(code: "I-AUT000019", message: "URL: \(qrCodeURL) cannot be opened")
        }
      #endif
    }
  #endif

  private let secretKey: String
  private let hashingAlgorithm: String?
  private let codeLength: Int
  private let codeIntervalSeconds: Int
  private let enrollmentCompletionDeadline: Date?
  let sessionInfo: String?

  init(secretKey: String, hashingAlgorithm: String?, codeLength: Int, codeIntervalSeconds: Int,
       enrollmentCompletionDeadline: Date?, sessionInfo: String?) {
    self.secretKey = secretKey
    self.hashingAlgorithm = hashingAlgorithm
    self.codeLength = codeLength
    self.codeIntervalSeconds = codeIntervalSeconds
    self.enrollmentCompletionDeadline = enrollmentCompletionDeadline
    self.sessionInfo = sessionInfo
  }
}
