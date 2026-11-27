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

/// The visible pending writes by path, so that removing a write doesn't need
/// to compare it with every other one (`FWriteTree.removeWriteId`).
///
/// It answers the two questions upstream's loop over all writes answers:
/// whether a newer write covers a path, and whether any write is at or below
/// it. Both walk only the path's pieces.
struct FWriteIndex {
    private final class Node {
        var children: [String: Node] = [:]
        /// The writes whose path is this node or below it.
        var writesAtOrBelow = 0
        /// The writes that cover this path, oldest first: an overwrite here,
        /// or a merge with a child here.
        var coveringWriteIds: [Int] = []

        var isUnused: Bool {
            writesAtOrBelow == 0 && coveringWriteIds.isEmpty && children.isEmpty
        }
    }

    private var root = Node()

    /// Adds a visible write. Writes are added oldest first.
    mutating func add(_ record: FWriteRecord) {
        var node = root
        node.writesAtOrBelow += 1
        for piece in record.path.pieces[record.path.pieceNum...] {
            let child = node.children[piece] ?? {
                let child = Node()
                node.children[piece] = child
                return child
            }()
            child.writesAtOrBelow += 1
            node = child
        }
        forEachCoveredPath(of: record) { path in
            self.node(at: path, creating: true)!.coveringWriteIds.append(record.writeId)
        }
    }

    /// Removes a write that `add(_:)` added.
    mutating func remove(_ record: FWriteRecord) {
        var node = root
        node.writesAtOrBelow -= 1
        for piece in record.path.pieces[record.path.pieceNum...] {
            node = node.children[piece]!
            node.writesAtOrBelow -= 1
        }
        var touched = [record.path]
        forEachCoveredPath(of: record) { path in
            let node = self.node(at: path, creating: false)!
            if let index = node.coveringWriteIds.lastIndex(of: record.writeId) {
                node.coveringWriteIds.remove(at: index)
            }
            touched.append(path)
        }
        touched.forEach(prune(along:))
    }

    /// Whether a write newer than `writeId` covers `path`: an overwrite at it
    /// or above it, or a merge with a child there.
    func isCovered(_ path: FPath, byWriteNewerThan writeId: Int) -> Bool {
        var node = root
        if node.coveringWriteIds.last ?? Int.min > writeId { return true }
        for piece in path.pieces[path.pieceNum...] {
            guard let child = node.children[piece] else { return false }
            if child.coveringWriteIds.last ?? Int.min > writeId { return true }
            node = child
        }
        return false
    }

    /// Whether any write's path is `path` or below it.
    func hasWrite(atOrBelow path: FPath) -> Bool {
        node(at: path, creating: false).map { $0.writesAtOrBelow > 0 } ?? false
    }

    mutating func removeAll() {
        root = Node()
    }

    private func forEachCoveredPath(of record: FWriteRecord, _ body: (FPath) -> Void) {
        switch record.record {
        case .overwrite:
            body(record.path)
        case let .merge(merge):
            // As upstream's -record:containsPath: reads a merge.
            var paths: [FPath] = []
            merge.enumerateWrites { childPath, _, _ in
                paths.append(record.path.child(childPath))
            }
            paths.forEach(body)
        }
    }

    private func node(at path: FPath, creating: Bool) -> Node? {
        var node = root
        for piece in path.pieces[path.pieceNum...] {
            if let child = node.children[piece] {
                node = child
            } else if creating {
                let child = Node()
                node.children[piece] = child
                node = child
            } else {
                return nil
            }
        }
        return node
    }

    /// Drops the nodes on `path` that no write uses any more, deepest first.
    private func prune(along path: FPath) {
        var nodes: [(parent: Node, piece: String, node: Node)] = []
        var node = root
        for piece in path.pieces[path.pieceNum...] {
            guard let child = node.children[piece] else { break }
            nodes.append((node, piece, child))
            node = child
        }
        for (parent, piece, node) in nodes.reversed() {
            guard node.isUnused else { return }
            parent.children[piece] = nil
        }
    }
}
