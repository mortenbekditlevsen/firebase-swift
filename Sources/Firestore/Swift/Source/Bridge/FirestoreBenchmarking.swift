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

/// The internal steps of reading and writing a document, for the benchmarks in
/// `Benchmarks/FirestorePort`. Not API.
@_spi(Benchmarking)
public enum FirestoreBenchmarking {
  /// The first step of `data()`: copying the core's values into the bridge's
  /// C++ map, without making Swift values of them. Returns the number of
  /// fields, so the copy can't be optimized away.
  public static func copyFields(of snapshot: DocumentSnapshot) -> Int {
    Int(snapshot.cppBridge.data(Int32(ServerTimestampBehavior.none.rawValue)).size())
  }

  /// The first step of `setData(_:)`: copying a document's values into the
  /// bridge's C++ map, before the core parses them. Returns the number of
  /// fields.
  public static func bridgeFields(of data: [String: Any]) -> Int {
    Int(toBridgeFieldValueMap(data).size())
  }
}
