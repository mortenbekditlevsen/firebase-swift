// Copyright 2020 Google LLC
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

/// Firebase App Check error domain.
public let AppCheckErrorDomain = "com.firebase.appCheck"

/// The codes of App Check errors, in `AppCheckErrorDomain`.
public enum AppCheckErrorCode: Int, Sendable {
  /// An unknown or non-actionable error.
  case unknown = 0

  /// A network connection error.
  case serverUnreachable = 1

  /// Invalid configuration error. Currently, an exception is thrown but this error is reserved
  /// for future implementations of invalid configuration detection.
  case invalidConfiguration = 2

  /// System keychain access error. Ensure that the app has proper keychain access.
  case keychain = 3

  /// Selected app attestation provider is not supported on the current platform or OS version.
  case unsupported = 4
}

/// As upstream's `FIRAppCheckErrorUtil`: errors from AppCheckCore are reported in
/// `AppCheckErrorDomain`, and other errors as `.unknown`, with the error as the underlying one.
enum AppCheckErrorUtil {
  static func publicDomainError(with error: Error) -> NSError {
    let nsError = error as NSError
    if nsError.domain == AppCheckCoreErrorDomain {
      guard let code = AppCheckCoreErrorCode(rawValue: nsError.code) else {
        return unknownError(with: nsError)
      }
      let publicCode: AppCheckErrorCode = switch code {
      case .unknown: .unknown
      case .serverUnreachable: .serverUnreachable
      case .invalidConfiguration: .invalidConfiguration
      case .keychain: .keychain
      case .unsupported: .unsupported
      }
      return NSError(domain: AppCheckErrorDomain, code: publicCode.rawValue,
                     userInfo: nsError.userInfo)
    } else if nsError.domain == AppCheckErrorDomain {
      return nsError
    }
    return unknownError(with: nsError)
  }

  private static func unknownError(with error: NSError) -> NSError {
    var userInfo: [String: Any] = [NSUnderlyingErrorKey: error]
    userInfo[NSLocalizedFailureReasonErrorKey] = error.userInfo[NSLocalizedFailureReasonErrorKey]
    return NSError(domain: AppCheckErrorDomain, code: AppCheckErrorCode.unknown.rawValue,
                   userInfo: userInfo)
  }
}
