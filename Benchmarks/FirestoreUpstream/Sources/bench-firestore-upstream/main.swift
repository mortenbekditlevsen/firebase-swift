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

// F1 (BenchmarkScenarios/FirestoreRead.swift) against upstream. Keep it in
// step with Benchmarks/FirestorePort/Sources/bench-firestore-port/main.swift.

import BenchmarkScenarios
import FirebaseCore
import FirebaseFirestore
import Foundation

do {
  let options = try FirestoreRead.Options.parse()

  let firebaseOptions = FirebaseOptions(googleAppID: "1:123:ios:123ab", gcmSenderID: "123")
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

  func write<Item: Encodable>(_ items: [(key: String, value: Item)], to collection: CollectionReference) throws {
    for chunk in stride(from: 0, to: items.count, by: 500) {
      let batch = db.batch()
      for (key, item) in items[chunk ..< min(chunk + 500, items.count)] {
        try batch.setData(from: item, forDocument: collection.document(key))
      }
      batch.commit { _ in } // Waits for a server, so it never completes.
    }
  }

  let collection = db.collection("items")
  let items = Fixtures.items(count: options.documents).sorted { $0.key < $1.key }
  try write(items, to: collection)
  let typedCollection = db.collection("typed")
  let typedItems = items.map { (key: $0.key, value: TypedItem($0.value, owner: collection.document($0.key))) }
  try write(typedItems, to: typedCollection)

  try await FirestoreRead.run(
    target: "upstream",
    options: options,
    query: { try await collection.getDocuments(source: .cache).documents },
    steps: [
      .init("F1-data") { _ = $0.data() },
      .init("F1-data-as") { _ = try $0.data(as: BenchItem.self) },
    ]
  )
  try await FirestoreRead.run(
    target: "upstream",
    options: options,
    queryScenario: "F1-typed-query",
    query: { try await typedCollection.getDocuments(source: .cache).documents },
    steps: [
      .init("F1-typed-data") { _ = $0.data() },
      .init("F1-typed-data-as") { _ = try $0.data(as: TypedItem.self) },
    ]
  )

  // F2 (BenchmarkScenarios/FirestoreWrite.swift): the same documents written
  // again, up to the core's mutation, in batches that are never committed.
  let encoder = Firestore.Encoder()
  var batch = db.batch()
  let encoded = try items.map { try encoder.encode($0.value) }
  let typedEncoded = try typedItems.map { try encoder.encode($0.value) }
  let references = items.map { collection.document($0.key) }
  let typedReferences = typedItems.map { typedCollection.document($0.key) }
  try FirestoreWrite.run(target: "upstream", options: options, reset: { batch = db.batch() }, steps: [
    .init("F2-encode") { _ = try encoder.encode(items[$0].value) },
    .init("F2-set") { batch.setData(encoded[$0], forDocument: references[$0]) },
    .init("F2-set-from") { try batch.setData(from: items[$0].value, forDocument: references[$0]) },
  ])
  try FirestoreWrite.run(target: "upstream", options: options, reset: { batch = db.batch() }, steps: [
    .init("F2-typed-encode") { _ = try encoder.encode(typedItems[$0].value) },
    .init("F2-typed-set") { batch.setData(typedEncoded[$0], forDocument: typedReferences[$0]) },
    .init("F2-typed-set-from") { try batch.setData(from: typedItems[$0].value, forDocument: typedReferences[$0]) },
  ])
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}

/// BenchItem's name, with four of Firestore's own types (F1-typed).
struct TypedItem: Codable {
  var name: String
  var created: Timestamp
  var updated: Date
  var location: GeoPoint
  var owner: DocumentReference

  init(_ item: BenchItem, owner: DocumentReference) {
    name = item.name
    created = Timestamp(seconds: Int64(item.createdAt / 1000),
                        nanoseconds: Int32(item.createdAt % 1000) * 1_000_000)
    updated = Date(timeIntervalSince1970: Double(item.createdAt) / 1000)
    location = GeoPoint(latitude: item.latitude, longitude: item.longitude)
    self.owner = owner
  }
}
