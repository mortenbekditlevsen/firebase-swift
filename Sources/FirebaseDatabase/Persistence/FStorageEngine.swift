// Copyright 2017 Google LLC
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

import Foundation

protocol FStorageEngine {
    func close()
    func saveUserOverwrite(_ node: FNode, atPath path: FPath, writeId: Int)
    func saveUserMerge(_ merge: FCompoundWrite, atPath path: FPath, writeId: Int)
    func removeUserWrite(_ writeId: Int)
    func removeAllUserWrites()
    var userWrites: [FWriteRecord] { get }
    func serverCache(atPath path: FPath) -> FNode
    func serverCache(forKeys keys: Set<String>, atPath path: FPath) -> FNode
    func updateServerCache(_ node: FNode, atPath path: FPath, merge: Bool)
    func updateServerCache(merge: FCompoundWrite, atPath path: FPath)
    var serverCacheEstimatedSizeInBytes: Int { get }
    func pruneCache(_ pruneForest: FPruneForest, atPath path: FPath)
    func loadTrackedQueries() -> [FTrackedQuery]
    func removeTrackedQuery(_ queryId: Int)
    func saveTrackedQuery(_ query: FTrackedQuery)
    func setTrackedQueryKeys(_ keys: Set<String>, forQueryId: Int)
    func updateTrackedQueryKeys(addedKeys added: Set<String>, removedKeys removed: Set<String>, forQueryId queryId: Int)
    func trackedQueryKeysForQuery(_ queryId: Int) -> Set<String>
}
