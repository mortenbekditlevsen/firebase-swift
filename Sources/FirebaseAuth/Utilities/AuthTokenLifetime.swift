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

/// Bounds for access token lifetimes, and for the dates and delays derived from them.
///
/// The backend sends the lifetime of a new access token as a string of seconds, in the
/// `expiresIn` or `expires_in` field of sign-in, update, and token refresh responses. The
/// resulting expiration date is saved with the user, and it sets when the automatic token
/// refresh runs. Firebase ID tokens last one hour, so 24 hours leaves wide headroom, while it
/// rejects values that would crash when the refresh is scheduled (a crash that repeats at every
/// launch, as the date is saved), or that would refresh the token too late, or never.
enum AuthTokenLifetime {
  /// The standard lifetime of a Firebase ID token: one hour. It replaces invalid lifetimes.
  static let standard: TimeInterval = 60 * 60

  /// The longest accepted token lifetime, and the longest delay of the automatic token refresh:
  /// 24 hours.
  static let maximum: TimeInterval = 24 * 60 * 60

  /// Returns the approximate expiration date for a token lifetime from a backend response. A
  /// lifetime that isn't a number in `(0, maximum]` is replaced with `standard`, and a warning
  /// is logged.
  static func expirationDate(expiresIn: String) -> Date {
    let lifetime = Double(expiresIn.trimmingCharacters(in: .whitespaces)) ?? .nan
    // Check `isFinite` explicitly, as comparisons with NaN are always false.
    guard lifetime.isFinite, lifetime > 0, lifetime <= maximum else {
      AuthLog.logWarning(
        code: "I-AUT000033",
        message: "Ignoring the invalid token lifetime \"\(expiresIn.prefix(32))\" from the " +
          "backend. Using \(Int(standard)) seconds instead."
      )
      return Date(timeIntervalSinceNow: standard)
    }
    return Date(timeIntervalSinceNow: lifetime)
  }

  /// Returns whether a saved access token expiration date is in range: finite, and no more than
  /// `maximum` from now. A date in the past is in range; the token has expired.
  static func isInRange(expirationDate: Date) -> Bool {
    let remainingLifetime = expirationDate.timeIntervalSinceNow
    return remainingLifetime.isFinite && remainingLifetime <= maximum
  }

  /// Returns the delay of the automatic token refresh, bounded to `[0, maximum]`. A delay that
  /// isn't finite, or is longer than `maximum`, becomes 0, which refreshes the token right away.
  static func boundedRefreshDelay(_ delay: TimeInterval) -> TimeInterval {
    guard delay.isFinite, delay <= maximum else {
      return 0
    }
    return max(delay, 0)
  }
}
