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

import FirebaseShared
import Foundation

/// The internal steps of the value paths, for the micro-benchmarks in
/// `Benchmarks/Port`. Not API.
@_spi(Benchmarking)
public enum DatabaseBenchmarking {
  /// An opaque database node.
  public struct Node: Sendable {
    let node: FNode
  }

  /// The inbound path for a server payload: JSON bytes to a node.
  public static func parseNode(_ json: Data) throws -> Node {
    let object = try JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed)
    return Node(node: FSnapshotUtilities.nodeFrom(object))
  }

  /// A node from a Foundation value, as writes build them.
  public static func node(from value: Any) -> Node {
    Node(node: FSnapshotUtilities.nodeFrom(value))
  }

  /// `DataSnapshot.value`: the Foundation tree of a node.
  public static func value(of node: Node) -> Any {
    node.node.val()
  }

  /// `DataSnapshot.data(as:)`: the Foundation tree, decoded.
  public static func decode<T: Decodable>(_ type: T.Type, from node: Node,
                                          decoder: Database.Decoder = .init()) throws -> T {
    try decoder.decode(type, from: node.node.val())
  }

  /// The outbound path for a write: a node to JSON bytes.
  public static func serialize(_ node: Node) throws -> Data {
    try JSONSerialization.data(withJSONObject: node.node.val(forExport: true),
                               options: .fragmentsAllowed)
  }

  /// Keys sorted as children are (`FUtilities.compareKey`).
  public static func sortKeys(_ keys: [String]) -> [String] {
    keys.sorted { FUtilities.compareKey($0, $1) == .orderedAscending }
  }

  /// The number of children of a node.
  public static func childCount(of node: Node) -> Int {
    node.node.numChildren()
  }
}
