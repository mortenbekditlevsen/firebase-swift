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

import SortedCollections

/// Builds a node from its leaves, as the server cache stores them: one per
/// path ("a/b/"), in key order, so a node's leaves come one after another.
/// A node's priority is the leaf ".priority" below it, and a leaf with a
/// priority stores its value at ".value" (as `val(forExport: true)` has them).
struct FLeafTreeBuilder {
    private struct Level {
        var name: String
        var children: [FChild] = []
        var sorted = true
        var priority: FNode?
        var value: LeafValue?

        mutating func add(_ name: String, _ node: FNode) {
            switch name {
            case kPayloadPriority:
                priority = node.isEmpty ? nil : node
            case kPayloadValue:
                if case .leaf(let leaf) = node.type { value = leaf }
            default:
                guard !node.isEmpty, name.utf8.first != UInt8(ascii: ".") else { return }
                let key = KeyIndex(key: name)
                if let last = children.last?.key {
                    if last == key {
                        // A leaf and children at one path: the later wins.
                        children[children.count - 1] = FChild(key: key, value: node)
                        return
                    }
                    if !(last < key) { sorted = false }
                }
                children.append(FChild(key: key, value: node))
            }
        }

        consuming func node() -> FNode {
            if let value {
                return .leaf(value, priority: priority)
            }
            guard !children.isEmpty else { return .empty }
            if !sorted {
                children.sort { $0.key < $1.key }
            }
            return .children(FChildren(sortedChildren: children), priority: priority)
        }
    }

    /// The levels from the root to the current node.
    private var levels = [Level(name: "")]
    /// A leaf at the root path itself.
    private var rootLeaf: FNode?

    /// Adds a leaf at `path`: the key's names below the root, each ending in
    /// "/", as UTF-8 ("" for the root itself).
    mutating func add(path: Span<UInt8>, leaf: FNode) {
        guard rootLeaf == nil else { return }
        if path.isEmpty {
            // The root is a leaf: it has no children (as before, the rest is ignored).
            rootLeaf = leaf
            return
        }
        // The levels open now that are on this path stay open.
        var depth = 0
        var start = 0
        var names: [String] = []
        var index = 0
        while index < path.count {
            if path[index] == UInt8(ascii: "/") {
                let level = depth + 1
                if names.isEmpty, level < levels.count, Self.equal(path, start ..< index, levels[level].name) {
                    depth = level
                } else {
                    names.append(Self.string(path, start ..< index))
                }
                start = index + 1
            }
            index += 1
        }
        if start < path.count {
            // No trailing "/".
            names.append(Self.string(path, start ..< path.count))
        }
        guard let leafName = names.popLast() else {
            // The path is a level that's open, whose children came first (not
            // in key order, where a path comes before the paths below it):
            // the leaf replaces them.
            let name = levels[depth].name
            close(to: depth - 1)
            levels[levels.count - 1].add(name, leaf)
            return
        }
        close(to: depth)
        for name in names {
            levels.append(Level(name: name))
        }
        levels[levels.count - 1].add(leafName, leaf)
    }

    /// The node of the leaves added.
    mutating func finish() -> FNode {
        if let rootLeaf { return rootLeaf }
        close(to: 0)
        return levels.removeLast().node()
    }

    /// Closes the levels below `depth`, adding each to its parent.
    private mutating func close(to depth: Int) {
        while levels.count > depth + 1 {
            let level = levels.removeLast()
            let name = level.name
            levels[levels.count - 1].add(name, level.node())
        }
    }

    private static func equal(_ bytes: Span<UInt8>, _ range: Range<Int>, _ string: String) -> Bool {
        var index = range.lowerBound
        for byte in string.utf8 {
            guard index < range.upperBound, bytes[index] == byte else { return false }
            index += 1
        }
        return index == range.upperBound
    }

    private static func string(_ bytes: Span<UInt8>, _ range: Range<Int>) -> String {
        unsafe bytes.withUnsafeBufferPointer { buffer in
            unsafe String(decoding: UnsafeBufferPointer(rebasing: buffer[range]), as: UTF8.self)
        }
    }
}
