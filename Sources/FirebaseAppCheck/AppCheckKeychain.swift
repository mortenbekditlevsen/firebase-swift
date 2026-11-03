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

/// Secure storage for what App Check keeps between launches: the cached App Check token and, with
/// `AppAttestProvider`, the App Attest artifact. Both are secrets.
///
/// Upstream stores them in the keychain. This port has no storage of its own: the app passes one
/// to `AppCheck.setAppCheckProviderFactory(_:keychain:)`, for example a keychain on Apple
/// platforms or libsecret on Linux.
///
/// Items are identified by `service` and `key`, and by `accessGroup` when it isn't nil (the
/// `FirebaseOptions.appGroupID`, for sharing between an app and its extensions).
public protocol AppCheckKeychain: Sendable {
  /// Returns the stored data, or nil if there's none.
  func data(forKey key: String, service: String, accessGroup: String?) async throws -> Data?

  /// Stores data, replacing any stored before.
  func setData(_ data: Data, forKey key: String, service: String,
               accessGroup: String?) async throws

  /// Removes stored data. Removing data that isn't there isn't an error.
  func removeData(forKey key: String, service: String, accessGroup: String?) async throws
}
