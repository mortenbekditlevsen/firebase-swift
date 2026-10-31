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

import FirebaseCore
@testable import FirebaseStorage
import Foundation
import Testing

private func rootReference() -> StorageReference {
  let options = FirebaseApp.Options(projectID: "project", googleAppID: "1:123:ios:123ab",
                                    apiKey: "key", clientID: nil, storageBucket: "bucket")
  let app = FirebaseApp(options: options, name: "storage-\(UUID().uuidString)")
  return Storage.storage(app: app).reference()
}

private func label<T>(_ snapshot: StorageTaskSnapshot<T>) -> String {
  switch snapshot.status {
  case .resume: "resume"
  case .progress: "progress"
  case .pause: "pause"
  case .success: "success"
  case .failure: "failure"
  }
}

/// Collects everything a stream delivers until it ends.
private func collect<T>(_ stream: AsyncThrowingStream<StorageTaskSnapshot<T>, Error>) async
  -> [String] {
  var seen: [String] = []
  do {
    for try await snapshot in stream {
      seen.append(label(snapshot))
    }
  } catch {
    seen.append("threw")
  }
  return seen
}

struct StorageTaskTests {
  @Test func downloadURLsEscapeTheBucket() throws {
    // Upstream's testInitializeDownloadURLEscapesBucket: a bucket with "#" or
    // "/" in it must not break or rewrite the URL's path.
    let dictionary = [
      "bucket": "bucket#/o/other",
      "downloadTokens": "12345,ignored",
      "name": "path/to/object",
    ]
    let escapedBucket = StorageUtils.GCSEscapedString(dictionary["bucket"]!)
    let escapedPath = StorageUtils.GCSEscapedString(dictionary["name"]!)
    let url = StorageGetDownloadURLTask.downloadURLFromMetadataDictionary(dictionary,
                                                                         rootReference())
    #expect(url?.absoluteString ==
      "https://firebasestorage.googleapis.com:443/v0/b/\(escapedBucket)/o/\(escapedPath)?alt=media&token=12345")
  }

  @StorageActor
  @Test func newObserversDontRepeatEventsToExistingOnes() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    let first = observer.observe(handle: "first")
    observer.fire(state: .progress)
    _ = observer.observe(handle: "second")
    _ = observer.observe(handle: "third")
    observer.succeed(with: Data())

    // The first observer sees its initial state, the progress and the
    // outcome, once each, however many observers joined later.
    #expect(await collect(first) == ["resume", "progress", "success"])
  }

  @StorageActor
  @Test func lateObserversGetTheOutcomeOnce() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    observer.succeed(with: Data())
    #expect(await collect(observer.observe(handle: "late")) == ["success"])
  }

  @StorageActor
  @Test func finishedTasksStayFinished() async throws {
    let observer = StorageObserver<Data>(reference: rootReference(), file: nil)
    let stream = observer.observe(handle: "observer")
    observer.fire(state: .cancelled(StorageError.cancelled))
    // A fetch completing or reporting progress after `cancel()` changes nothing.
    observer.fire(state: .progress)
    observer.succeed(with: Data())
    observer.setState(.running)

    #expect(await collect(stream) == ["resume", "failure", "threw"])
    guard case .cancelled = observer.base.state else {
      Issue.record("Expected the task to stay cancelled, got \(observer.base.state)")
      return
    }
  }
}
