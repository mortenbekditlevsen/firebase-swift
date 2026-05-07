//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 03/03/2022.
//

import Foundation

class FRangedFilter: FNodeFilter {
    public let startPost: FNamedNode
    public let endPost: FNamedNode
    init(queryParams params: FQueryParams) {
        self.indexedFilter = FIndexedFilter(index: params.index)
        self.index = params.index
        self.startPost = FRangedFilter.startPost(fromQueryParams: params)
        self.endPost = FRangedFilter.endPost(fromQueryParams: params)
    }
    func updateChildIn(_ oldSnap: FIndexedNode, forChildKey childKey: String, newChild newChildSnap: FNode, affectedPath: FPath, fromSource source: FCompleteChildSource, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode {
        var newChildSnap = newChildSnap
        if !matchesKey(childKey, andNode:newChildSnap) {
            newChildSnap = .empty
        }
        return indexedFilter.updateChildIn(oldSnap,
                                           forChildKey:childKey,
                                           newChild:newChildSnap,
                                           affectedPath:affectedPath,
                                           fromSource:source,
                                           accumulator:optChangeAccumulator)

    }

    func updateFullNode(_ oldSnap: FIndexedNode, withNewNode newSnap: FIndexedNode, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode {
        var filtered: FIndexedNode
        if newSnap.node.isLeafNode() {
            // Make sure we have a children node with the correct index, not a leaf
            // node
            filtered = FIndexedNode.indexedNodeWithNode(.empty, index: index)
        } else {
            // Dont' support priorities on queries
            filtered = newSnap.updatePriority(.empty)
            newSnap.node.enumerateChildren { key, node, stop in
                if !self.matchesKey(key, andNode: node) {
                    filtered = filtered.updateChild(key, withNewChild: .empty)
                }
            }
        }
        return indexedFilter.updateFullNode(oldSnap, withNewNode: filtered, accumulator: optChangeAccumulator)
    }

    func updatePriority(_ priority: FNode, forNode oldSnap: FIndexedNode) -> FIndexedNode {
        // Don't support priorities on queries
        return oldSnap
    }

    var filtersNodes: Bool { true }

    var indexedFilter: FNodeFilter

    var index: FIndex

    static func startPost(fromQueryParams params: FQueryParams) -> FNamedNode {
        if params.hasStart {
            let startKey = params.indexStartKey
            return params.index.makePost(params.indexStartValue, name: startKey)
        } else {
            return params.index.minPost
        }
    }

    static func endPost(fromQueryParams params: FQueryParams) -> FNamedNode {
        if params.hasEnd {
            let endKey = params.indexEndKey
            return params.index.makePost(params.indexEndValue, name: endKey)
        } else {
            return params.index.maxPost
        }
    }

    func matchesKey(_ key: String, andNode node: FNode) -> Bool {
        index.compare(lhs: (key: startPost.name,
                            node: startPost.node),
                      rhs: (key: key,
                            node: node)
        ).rawValue <= ComparisonResult.orderedSame.rawValue &&
        index.compare(lhs: (key: key, node: node),
                      rhs: (key: endPost.name, node: endPost.node))
        .rawValue <= ComparisonResult.orderedSame.rawValue
    }
}
