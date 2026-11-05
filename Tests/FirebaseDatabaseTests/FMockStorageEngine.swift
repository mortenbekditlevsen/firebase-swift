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

// Ports of upstream's test helpers FMockStorageEngine, FTestCachePolicy and
// FTestClock (FirebaseDatabase/Tests/Helpers, 13.1.1).

@testable import FirebaseDatabase
import Foundation

/// An in-memory storage engine.
final class FMockStorageEngine: FStorageEngine {
  private(set) var closed = false
  private var userWritesDict: [Int: FWriteRecord] = [:]
  private var serverCache = FCompoundWrite.emptyWrite
  private var trackedQueries: [Int: FTrackedQuery] = [:]
  private var trackedQueryKeys: [Int: Set<String>] = [:]

  func close() {
    closed = true
  }

  func saveUserOverwrite(_ node: FNode, atPath path: FPath, writeId: Int) {
    userWritesDict[writeId] = FWriteRecord(path: path, overwrite: node, writeId: writeId,
                                           visible: true)
  }

  func saveUserMerge(_ merge: FCompoundWrite, atPath path: FPath, writeId: Int) {
    userWritesDict[writeId] = FWriteRecord(path: path, merge: merge, writeId: writeId)
  }

  func removeUserWrite(_ writeId: Int) {
    userWritesDict.removeValue(forKey: writeId)
  }

  func removeAllUserWrites() {
    userWritesDict.removeAll()
  }

  var userWrites: [FWriteRecord] {
    userWritesDict.values.sorted { $0.writeId < $1.writeId }
  }

  func serverCache(atPath path: FPath) -> FNode {
    serverCache.childCompoundWriteAtPath(path).applyToNode(.empty)
  }

  func serverCache(forKeys keys: Set<String>, atPath path: FPath) -> FNode {
    var children = FNode.empty
    let fullNode = serverCache.childCompoundWriteAtPath(path).applyToNode(.empty)
    for key in keys {
      children = children.updateImmediateChild(key, withNewChild: fullNode.getImmediateChild(key))
    }
    return children
  }

  func updateServerCache(_ node: FNode, atPath path: FPath, merge: Bool) {
    if merge {
      node.enumerateChildren { key, childNode, _ in
        self.serverCache = self.serverCache.addWrite(childNode,
                                                     atPath: path.child(fromString: key))
      }
    } else {
      serverCache = serverCache.addWrite(node, atPath: path)
    }
  }

  func updateServerCache(merge: FCompoundWrite, atPath path: FPath) {
    serverCache = serverCache.addCompoundWrite(merge, atPath: path)
  }

  var serverCacheEstimatedSizeInBytes: Int {
    let data = serverCache.applyToNode(.empty).val(forExport: true)
    return (try? JSONSerialization.data(withJSONObject: data, options: [.fragmentsAllowed]))?
      .count ?? 0
  }

  func pruneCache(_ pruneForest: FPruneForest, atPath prunePath: FPath) {
    serverCache.enumerateWrites { absolutePath, node, _ in
      precondition(prunePath == absolutePath || !absolutePath.contains(prunePath),
                   "Pruning at \(prunePath) but we found data higher up!")
      if prunePath.contains(absolutePath) {
        let relativePath = FPath.relativePath(from: prunePath, to: absolutePath)
        if pruneForest.shouldPruneUnkeptDescendants(atPath: relativePath) {
          var newCache = FCompoundWrite.emptyWrite
          pruneForest.child(atPath: relativePath).enumarateKeptNodes { keepPath in
            newCache = newCache.addWrite(node.getChild(keepPath), atPath: keepPath)
          }
          self.serverCache = self.serverCache.removeWriteAtPath(absolutePath)
            .addCompoundWrite(newCache, atPath: absolutePath)
        } else {
          // NOTE: This is technically a valid scenario (e.g. you ask to prune at / but only want
          // to prune 'foo' and 'bar' and ignore everything else).  But currently our pruning will
          // explicitly prune or keep everything we know about, so if we hit this it means our
          // tracked queries and the server cache are out of sync.
          precondition(pruneForest.shouldKeepPath(relativePath),
                       "We have data at \(relativePath) that is neither pruned nor kept.")
        }
      }
    }
  }

  func loadTrackedQueries() -> [FTrackedQuery] {
    Array(trackedQueries.values)
  }

  func removeTrackedQuery(_ queryId: Int) {
    trackedQueries.removeValue(forKey: queryId)
    trackedQueryKeys.removeValue(forKey: queryId)
  }

  func saveTrackedQuery(_ query: FTrackedQuery) {
    trackedQueries[query.queryId] = query
  }

  func setTrackedQueryKeys(_ keys: Set<String>, forQueryId queryId: Int) {
    trackedQueryKeys[queryId] = keys
  }

  func updateTrackedQueryKeys(addedKeys added: Set<String>, removedKeys removed: Set<String>,
                              forQueryId queryId: Int) {
    trackedQueryKeys[queryId] = trackedQueryKeysForQuery(queryId).subtracting(removed)
      .union(added)
  }

  func trackedQueryKeysForQuery(_ queryId: Int) -> Set<String> {
    trackedQueryKeys[queryId] ?? []
  }
}

/// Prunes only when told to.
final class FTestCachePolicy: FCachePolicy {
  let percentOfQueriesToPruneAtOnce: Double
  let maxNumberOfQueriesToKeep: Int
  private var pruneNext = false

  init(percent: Double, maxQueries: Int) {
    percentOfQueriesToPruneAtOnce = percent
    maxNumberOfQueriesToKeep = maxQueries
  }

  func pruneOnNextCheck() {
    pruneNext = true
  }

  func shouldPruneCache(size cacheSize: Int, numberOfTrackedQueries numTrackedQueries: Int)
    -> Bool {
    if pruneNext {
      pruneNext = false
      return true
    } else {
      return false
    }
  }

  func shouldCheckCacheSize(_ serverUpdatesSinceLastCheck: Int) -> Bool {
    true
  }
}

/// A clock that only moves when told to.
final class FTestClock: FClock, @unchecked Sendable {
  private(set) var currentTime: TimeInterval = 0.001

  func tick() {
    currentTime += 0.001
  }
}
