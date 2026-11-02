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

import Foundation

/// The domain of errors from Firestore.
public let FirestoreErrorDomain = "FIRFirestoreErrorDomain"

/// An error from Firestore, in `FirestoreErrorDomain`.
///
/// Mirrors upstream's `NS_ERROR_ENUM`: match a code with
/// `case FirestoreErrorCode.unavailable:`, or cast with `error as? FirestoreErrorCode`.
public struct FirestoreErrorCode: CustomNSError, Hashable, Sendable {
  /// The error codes, the same as gRPC's.
  public enum Code: Int, Sendable {
    /// The operation completed successfully. Not used for errors.
    case ok = 0
    /// The operation was cancelled (typically by the caller).
    case cancelled = 1
    /// Unknown error or an error from a different error domain.
    case unknown = 2
    /// The client specified an invalid argument.
    case invalidArgument = 3
    /// The deadline expired before the operation could complete.
    case deadlineExceeded = 4
    /// Some requested document was not found.
    case notFound = 5
    /// Some document that we attempted to create already exists.
    case alreadyExists = 6
    /// The caller does not have permission to execute the specified operation.
    case permissionDenied = 7
    /// Some resource has been exhausted, perhaps a per-user quota.
    case resourceExhausted = 8
    /// The system is not in a state required for the operation's execution.
    case failedPrecondition = 9
    /// The operation was aborted, typically due to a concurrency issue.
    case aborted = 10
    /// The operation was attempted past the valid range.
    case outOfRange = 11
    /// The operation is not implemented or not supported.
    case unimplemented = 12
    /// Internal errors.
    case `internal` = 13
    /// The service is currently unavailable, most likely transiently.
    case unavailable = 14
    /// Unrecoverable data loss or corruption.
    case dataLoss = 15
    /// The request does not have valid authentication credentials.
    case unauthenticated = 16
  }

  public let code: Code
  private let message: String?

  public init(_ code: Code, userInfo: [String: Any] = [:]) {
    self.code = code
    message = userInfo[NSLocalizedDescriptionKey] as? String
  }

  public static var errorDomain: String { FirestoreErrorDomain }
  public var errorCode: Int { code.rawValue }
  public var errorUserInfo: [String: Any] {
    message.map { [NSLocalizedDescriptionKey: $0] } ?? [:]
  }

  public static var ok: Code { .ok }
  public static var cancelled: Code { .cancelled }
  public static var unknown: Code { .unknown }
  public static var invalidArgument: Code { .invalidArgument }
  public static var deadlineExceeded: Code { .deadlineExceeded }
  public static var notFound: Code { .notFound }
  public static var alreadyExists: Code { .alreadyExists }
  public static var permissionDenied: Code { .permissionDenied }
  public static var resourceExhausted: Code { .resourceExhausted }
  public static var failedPrecondition: Code { .failedPrecondition }
  public static var aborted: Code { .aborted }
  public static var outOfRange: Code { .outOfRange }
  public static var unimplemented: Code { .unimplemented }
  public static var `internal`: Code { .internal }
  public static var unavailable: Code { .unavailable }
  public static var dataLoss: Code { .dataLoss }
  public static var unauthenticated: Code { .unauthenticated }
}

public extension FirestoreErrorCode.Code {
  /// Lets `case FirestoreErrorCode.notFound:` match an `Error`.
  static func ~= (code: Self, error: any Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == FirestoreErrorDomain && nsError.code == code.rawValue
  }
}

/// The error a bridge callback reported, or nil for code 0 (OK).
func firestoreError(code: Int32, message: UnsafePointer<CChar>?) -> FirestoreErrorCode? {
  guard code != 0 else { return nil }
  let code = FirestoreErrorCode.Code(rawValue: Int(code)) ?? .unknown
  let message = message.map { String(cString: $0) } ?? ""
  return FirestoreErrorCode(code, userInfo: [NSLocalizedDescriptionKey: message])
}

/// Stops on an invalid argument, as upstream does by raising an exception.
func invalidArgument(_ message: String) -> Never {
  fatalError("Invalid argument: \(message)")
}
