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
    try FJSONScanner.withScanner(json) { scanner in
      Node(node: try scanner.readNode())
    }
  }

  /// The inbound path before P4: JSONSerialization, then `nodeFrom`.
  public static func parseNodeWithJSONSerialization(_ json: Data) throws -> Node {
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

  /// `DataSnapshot.data(as:)`: the node, decoded (FNodeDecoder).
  public static func decode<T: Decodable>(_ type: T.Type, from node: Node,
                                          decoder: Database.Decoder = .init()) throws -> T {
    try FNodeDecoder(decoder).decode(type, from: node.node)
  }

  /// `DataSnapshot.data(as:)` before P5: the Foundation tree, decoded.
  public static func decodeFoundationValue<T: Decodable>(_ type: T.Type, from node: Node,
                                                         decoder: Database.Decoder = .init()) throws -> T {
    try decoder.decode(type, from: node.node.val())
  }

  /// `setValue(from:)`: a value, encoded to a node (FNodeEncoder).
  public static func encode<T: Encodable>(_ value: T, encoder: Database.Encoder = .init()) throws -> Node {
    Node(node: try FNodeEncoder(encoder).encode(value))
  }

  /// `setValue(from:)` before P5: FirebaseDataEncoder, then `nodeFrom`.
  public static func encodeFoundationValue<T: Encodable>(_ value: T,
                                                         encoder: Database.Encoder = .init()) throws -> Node {
    Node(node: FSnapshotUtilities.nodeFrom(try encoder.encode(value)))
  }

  /// The outbound path for a write: a node to JSON bytes.
  public static func serialize(_ node: Node) throws -> Int {
    var writer = FJSONWriter()
    try writer.write(node.node)
    return writer.buffer.readableBytes
  }

  /// The outbound path before P4: `val(forExport:)`, then JSONSerialization.
  public static func serializeWithJSONSerialization(_ node: Node) throws -> Data {
    try JSONSerialization.data(withJSONObject: node.node.val(forExport: true),
                               options: .fragmentsAllowed)
  }

  /// Keys sorted as children are (`FUtilities.compareKey`).
  public static func sortKeys(_ keys: [String]) -> [String] {
    keys.sorted { FUtilities.compareKey($0, $1) == .orderedAscending }
  }

  /// A listen's simple hash of the cached data (`FNode.dataHash()`).
  public static func dataHash(of node: Node) -> String {
    node.node.dataHash()
  }

  /// Parses `json` and hashes the node: a listen's first hash of new data.
  public static func parseAndHash(_ json: Data) throws -> String {
    try parseNode(json).node.dataHash()
  }

  /// The node with one leaf below `path` replaced, as a server update or a
  /// write does.
  public static func updating(_ node: Node, at path: String, to value: Int) -> Node {
    Node(node: node.node.updateChild(FPath(with: path), withNewChild: .leaf(.int64(Int64(value)))))
  }

  /// Bytes a node takes inline (in its parent's children).
  public static var nodeStride: Int { MemoryLayout<FNode>.stride }

  /// A listen's compound hash of the cached data, sent when it's large.
  public static func compoundHashCount(of node: Node) -> Int {
    FCompoundHash.fromNode(node: node.node).hashes.count
  }

  /// The size estimate that decides whether a listen sends the compound hash.
  public static func estimatedSize(of node: Node) -> Int {
    FSnapshotUtilities.estimateSerializedNodeSize(node.node)
  }

  /// S4b's pending writes without the network: `count` overwrites of sibling
  /// locations, then their acknowledgements, oldest first. Returns how many
  /// removals were visible.
  public static func writeTreeAddAndRemove(count: Int) -> Int {
    let tree = FWriteTree()
    let parent = FPath(with: "public/bench/s4b")
    for id in 0 ..< count {
      tree.addOverwriteAtPath(parent.child(fromString: "item\(id)"), newData: .leaf(.int64(Int64(id))),
                              writeId: id, isVisible: true)
    }
    var visible = 0
    for id in 0 ..< count where tree.removeWriteId(id) {
      visible += 1
    }
    return visible
  }

  /// The number of children of a node.
  public static func childCount(of node: Node) -> Int {
    node.node.numChildren()
  }
}
