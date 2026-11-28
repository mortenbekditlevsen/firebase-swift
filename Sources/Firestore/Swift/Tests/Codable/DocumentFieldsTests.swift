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

// data() makes the document's fields from the core's values (DocumentFields);
// these compare it with the conversion it replaced, through BridgeFieldValue,
// value for value and type for type.

import FirebaseCore
@testable import FirebaseFirestore
import Foundation
import Testing

@Suite("DocumentFields")
struct DocumentFieldsTests {
  /// Every kind of value, with server timestamps not set yet.
  @Test(arguments: FirestoreValueDecoderTests.behaviors)
  func everyKindOfValueAsBefore(behavior: ServerTimestampBehavior) async throws {
    let snapshot = try await FirestoreValueDecoderTests.snapshot()
    expectSame(snapshot, behavior)
    for (field, _) in FirestoreValueDecoderTests.values {
      #expect(snapshot.data(with: behavior)?[field] != nil, "\(field)")
    }
  }

  /// Values of every kind inside maps and arrays, and server timestamps not
  /// set yet inside a map.
  @Test(arguments: FirestoreValueDecoderTests.behaviors)
  func nestedValuesAsBefore(behavior: ServerTimestampBehavior) async throws {
    let db = try await FirestoreValueDecoderTests.offlineFirestore()
    let document = db.document("coll/nested")
    var values = FirestoreValueDecoderTests.values
    values["reference"] = db.document("coll/other")
    document.setData([
      "map": values.merging(["inner": values, "pending": 1]) { $1 },
      "array": Array(values.values.filter { !($0 is [Any]) }),
      "arrayOfMaps": [values, ["a": [values]]],
    ]) { _ in }
    document.updateData(["map.pending": FieldValue.serverTimestamp()]) { _ in }
    let snapshot = try await document.getDocument(source: .cache)
    expectSame(snapshot, behavior)
  }

  @Test func missingDocumentsHaveNoData() async throws {
    let db = try await FirestoreValueDecoderTests.offlineFirestore()
    let document = db.document("coll/missing")
    document.delete { _ in }
    let snapshot = try await document.getDocument(source: .cache)
    #expect(snapshot.data() == nil)
  }

  private func expectSame(_ snapshot: DocumentSnapshot, _ behavior: ServerTimestampBehavior,
                          sourceLocation: SourceLocation = #_sourceLocation) {
    let before = fromBridgeFieldValueMap(
      snapshot.cppBridge.data(Int32(behavior.rawValue)), firestore: snapshot.firestore
    )
    let now = snapshot.data(with: behavior) ?? [:]
    #expect(!before.isEmpty, sourceLocation: sourceLocation)
    for key in Set(before.keys).union(now.keys) {
      #expect(same(now[key] as Any, before[key] as Any), "\(key), \(behavior)",
              sourceLocation: sourceLocation)
    }
  }
}

/// Whether two of data()'s values are the same, of the same type.
private func same(_ a: Any, _ b: Any) -> Bool {
  switch (a, b) {
  case let (a as [String: Any], b as [String: Any]):
    return a.count == b.count && a.allSatisfy { key, value in b[key].map { same(value, $0) } ?? false }
  case let (a as [Any], b as [Any]):
    return a.count == b.count && zip(a, b).allSatisfy { same($0, $1) }
  default:
    break
  }
  guard type(of: a) == type(of: b) else { return false }
  if let a = a as? NSNumber, let b = b as? NSNumber {
    // By kind and value, NaNs included.
    return String(cString: a.objCType) == String(cString: b.objCType) && a.description == b.description
  }
  if let a = a as? AnyHashable, let b = b as? AnyHashable {
    return a == b
  }
  return String(reflecting: a) == String(reflecting: b)
}
