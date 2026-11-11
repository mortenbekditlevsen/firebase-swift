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
import Foundation
import Testing

/// The storage engine reads what earlier versions (and upstream) wrote: the
/// format the engine wrote with JSONSerialization before it used
/// FJSONScanner and FJSONWriter.
final class FLevelDBCompatibilityTests {
    let engine = FLevelDBStorageEngine(path: "compat-db-\(UUID().uuidString)")

    deinit {
        engine.purgeEverything()
        engine.close()
    }

    /// Stores `node` as the engine did before: `val(forExport: true)`, a key
    /// per leaf, each value serialized by JSONSerialization.
    private func storeTheOldWay(_ node: FNode, at path: FPath) throws {
        func store(_ value: Any, key: String) throws {
            if let dictionary = value as? [String: Any] {
                for (childKey, child) in dictionary {
                    try store(child, key: "\(key)\(childKey)/")
                }
            } else if !(value is NSNull) {
                let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                _ = engine.serverCacheDB.setData(data, forKey: key)
            }
        }
        try store(node.val(forExport: true), key: kFServerCachePrefix + path.toStringWithTrailingSlash())
    }

    /// The server cache's key for `path`.
    private func key(_ path: String) -> String {
        kFServerCachePrefix + FPath(with: path).toStringWithTrailingSlash()
    }

    @Test func cachesWrittenTheOldWayLoad() throws {
        var random = SeededRandom(seed: 0x01D)
        for index in 0 ..< 150 {
            let node = FSnapshotUtilities.nodeFrom(randomJSON(depth: 0, using: &random))
            let path = FPath(with: "old/\(index)")
            try storeTheOldWay(node, at: path)
            #expect(engine.serverCache(atPath: path) == node, "\(node.val(forExport: true))")
        }
    }

    @Test func cachesRoundTrip() {
        var random = SeededRandom(seed: 0x2E3)
        for index in 0 ..< 150 {
            let node = FSnapshotUtilities.nodeFrom(randomJSON(depth: 0, using: &random))
            let path = FPath(with: "new/\(index)")
            engine.updateServerCache(node, atPath: path, merge: false)
            #expect(engine.serverCache(atPath: path) == node, "\(node.val(forExport: true))")
            // The children too, by key.
            if case .children(let children) = node.type, let key = children.keys.first?.key {
                #expect(engine.serverCache(forKeys: [key], atPath: path).getImmediateChild(key)
                    == node.getImmediateChild(key))
            }
        }
    }

    @Test func numbersAndStringsTheOldWayLoadExactly() throws {
        let node = FSnapshotUtilities.nodeFrom([
            "double": 2.47, "small": 1e-7, "big": 12_345_678_901_234_567, "negative": -3,
            "slash": "a/b", "escapes": "quote\" back\\ newline\n", "unicode": "æøå 😀",
            "flag": true, "priority": [".value": "v", ".priority": 2.5],
        ] as [String: Any])
        try storeTheOldWay(node, at: FPath(with: "exact"))
        #expect(engine.serverCache(atPath: FPath(with: "exact")) == node)
    }

    @Test func aLeafAtThePathItselfLoads() throws {
        try storeTheOldWay(.leaf(.string("leaf")), at: FPath(with: "leaf"))
        #expect(engine.serverCache(atPath: FPath(with: "leaf")) == .leaf(.string("leaf")))
    }

    @Test func valuesWithACTerminatorLoad() {
        var value = Data("\"terminated\"".utf8)
        value.append(0)
        _ = engine.serverCacheDB.setData(value, forKey: key("c/x"))
        #expect(engine.serverCache(atPath: FPath(with: "c")).getImmediateChild("x") == .leaf(.string("terminated")))
    }

    @Test func aCorruptValueIsSkipped() {
        _ = engine.serverCacheDB.setData(Data("{not json".utf8), forKey: key("bad/x"))
        _ = engine.serverCacheDB.setData(Data("1".utf8), forKey: key("bad/y"))
        let node = engine.serverCache(atPath: FPath(with: "bad"))
        #expect(node.numChildren() == 1)
        #expect(node.getImmediateChild("y") == .leaf(.int64(1)))
    }

    @Test func userWritesWrittenTheOldWayLoad() throws {
        let overwrite = FSnapshotUtilities.nodeFrom(["a": 1, "t": [".sv": "timestamp"], "p": [".value": "x", ".priority": 1]])
        let merge = FSnapshotUtilities.compoundWriteFromDictionary(["b/c": 2, "gone": NSNull()],
                                                                    withValidationFrom: "test")
        let writes: [[String: Any]] = [
            [kFUserWriteId: 1, kFUserWritePath: "/a/", kFUserWriteOverwrite: overwrite.val(forExport: true)],
            [kFUserWriteId: 2, kFUserWritePath: "/b/", kFUserWriteMerge: merge.valForExport(true)],
        ]
        for write in writes {
            let data = try JSONSerialization.data(withJSONObject: write)
            _ = engine.writesDB.setData(data, forKey: "\(write[kFUserWriteId]!)")
        }
        let loaded = engine.userWrites
        #expect(loaded.map(\.writeId) == [1, 2])
        guard case .overwrite(let node) = loaded.first?.record, case .merge(let loadedMerge) = loaded.last?.record else {
            Issue.record("wrong records: \(loaded)")
            return
        }
        #expect(node == overwrite)
        #expect(loadedMerge.valForExport(true) as NSDictionary == merge.valForExport(true) as NSDictionary)
    }

    @Test func userWritesRoundTripAndACorruptOneIsRemoved() {
        let overwrite = FSnapshotUtilities.nodeFrom(["a": [".value": 1, ".priority": "p"]])
        engine.saveUserOverwrite(overwrite, atPath: FPath(with: "x"), writeId: 7)
        engine.saveUserMerge(FSnapshotUtilities.compoundWriteFromDictionary(["y": 1], withValidationFrom: "test"),
                             atPath: FPath(with: "z"), writeId: 8)
        _ = engine.writesDB.setData(Data("garbage".utf8), forKey: "9")
        let loaded = engine.userWrites
        #expect(loaded.map(\.writeId) == [7, 8])
        if case .overwrite(let node) = loaded.first?.record {
            #expect(node == overwrite)
        } else {
            Issue.record("not an overwrite")
        }
        // The corrupt one is gone.
        #expect(engine.userWrites.count == 2)
        #expect(engine.writesDB.data(forKey: "9") == nil)
    }
}
