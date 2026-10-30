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

@testable import FirebaseAuth
import Foundation
import Testing

final class AuthFileStorageTests {
  let base: URL
  let service = "firebase_auth_1:123:ios:123ab"
  let key = "[DEFAULT]_firebase_user"

  init() {
    base = FileManager.default.temporaryDirectory
      .appendingPathComponent("AuthFileStorageTests-\(UUID().uuidString)", isDirectory: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: base)
  }

  private func storage(_ service: String? = nil) -> AuthFileStorage {
    AuthFileStorage(service: service ?? self.service, baseDirectory: base)
  }

  private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? NSNumber).intValue
  }

  @Test func missingKeysReadAsNil() throws {
    #expect(try storage().data(forKey: key) == nil)
  }

  @Test func writesReadsOverwritesAndRemoves() throws {
    let storage = storage()
    try storage.setData(Data("one".utf8), forKey: key)
    #expect(try storage.data(forKey: key) == Data("one".utf8))

    try storage.setData(Data("two".utf8), forKey: key)
    #expect(try storage.data(forKey: key) == Data("two".utf8))

    try storage.removeData(forKey: key)
    #expect(try storage.data(forKey: key) == nil)
    // Removing again is fine.
    try storage.removeData(forKey: key)
  }

  @Test func dataOutlivesTheInstance() throws {
    try storage().setData(Data("kept".utf8), forKey: key)
    #expect(try storage().data(forKey: key) == Data("kept".utf8))
  }

  @Test func servicesAndKeysAreKeptApart() throws {
    let storage = storage()
    let other = self.storage("firebase_auth_1:456:ios:456cd")
    try storage.setData(Data("a".utf8), forKey: key)
    try storage.setData(Data("b".utf8), forKey: "other/app_firebase_user")
    try other.setData(Data("c".utf8), forKey: key)

    #expect(try storage.data(forKey: key) == Data("a".utf8))
    #expect(try storage.data(forKey: "other/app_firebase_user") == Data("b".utf8))
    #expect(try other.data(forKey: key) == Data("c".utf8))
  }

  @Test(arguments: ["..", ".", "a/b", "a:b", "%3A", "æøå", "x y"])
  func namesBecomeSafeFileNames(name: String) {
    let fileName = AuthFileStorage.fileName(for: name)
    #expect(!fileName.isEmpty)
    #expect(!fileName.contains("/"))
    #expect(!fileName.contains("."))
    #expect(fileName.removingPercentEncoding == name)
  }

  @Test func onlyTheOwnerCanReadTheFiles() throws {
    try storage().setData(Data("secret".utf8), forKey: key)

    let directory = base.appendingPathComponent(AuthFileStorage.fileName(for: service))
    let file = directory.appendingPathComponent(AuthFileStorage.fileName(for: key))
    #expect(try permissions(directory) == 0o700)
    #expect(try permissions(file) == 0o600)
  }

  @Test func theDefaultLocationFollowsXDG() {
    let path = AuthFileStorage.defaultBaseDirectory.path
    if let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], dataHome.hasPrefix("/") {
      #expect(path.hasPrefix(dataHome))
    } else {
      #expect(path.hasSuffix(".local/share/firebase-swift/auth"))
    }
  }
}
