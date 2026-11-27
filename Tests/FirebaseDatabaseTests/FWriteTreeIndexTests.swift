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

@testable import FirebaseDatabase
import Testing

/// `FWriteTree.removeWriteId` answers its questions from an index of the
/// writes by path, where upstream compares the removed write with every other
/// one. These tests run both on the same random writes.
@Suite struct FWriteTreeIndexTests {
    @Test(arguments: 0 ..< 300)
    func behavesAsUpstreamsLoop(seed: Int) {
        var random = SplitMix64(seed: UInt64(seed))
        let tree = FWriteTree()
        let reference = ReferenceWriteTree()
        var pending: [Int] = []
        var nextId = 0

        for _ in 0 ..< 150 {
            let choice = random.next(below: 10)
            if choice < 4 || pending.isEmpty {
                let path = randomPath(&random, maxDepth: 3)
                let node = FNode.leaf(.int64(Int64(nextId)))
                let visible = random.next(below: 5) != 0
                tree.addOverwriteAtPath(path, newData: node, writeId: nextId, isVisible: visible)
                reference.addOverwrite(path, node, writeId: nextId, visible: visible)
                pending.append(nextId)
                nextId += 1
            } else if choice < 6 {
                let path = randomPath(&random, maxDepth: 2)
                var merge = FCompoundWrite.emptyWrite
                for _ in 0 ..< 1 + random.next(below: 3) {
                    let child = randomPath(&random, maxDepth: 2, minDepth: 1)
                    merge = merge.addWrite(.leaf(.int64(Int64(nextId))), atPath: child)
                }
                tree.addMergeAtPath(path, changedChildren: merge, writeId: nextId)
                reference.addMerge(path, merge, writeId: nextId)
                pending.append(nextId)
                nextId += 1
            } else {
                // Mostly the oldest, as the server acknowledges; sometimes any.
                let position = random.next(below: 3) == 0 ? random.next(below: pending.count) : 0
                let writeId = pending.remove(at: position)
                #expect(tree.removeWriteId(writeId) == reference.removeWriteId(writeId),
                        "seed \(seed), removing \(writeId)")
            }
            #expect(tree.visibleWrites == reference.visibleWrites, "seed \(seed)")
            #expect(tree.allWrites == reference.allWrites, "seed \(seed)")
        }
        for writeId in 0 ..< nextId {
            #expect(tree.writeForId(writeId) == reference.allWrites.first { $0.writeId == writeId })
        }
        #expect(tree.removeAllWrites() == reference.allWrites)
        #expect(tree.allWrites.isEmpty)
    }

    /// Thousands of sibling writes, acknowledged oldest first, as a burst of
    /// sets gets acknowledged: each removal is visible and needs no rebuild.
    @Test func acknowledgesManySiblingWrites() {
        let tree = FWriteTree()
        let parent = FPath(with: "items")
        for id in 0 ..< 20_000 {
            tree.addOverwriteAtPath(parent.child(fromString: "item\(id)"), newData: .leaf(.int64(Int64(id))),
                                    writeId: id, isVisible: true)
        }
        var visible = 0
        for id in 0 ..< 20_000 where tree.removeWriteId(id) {
            visible += 1
        }
        #expect(visible == 20_000)
        #expect(tree.allWrites.isEmpty)
        #expect(tree.visibleWrites == .emptyWrite)
    }

    private func randomPath(_ random: inout SplitMix64, maxDepth: Int, minDepth: Int = 0) -> FPath {
        let names = ["a", "b", "c"]
        let depth = minDepth + random.next(below: maxDepth - minDepth + 1)
        return FPath(with: (0 ..< depth).map { _ in names[random.next(below: names.count)] }.joined(separator: "/"))
    }
}

/// Upstream's FWriteTree (13.2.0), as far as removing a write goes: it
/// compares the removed write with every other pending one.
private final class ReferenceWriteTree {
    var visibleWrites = FCompoundWrite.emptyWrite
    var allWrites: [FWriteRecord] = []

    func addOverwrite(_ path: FPath, _ node: FNode, writeId: Int, visible: Bool) {
        allWrites.append(FWriteRecord(path: path, overwrite: node, writeId: writeId, visible: visible))
        if visible {
            visibleWrites = visibleWrites.addWrite(node, atPath: path)
        }
    }

    func addMerge(_ path: FPath, _ merge: FCompoundWrite, writeId: Int) {
        allWrites.append(FWriteRecord(path: path, merge: merge, writeId: writeId))
        visibleWrites = visibleWrites.addCompoundWrite(merge, atPath: path)
    }

    func removeWriteId(_ writeId: Int) -> Bool {
        let index = allWrites.firstIndex { $0.writeId == writeId }!
        let writeToRemove = allWrites.remove(at: index)
        var removedWriteWasVisible = writeToRemove.visible
        var removedWriteOverlapsWithOtherWrites = false
        var i = allWrites.count - 1
        while removedWriteWasVisible, i >= 0 {
            let currentWrite = allWrites[i]
            if currentWrite.visible {
                if i >= index, record(currentWrite, containsPath: writeToRemove.path) {
                    removedWriteWasVisible = false
                } else if writeToRemove.path.contains(currentWrite.path) {
                    removedWriteOverlapsWithOtherWrites = true
                }
            }
            i -= 1
        }
        if !removedWriteWasVisible {
            return false
        } else if removedWriteOverlapsWithOtherWrites {
            visibleWrites = allWrites.reduce(FCompoundWrite.emptyWrite) { tree, write in
                switch write.record {
                case let .overwrite(node): tree.addWrite(node, atPath: write.path)
                case let .merge(merge): tree.addCompoundWrite(merge, atPath: write.path)
                }
            }
            return true
        } else {
            if case let .merge(merge) = writeToRemove.record {
                merge.enumerateWrites { path, _, _ in
                    self.visibleWrites = self.visibleWrites.removeWriteAtPath(writeToRemove.path.child(path))
                }
            } else {
                visibleWrites = visibleWrites.removeWriteAtPath(writeToRemove.path)
            }
            return true
        }
    }

    private func record(_ record: FWriteRecord, containsPath path: FPath) -> Bool {
        switch record.record {
        case let .merge(merge):
            var contains = false
            merge.enumerateWrites { childPath, _, stop in
                contains = record.path.child(childPath).contains(path)
                stop = contains
            }
            return contains
        case .overwrite:
            return record.path.contains(path)
        }
    }
}

/// A seedable generator, so a failing seed can be rerun.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
