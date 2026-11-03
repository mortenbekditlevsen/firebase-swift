// Copyright 2022 Google LLC
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

// MARK: This file is used to evaluate the experience of using Firebase APIs in Swift.

import Foundation
import XCTest

import FirebaseCore
import FirebaseStorage

final class StorageAPITests: XCTestCase {
  func StorageAPIs() {
    let app = FirebaseApp.app()
    _ = Storage.storage()
    _ = Storage.storage(app: app!)
    _ = Storage.storage(url: "my-url")
    let storage = Storage.storage(app: app!, url: "my-url")
    _ = storage.app
    storage.maxUploadRetryTime = storage.maxUploadRetryTime + 1
    storage.maxDownloadRetryTime = storage.maxDownloadRetryTime + 1
    storage.maxOperationRetryTime = storage.maxOperationRetryTime + 1
    // Port note: no callbackQueue; the API is async.
    _ = storage.reference()
    _ = storage.reference(forURL: "my-url")
    _ = storage.reference(withPath: "path")
    storage.useEmulator(withHost: "host", port: 123)
  }

  func StorageReferenceApis() {
    var ref = Storage.storage().reference()
    _ = ref.storage
    _ = ref.bucket
    _ = ref.fullPath
    _ = ref.name

    ref = ref.root()
    ref = ref.parent()!
    ref = ref.child("path")

    let metadata = StorageMetadata()

    // Port note: the API is async only; upstream's completion-handler forms
    // are left out here and below.
    _ = ref.putData(Data())
    _ = ref.putData(Data(), metadata: metadata)
    let file = URL(string: "my-url")!
    _ = ref.putFile(from: file)
    _ = ref.putFile(from: file, metadata: metadata)
    ref.write(toFile: file)

    Task {
      let _: StorageMetadata = try await ref.putData(Data(), metadata: metadata)
      let _: StorageMetadata = try await ref.putFile(from: file, metadata: metadata)
      _ = try await ref.getData(maxSize: 122)
      _ = try await ref.downloadURL()
      let _: URL = try await ref.write(toFile: file)
      _ = try await ref.listAll()
      _ = try await ref.list(maxResults: 123)
      _ = try await ref.list(maxResults: 123, pageToken: "pageToken")
      _ = try await ref.getMetadata()
      _ = try await ref.updateMetadata(metadata)
      try await ref.delete()
    }
  }

  #if Firebase9Breaking
    func StorageConstantsTypedefs() {
      var _: StorageHandle
      var _: StorageVoidDataError
      var _: StorageVoidError
      var _: StorageVoidMetadata
      var _: StorageVoidMetadataError
      var _: StorageVoidSnapshot
      var _: StorageVoidURLError
    }
  #endif

  func testStorageConstantsGlobal() {
    XCTAssertEqual(StorageErrorDomain, "FIRStorageErrorDomain")
  }

  func StorageListResultApis(result: StorageListResult) {
    _ = result.prefixes
    _ = result.items
    _ = result.pageToken
  }

  // Port note: StorageTaskStatus is generic over the task's result, which
  // `.success` carries (as `.failure` carries the error); there's no `.unknown`.
  func taskStatuses(status: StorageTaskStatus<Data>) -> StorageTaskStatus<Data> {
    switch status {
    case .resume: return status
    case .progress: return status
    case .pause: return status
    case .success: return status
    case .failure: return status
    }
  }

  func errorCodes(code: StorageErrorCode) -> StorageErrorCode {
    switch code {
    case .unknown: return code
    case .objectNotFound: return code
    case .bucketNotFound: return code
    case .projectNotFound: return code
    case .quotaExceeded: return code
    case .unauthenticated: return code
    case .unauthorized: return code
    case .retryLimitExceeded: return code
    case .nonMatchingChecksum: return code
    case .downloadSizeExceeded: return code
    case .cancelled: return code
    case .invalidArgument: return code
    case .bucketMismatch: return code
    case .internalError: return code
    case .pathError: return code
    @unknown default:
      fatalError()
    }
  }

  func storageMetadataApis() {
    let metadata = StorageMetadata()
    _ = metadata.bucket
    _ = metadata.cacheControl
    _ = metadata.contentDisposition
    _ = metadata.contentEncoding
    _ = metadata.contentLanguage
    _ = metadata.contentType
    _ = metadata.md5Hash
    _ = metadata.generation
    _ = metadata.customMetadata
    _ = metadata.metageneration
    _ = metadata.name
    _ = metadata.path
    _ = metadata.size
    _ = metadata.timeCreated
    _ = metadata.updated
    _ = metadata.dictionaryRepresentation()
    _ = metadata.isFile
    _ = metadata.isFolder
  }

  // Port note: tasks are observed through an AsyncThrowingStream, which ends
  // when the task does; there are no per-status observers to remove.
  func StorageObservableTaskApis(ref: StorageReference) async throws {
    let task: StorageDownloadTask = ref.write(toFile: URL(string: "url")!)
    let (_ /* handle */, snapshots) = await task.observe()
    for try await snapshot in snapshots {
      _ = snapshot
    }
  }

  func StorageTaskManagementApis(task: StorageTaskManagement) {
    task.enqueue()
    // Port note: pause, cancel and resume are required, not optional.
    task.pause()
    task.cancel()
    task.resume()
  }

  // Port note: snapshots are generic over the task's result, and carry the
  // task's state (`base`) instead of the task.
  func StorageTaskSnapshotApis(snapshot: StorageTaskSnapshot<Data>) {
    _ = snapshot.base
    _ = snapshot.metadata
    _ = snapshot.reference
    _ = snapshot.progress
    _ = snapshot.error
    _ = snapshot.status
  }
}
