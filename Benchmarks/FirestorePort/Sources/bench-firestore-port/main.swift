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

// F1 (BenchmarkScenarios/FirestoreRead.swift) against the port. Keep it in
// step with Benchmarks/Upstream/Sources/bench-firestore-upstream/main.swift.

import BenchmarkScenarios
import FirebaseCore
@_spi(Benchmarking) import FirebaseFirestore
import Foundation

do {
  let options = try FirestoreRead.Options.parse()

  var firebaseOptions = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
  firebaseOptions.projectID = "demo-firestore-bench"
  firebaseOptions.apiKey = "demo-api-key"
  FirebaseApp.configure(options: firebaseOptions)

  // No server: the writes stay in the in-memory cache, and the reads come
  // from it, so the numbers are the SDK's own work.
  let db = Firestore.firestore()
  let settings = db.settings
  settings.cacheSettings = MemoryCacheSettings()
  db.settings = settings
  try await db.disableNetwork()

  let collection = db.collection("items")
  let items = Fixtures.items(count: options.documents).sorted { $0.key < $1.key }
  for chunk in stride(from: 0, to: items.count, by: 500) {
    let batch = db.batch()
    for (key, item) in items[chunk ..< min(chunk + 500, items.count)] {
      try batch.setData(from: item, forDocument: collection.document(key))
    }
    batch.commit { _ in } // Waits for a server, so it never completes.
  }

  try await FirestoreRead.run(
    target: "port",
    options: options,
    query: { try await collection.getDocuments(source: .cache).documents },
    steps: [
      .init("F1-bridge") { _ = FirestoreBenchmarking.copyFields(of: $0) },
      .init("F1-data") { _ = $0.data() },
      .init("F1-data-as") { _ = try $0.data(as: BenchItem.self) },
      // How data(as:) decoded before FirestoreValueDecoder: from data().
      .init("F1-data-as-foundation") {
        _ = try Firestore.Decoder().decode(BenchItem.self, from: $0.data(), in: $0.reference)
      },
    ]
  )
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
