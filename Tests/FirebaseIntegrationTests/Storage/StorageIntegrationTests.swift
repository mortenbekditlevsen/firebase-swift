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

import FirebaseAuth
import FirebaseStorage
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

/// Uses the rules in Tests/Emulator/storage.rules: `public/` is open,
/// `users/{uid}/` is readable and writable only by that signed-in user.
@Suite(.enabled(if: Emulators.storage != nil && Emulators.auth != nil,
                "Needs the Storage and Auth emulators"),
       .timeLimit(.minutes(1)))
struct StorageIntegrationTests {
  /// A folder only this test uses, under the open `public/` path.
  private func scratchRef(_ storage: Storage) -> StorageReference {
    storage.reference().child("public").child(UUID().uuidString)
  }

  @Test func tokensAreNotSentOverHTTPToOtherHosts() async throws {
    let emulatorApp = try EmulatorApp()
    _ = try await emulatorApp.auth.signInAnonymously()
    let storage = Storage.storage(app: emulatorApp.app)
    // A non-routable address: nothing must be sent there.
    storage.useEmulator(withHost: "10.255.255.1", port: 9199)
    storage.maxOperationRetryTime = 2

    let error = await #expect(throws: StorageError.self) {
      _ = try await storage.reference().child("public/file.txt").getMetadata()
    }
    guard case .unauthenticated = error else {
      Issue.record("Expected unauthenticated, got \(String(describing: error))")
      return
    }
  }

  @Test func uploadsAndDownloadsData() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("hello.txt")
    let data = Data("Hello, Storage".utf8)

    let uploaded = try await ref.putData(data)
    #expect(uploaded.size == Int64(data.count))
    #expect(uploaded.name == "hello.txt")
    #expect(uploaded.path == ref.fullPath)

    #expect(try await ref.getData(maxSize: 1024) == data)
  }

  @Test func largeUploadsRoundTrip() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("large.bin")
    // Bigger than one upload chunk, so it takes more than one request.
    let data = Data((0 ..< 3 * 1024 * 1024).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    _ = try await ref.putData(data)
    #expect(try await ref.getData(maxSize: Int64(data.count)) == data)
  }

  @Test func downloadsLargerThanMaxSizeFail() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("big.bin")
    _ = try await ref.putData(Data(count: 2048))

    await #expect(throws: StorageError.self) {
      _ = try await ref.getData(maxSize: 1024)
    }
  }

  @Test func metadataIsStoredAndUpdated() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("doc.json")
    var metadata = StorageMetadata()
    metadata.contentType = "application/json"
    metadata.customMetadata = ["owner": "ada"]
    _ = try await ref.putData(Data("{}".utf8), metadata: metadata)

    var stored = try await ref.getMetadata()
    #expect(stored.contentType == "application/json")
    #expect(stored.customMetadata?["owner"] == "ada")

    stored.customMetadata = ["owner": "grace"]
    stored.cacheControl = "no-cache"
    let updated = try await ref.updateMetadata(stored)
    #expect(updated.customMetadata?["owner"] == "grace")
    #expect(updated.cacheControl == "no-cache")
    #expect(updated.metageneration > stored.metageneration)
  }

  @Test func listsItemsAndPrefixes() async throws {
    let folder = try scratchRef(EmulatorApp().storage())
    for path in ["a.txt", "b.txt", "c.txt", "sub/d.txt"] {
      _ = try await folder.child(path).putData(Data(path.utf8))
    }

    let all = try await folder.listAll()
    #expect(all.items.map(\.name).sorted() == ["a.txt", "b.txt", "c.txt"])
    #expect(all.prefixes.map(\.name) == ["sub"])

    let firstPage = try await folder.list(maxResults: 2)
    #expect(firstPage.items.count == 2)
    let token = try #require(firstPage.pageToken)
    let secondPage = try await folder.list(maxResults: 2, pageToken: token)
    #expect(Set(firstPage.items.map(\.name) + secondPage.items.map(\.name))
      == ["a.txt", "b.txt", "c.txt"])
  }

  @Test func downloadURLsServeTheObject() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("served.txt")
    let data = Data("served".utf8)
    _ = try await ref.putData(data)

    let url = try await ref.downloadURL()
    let (downloaded, _) = try await URLSession.shared.data(from: url)
    #expect(downloaded == data)
  }

  @Test func deletedObjectsAreGone() async throws {
    let ref = try scratchRef(EmulatorApp().storage()).child("gone.txt")
    _ = try await ref.putData(Data("bye".utf8))

    try await ref.delete()
    let error = await #expect(throws: StorageError.self) {
      _ = try await ref.getMetadata()
    }
    guard case .objectNotFound = error else {
      Issue.record("Expected objectNotFound, got \(String(describing: error))")
      return
    }
  }

  @Test func unauthenticatedUploadsToProtectedPathsFail() async throws {
    let storage = try EmulatorApp().storage()
    await #expect(throws: StorageError.self) {
      _ = try await storage.reference().child("users/nobody/file.txt").putData(Data("x".utf8))
    }
  }

  @Test func rulesSeeTheSignedInUser() async throws {
    let emulatorApp = try EmulatorApp()
    let storage = try emulatorApp.storage()
    let uid = try await emulatorApp.auth.signInAnonymously().user.uid

    let mine = storage.reference().child("users/\(uid)/file.txt")
    _ = try await mine.putData(Data("mine".utf8))
    #expect(try await mine.getData(maxSize: 64) == Data("mine".utf8))

    await #expect(throws: StorageError.self) {
      _ = try await storage.reference().child("users/someone-else/file.txt")
        .putData(Data("x".utf8))
    }
  }
}
