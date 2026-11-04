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

@testable import FirebaseFirestore
import XCTest

/// Realtime pipelines are internal upstream and have no Swift tests there;
/// these cover the port's listener bridge.
final class RealtimePipelineTests: FSTIntegrationTestCase {
  override func setUpWithError() throws {
    try super.setUpWithError()
    if FSTIntegrationTestCase.backendEdition() == .standard {
      throw XCTSkip("Realtime pipelines need the Enterprise edition")
    }
  }

  func testListenerGetsResultsAndChanges() async throws {
    let collection = collectionRef(withDocuments: [
      "a": ["n": 1],
      "b": ["n": 5],
    ])
    let pipeline = db.realtimePipeline().collection(collection)
      .where(Field("n").greaterThan(2))
    var snapshots = pipeline.snapshotStream().makeAsyncIterator()

    let first = try await next(&snapshots) { ids($0) == ["b"] }
    XCTAssertEqual(first.results().first?.get("n") as? Int, 5)

    try await collection.document("c").setData(["n": 7])
    let second = try await next(&snapshots) { ids($0) == ["b", "c"] }
    let added = second.changes.filter { $0.type == .added }.map(\.result.id)
    XCTAssertEqual(added, ["c"])

    try await collection.document("b").setData(["n": 0])
    let third = try await next(&snapshots) { ids($0) == ["c"] }
    XCTAssertEqual(third.changes.filter { $0.type == .removed }.map(\.result.id), ["b"])
  }

  private func ids(_ snapshot: RealtimePipeline.Snapshot) -> Set<String> {
    Set(snapshot.results().compactMap(\.id))
  }

  /// The next snapshot that `matches`, skipping the ones before it (from the
  /// cache, say).
  private func next(_ snapshots: inout AsyncThrowingStream<RealtimePipeline.Snapshot, Error>
    .AsyncIterator,
    where matches: (RealtimePipeline.Snapshot) -> Bool) async throws
    -> RealtimePipeline.Snapshot {
    for _ in 0 ..< 10 {
      guard let snapshot = try await snapshots.next() else { break }
      if matches(snapshot) { return snapshot }
    }
    XCTFail("No matching snapshot")
    throw CancellationError()
  }
}
