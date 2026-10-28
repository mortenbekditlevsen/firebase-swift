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

class FChildChangeAccumulator {
    private var changeMap: [String: FChange] = [:]
    var changes: [FChange] { Array(changeMap.values) }
    init() {}
    func trackChildChange(_ change: FChange) {
        let type = change.type
        guard let childKey = change.childKey else { return }
        assert(type == .childAdded || type == .childChanged || type == .childRemoved, "Only child changes supported for tracking.")
        assert(childKey != ".priority", "Changes not tracked on priority")
        guard let oldChange = changeMap[childKey] else {
            changeMap[childKey] = change
            return
        }
        let oldType = oldChange.type
        switch (type, oldType) {
        case (.childAdded, .childRemoved):
            let newChange = FChange(type: .childChanged,
                                    indexedNode: change.indexedNode,
                                    childKey: childKey,
                                    oldIndexedNode: oldChange.indexedNode)
            changeMap[childKey] = newChange
        case (.childRemoved, .childAdded):
            changeMap.removeValue(forKey: childKey)

        case (.childRemoved, .childChanged):
            let newChange = FChange(type: .childRemoved,
                                    indexedNode: oldChange.oldIndexedNode!,
                                    childKey: childKey)
            changeMap[childKey] = newChange

        case (.childChanged, .childAdded):
            let newChange = FChange(type: .childAdded,
                                    indexedNode: change.indexedNode,
                                    childKey: childKey)
            changeMap[childKey] = newChange

        case (.childChanged, .childChanged):
            let newChange = FChange(type: .childChanged,
                                    indexedNode: change.indexedNode,
                                    childKey: childKey,
                                    oldIndexedNode: oldChange.oldIndexedNode!)
            changeMap[childKey] = newChange

        case (_, _):
            fatalError("Illegal combination of changes: \(change) occurred after \(oldChange)")
        }
    }
}

