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

/// Stores each key in its own file, for platforms without a keychain.
///
/// Files live in `$XDG_DATA_HOME/firebase-swift/auth/<service>/`, which
/// defaults to `~/.local/share/firebase-swift/auth/<service>/`. Directories
/// this creates are readable only by the owner (0700) and so are the files
/// (0600), because they hold refresh tokens. Writes are atomic, so a crash
/// leaves either the old or the new value.
final class AuthFileStorage: AuthStorage {
  private let directory: URL

  static func storage(identifier: String) -> Self {
    Self(service: identifier)
  }

  convenience init(service: String) {
    self.init(service: service, baseDirectory: Self.defaultBaseDirectory)
  }

  /// - Parameter baseDirectory: Holds a directory per service; tests pass a
  ///   temporary one.
  init(service: String, baseDirectory: URL) {
    directory = baseDirectory.appendingPathComponent(Self.fileName(for: service), isDirectory: true)
  }

  func data(forKey key: String) throws -> Data? {
    let url = fileURL(forKey: key)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }

  func setData(_ data: Data, forKey key: String) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let url = fileURL(forKey: key)
    try data.write(to: url, options: .atomic)
    // The atomic write creates a new file with the default permissions; the
    // directory being 0700 keeps it private until this narrows them.
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  func removeData(forKey key: String) throws {
    let url = fileURL(forKey: key)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  private func fileURL(forKey key: String) -> URL {
    precondition(!key.isEmpty, "The key cannot be empty.")
    return directory.appendingPathComponent(Self.fileName(for: key), isDirectory: false)
  }

  /// Service names and keys contain app names and IDs (with `:` and possibly
  /// `/`), so keep only characters that are safe in a file name everywhere.
  /// Percent-encoding the rest keeps different names apart.
  static func fileName(for name: String) -> String {
    var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
    allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    // Only "%" and disallowed characters get encoded, and the result has no
    // "." so it can't be "." or "..".
    return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
  }

  /// `$XDG_DATA_HOME/firebase-swift/auth`, or `~/.local/share/firebase-swift/auth`
  /// when it isn't set. The spec says to ignore relative paths.
  static var defaultBaseDirectory: URL {
    let dataHome: URL
    if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
       xdgDataHome.hasPrefix("/") {
      dataHome = URL(fileURLWithPath: xdgDataHome, isDirectory: true)
    } else {
      dataHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share", isDirectory: true)
    }
    return dataHome.appendingPathComponent("firebase-swift/auth", isDirectory: true)
  }
}
