//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 03/03/2022.
//

import Foundation

class FLimitedFilter: FNodeFilter {
    let rangedFilter: FRangedFilter
    let index: FIndex
    let limit: Int
    let reverse: Bool
    init(queryParams params: FQueryParams) {
        self.rangedFilter = FRangedFilter(queryParams: params)
        self.index = params.index
        self.limit = params.limit
        self.reverse = !params.isViewFromLeft
    }

    func fullLimitUpdateNode(_ oldIndexed: FIndexedNode, forChildKey childKey: String, newChild newChildSnap: FNode, fromSource source: FCompleteChildSource, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode {
        assert(oldIndexed.node.numChildren() == limit,
                 "Should have number of children equal to limit.")

        let windowBoundary = reverse ? oldIndexed.firstChild! : oldIndexed.lastChild!
        let inRange = rangedFilter.matchesKey(childKey, andNode: newChildSnap)
        if oldIndexed.node.hasChild(childKey) {
            // `childKey` was already in `oldSnap`. Figure out if it remains in the
            // window or needs to be replaced.
            let oldChildSnap = oldIndexed.node.getImmediateChild(childKey)

            // In case the `newChildSnap` falls outside the window, get the
            // `nextChild` that might replace it.
            var nextChild = source.childByIndex(index, afterChild: windowBoundary, isReverse: reverse)
            if let c = nextChild, c.name == childKey || oldIndexed.node.hasChild(c.name) {
                // There is a weird edge case where a node is updated as part of a
                // merge in the write tree, but hasn't been applied to the limited
                // filter yet. Ignore this next child which will be updated later in
                // the limited filter...
                nextChild = source.childByIndex(index, afterChild: c, isReverse: reverse)
            }

            // Figure out if `newChildSnap` is in range and ordered before
            // `nextChild`
            var remainsInWindow = inRange && !newChildSnap.isEmpty
            remainsInWindow = remainsInWindow &&
            (nextChild == nil || index.compare(lhs: (key: nextChild!.name,
                                                  node: nextChild!.node),
                                               rhs: (key: childKey,
                                                  node: newChildSnap),
                                                  reversed:self.reverse).rawValue >=
             ComparisonResult.orderedSame.rawValue)

            if remainsInWindow {
                // `newChildSnap` is ordered before `nextChild`, so it's a child
                // changed event
                if let accumulator = optChangeAccumulator {
                    let change = FChange(type: .childChanged,
                                         indexedNode: FIndexedNode(node: newChildSnap),
                                         childKey: childKey,
                                         oldIndexedNode: FIndexedNode(node: oldChildSnap))
                    accumulator.trackChildChange(change)
                }
                return oldIndexed.updateChild(childKey, withNewChild: newChildSnap)
            } else {
                // `newChildSnap` is ordered after `nextChild`, so it's a child
                // removed event
                if let accumulator = optChangeAccumulator {
                    let change = FChange(type: .childRemoved,
                                         indexedNode: FIndexedNode(node: oldChildSnap),
                                         childKey: childKey)
                    accumulator.trackChildChange(change)
                }
                let newIndexed = oldIndexed.updateChild(childKey, withNewChild: .empty)

                // We need to check if the `nextChild` is actually in range before
                // adding it

                guard let nextChild = nextChild else {
                    return newIndexed
                }

                guard rangedFilter.matchesKey(nextChild.name,
                                              andNode: nextChild.node) else {
                    return newIndexed
                }
                if let accumulator = optChangeAccumulator {
                    let change = FChange(type:.childAdded,
                                         indexedNode:FIndexedNode(node: nextChild.node),
                                         childKey:nextChild.name)
                    accumulator.trackChildChange(change)
                }
                return newIndexed.updateChild(nextChild.name,
                                              withNewChild:nextChild.node)
            }

        } else if newChildSnap.isEmpty {
            // We're deleting a node, but it was not in the window, so ignore it.
            return oldIndexed
        } else if inRange {
            // `newChildSnap` is in range, but was ordered after `windowBoundary`.
            // If this has changed, we bump out the `windowBoundary` and add the
            // `newChildSnap`
            if index.compare(lhs: (key: windowBoundary.name,
                               node: windowBoundary.node),
                             rhs: (key: childKey,
                                   node: newChildSnap),
                                reversed:self.reverse).rawValue >= ComparisonResult.orderedSame.rawValue {
                if let accumulator = optChangeAccumulator {
                    let removedChange = FChange(type: .childRemoved, indexedNode: FIndexedNode(node: windowBoundary.node), childKey: windowBoundary.name)
                    let addedChange = FChange(type: .childAdded, indexedNode: FIndexedNode(node: newChildSnap), childKey: childKey)
                    accumulator.trackChildChange(removedChange)
                    accumulator.trackChildChange(addedChange)
                }
                return oldIndexed
                    .updateChild(childKey, withNewChild:newChildSnap)
                    .updateChild(windowBoundary.name, withNewChild: .empty)
            } else {
                return oldIndexed
            }
        } else {
            // `newChildSnap` was not in range and remains not in range, so ignore
            // it.
            return oldIndexed
        }
    }

    func updateChildIn(_ oldSnap: FIndexedNode, forChildKey childKey: String, newChild newChildSnap: FNode, affectedPath: FPath, fromSource source: FCompleteChildSource, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode {
        var newChildSnap = newChildSnap
        if !self.rangedFilter.matchesKey(childKey, andNode:newChildSnap) {
            newChildSnap = .empty
        }
        if oldSnap.node.getImmediateChild(childKey) == newChildSnap {
            // No change
            return oldSnap
        } else if oldSnap.node.numChildren() < self.limit {
            return self.rangedFilter.indexedFilter
                .updateChildIn(oldSnap, forChildKey: childKey, newChild: newChildSnap, affectedPath: affectedPath, fromSource: source, accumulator: optChangeAccumulator)
        } else {
            return fullLimitUpdateNode(oldSnap,
                                       forChildKey:childKey,
                                       newChild:newChildSnap,
                                       fromSource:source,
                                       accumulator:optChangeAccumulator)
        }
    }

    func updateFullNode(_ oldSnap: FIndexedNode, withNewNode newSnap: FIndexedNode, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode {

        var filtered: FIndexedNode
        if newSnap.node.isLeafNode() || newSnap.node.isEmpty {
            // Make sure we have a children node with the correct index, not a leaf
            // node
            filtered = FIndexedNode(node: .empty, index: index)
        } else {
            filtered = newSnap
            // Don't support priorities on queries.
            filtered = filtered.updatePriority(.empty)
            var startPost: FNamedNode
            var endPost: FNamedNode
            if self.reverse {
                startPost = self.rangedFilter.endPost
                endPost = self.rangedFilter.startPost
            } else {
                startPost = self.rangedFilter.startPost
                endPost = self.rangedFilter.endPost
            }
            var foundStartPost = false
            var count = 0
            newSnap.enumerateChildrenReverse(reverse) { childKey, childNode, stop in
                if !foundStartPost && self.index.compare(lhs: (key: startPost.name, node: startPost.node), rhs: (key: childKey, node: childNode), reversed: self.reverse).rawValue <= ComparisonResult.orderedSame.rawValue {
                    // Start adding
                    foundStartPost = true
                }
                var inRange = foundStartPost && count < self.limit
                inRange = inRange &&
                self.index.compare(lhs: (key: childKey,
                                         node: childNode),
                                   rhs: (key :endPost.name,
                                         node: endPost.node),
                                      reversed:self.reverse).rawValue <=
                ComparisonResult.orderedSame.rawValue;
                if inRange {
                    count += 1
                } else {
                    filtered = filtered.updateChild(childKey,
                                withNewChild:.empty)
                }

            }
        }
        return self.indexedFilter.updateFullNode(oldSnap,
                                      withNewNode:filtered,
                                                 accumulator:optChangeAccumulator)

    }

    func updatePriority(_ priority: FNode, forNode oldSnap: FIndexedNode) -> FIndexedNode {
        // Don't support priorities on queries.
        return oldSnap
    }

    var indexedFilter: FNodeFilter {
        rangedFilter.indexedFilter
    }

    var filtersNodes: Bool { true }
}
