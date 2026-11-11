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

/// The debug tokens that the Firebase CLI (`firebase appcheck:debugtokens:create`) saves on the
/// host machine, by Google App ID. Upstream's `FIRAppCheckDebugTokenConfigStore` (13.2.0).
enum AppCheckDebugTokenConfigStore {
  /// The config store's path, relative to the host user's home directory.
  static let relativePath = ".config/configstore/firebase-appcheck.json"

  /// The debug token for `googleAppID` from the host machine's config store, in a Simulator.
  /// `nil` elsewhere, or if there's none.
  static func debugToken(forGoogleAppID googleAppID: String,
                         environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String? {
    #if targetEnvironment(simulator)
      // Set by the Simulator to the host user's home directory.
      guard let hostHome = environment["SIMULATOR_HOST_HOME"], !hostHome.isEmpty else {
        return nil
      }
      return debugToken(forGoogleAppID: googleAppID, hostHome: hostHome)
    #else
      return nil
    #endif
  }

  /// The debug token for `googleAppID` in the config store under `hostHome`. On every platform,
  /// for the tests.
  static func debugToken(forGoogleAppID googleAppID: String, hostHome: String) -> String? {
    guard !googleAppID.isEmpty else { return nil }
    let fileURL = URL(fileURLWithPath: hostHome, isDirectory: true)
      .appendingPathComponent(relativePath, isDirectory: false)
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      // A missing file (or a path where it can't exist) means the Firebase CLI flow isn't in use.
      if !isMissingFileError(error) {
        logger.warning("""
        I-FAA003006: Failed to read App Check debug tokens from ~/\(relativePath): \
        \(error.localizedDescription)
        """)
      }
      return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: data),
          let store = json as? [String: Any] else {
      logger.warning("""
      I-FAA003006: Failed to parse App Check debug tokens from ~/\(relativePath): expected a JSON \
      object
      """)
      return nil
    }
    // A config store without `tokens` (e.g. `{}` after the last token was removed) is valid.
    guard let tokens = store["tokens"] else { return nil }
    guard let tokens = tokens as? [String: Any] else {
      logger.warning("""
      I-FAA003006: Failed to parse App Check debug tokens from ~/\(relativePath): `tokens` is not \
      a JSON object
      """)
      return nil
    }
    guard let token = tokens[googleAppID] as? String, !token.isEmpty else { return nil }
    return token
  }

  /// Whether reading the config store failed because it doesn't exist. That includes a path
  /// component that's a file rather than a directory (e.g. `~/.config`), where it can't exist.
  private static func isMissingFileError(_ error: any Error) -> Bool {
    let error = error as NSError
    if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      return true
    }
    guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
    return underlying.domain == NSPOSIXErrorDomain
      && (underlying.code == Int(ENOTDIR) || underlying.code == Int(ENOENT))
  }
}
