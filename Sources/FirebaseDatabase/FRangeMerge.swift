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

/**
 * Applies a merge of a snap for a given interval of paths.
 * Each leaf in the current node which the relative path lies *after* (the
 * optional) start and lies *before or at* (the optional) end will be deleted.
 * Each leaf in snap that lies in the interval will be added to the resulting
 * node. Nodes outside of the range are ignored. nil for start and end are
 * sentinel values that represent -infinity and +infinity respectively (aka
 * includes any path). Priorities of children nodes are treated as leaf children
 * of that node.
 */
struct FRangeMerge {
    let optExclusiveStart: FPath?
    let optInclusiveEnd: FPath?
    var updates: FNode

    func applyToNode(_ node: FNode) -> FNode {
        updateRangeInNode(currentPath: .empty,
                          node: node,
                          updates: updates)
    }

    init(start: FPath?, end: FPath?, updates: FNode) {
        self.optExclusiveStart = start
        self.optInclusiveEnd = end
        self.updates = updates
    }

    private func updateRangeInNode(currentPath: FPath, node: FNode, updates: FNode) -> FNode {
        let startComparison = optExclusiveStart.map { currentPath.compare($0) } ?? .orderedDescending

        let endComparison = optInclusiveEnd.map { currentPath.compare($0) } ?? .orderedAscending

        let startInNode = optExclusiveStart.map { currentPath.contains($0) } ?? false

        let endInNode = optInclusiveEnd.map { currentPath.contains($0) } ?? false

        if (startComparison == .orderedDescending &&
            endComparison == .orderedAscending && !endInNode) {
            // child is completly contained
            return updates
        } else if (startComparison == .orderedDescending &&
                   endInNode &&
                   updates.isLeafNode()) {
            return updates
        } else if (startComparison == .orderedDescending &&
                   endComparison == .orderedSame) {
            assert(endInNode, "End not in node")
            assert(!updates.isLeafNode(), "Found leaf node update, this case should have been handled above.")
            if node.isLeafNode() {
                // Update node was not a leaf node, so we can delete it
                return .empty
            } else {
                // Unaffected by range, ignore
                return node
            }
        } else if (startInNode || endInNode) {
            // There is a partial update we need to do, so collect all relevant
            // children
            var allChildren: Set<String> = []
            node.enumerateChildren { key, _, _ in
                allChildren.insert(key)
            }
            updates.enumerateChildren { key, _, _ in
                allChildren.insert(key)
            }

            var newNode = node

            let action: (String) -> Void = { key in
                let currentChild = node.getImmediateChild(key)
                let updatedChild =
                self.updateRangeInNode(currentPath:
                                        currentPath.child(fromString: key),
                                       node: currentChild,
                                       updates: updates.getImmediateChild(key))
                // Only need to update if the node changed
                if (updatedChild != currentChild) {
                    newNode = newNode.updateImmediateChild(key,
                                                           withNewChild:updatedChild)
                }
            }

            for key in allChildren {
                action(key)
            }

            // Add priority last, so the node is not empty when applying
            if !updates.getPriority().isEmpty || !node.getPriority().isEmpty {
                action(".priority")
            }
            return newNode
        } else {
            // Unaffected by this range
            assert(endComparison == .orderedDescending ||
                   startComparison.rawValue <= ComparisonResult.orderedSame.rawValue,
                   "Invalid range for update")
            return node
        }
    }

    var debugDescription: String {
        "RangeMerge (optExclusiveStart = \(optExclusiveStart?.description ?? "nil"), optExclusiveEnd = \(optInclusiveEnd?.description ?? "nil"), updates = \(updates))"
    }
}
