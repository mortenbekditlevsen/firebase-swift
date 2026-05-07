//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

enum FOperationType {
    case overwrite(snap: FNode)
    case merge(children: FCompoundWrite)
    case ackUserWrite(affectedTree: FImmutableTree<Bool>, revert: Bool)
    case listenComplete
}

struct FOperation {
    var source: FOperationSource
    var path: FPath
    var type: FOperationType

    static func overwrite(source: FOperationSource, path: FPath, snap: FNode) -> FOperation {
        FOperation(source: source, path: path, type: .overwrite(snap: snap))
    }

    static func merge(source: FOperationSource, path: FPath, children: FCompoundWrite) -> FOperation {
        FOperation(source: source, path: path, type: .merge(children: children))
    }

    static func ackUserWrite(path: FPath, affectedTree: FImmutableTree<Bool>, revert: Bool) -> FOperation {
        FOperation(source: .user, path: path, type: .ackUserWrite(affectedTree: affectedTree, revert: revert))
    }
    static func listenComplete(source: FOperationSource, path: FPath) -> FOperation {
        FOperation(source: .user, path: path, type: .listenComplete)
    }

    func operationForChild(_ childKey: String) -> FOperation? {
        switch type {
        case .overwrite(let snap):
            if path.isEmpty {
                return .overwrite(source: source, path: .empty, snap: snap.getImmediateChild(childKey))
            } else {
                return .overwrite(source: source, path: path.popFront(), snap: snap)
            }
        case .merge(let children):
            if path.isEmpty {
                let childTree = children.childCompoundWriteAtPath(FPath(with: childKey))
                if childTree.isEmpty {
                    return nil
                } else if let rootWrite = childTree.rootWrite {
                    // We have a snapshot for the child in question. This becomes an
                    // overwrite of the child.
                    return .overwrite(source: source, path: .empty, snap: rootWrite)
                } else {
                    // This is a merge at a deeper level
                    return .merge(source: source, path: .empty, children: childTree)
                }
            } else {
                assert(path.getFront() == childKey,
                    "Can't get a merge for a child not on the path of the operation")
                return .merge(source: source, path: path.popFront(), children: children)
            }
        case let .ackUserWrite(affectedTree, revert):
            if !path.isEmpty {
                assert(path.getFront() == childKey, "operationForChild called for unrelated child.")
                return .ackUserWrite(path: path.popFront(),
                                     affectedTree: affectedTree,
                                     revert: revert)
            } else if affectedTree.value != nil {
                assert(affectedTree.childrenIsEmpty, "affectedTree should not have overlapping affected paths.")
                // All child locations are affected as well; just return same operation.
                return self
            } else {
                let childTree = affectedTree.subtree(atPath: FPath(with: childKey))
                return .ackUserWrite(path: .empty,
                                     affectedTree: childTree,
                                     revert: revert)
            }

        case .listenComplete:
            if path.isEmpty {
                return .listenComplete(source: source, path: .empty)
            } else {
                return .listenComplete(source: source, path: path.popFront())
            }
        }
    }

    var description: String {
        switch type {
        case .overwrite(let snap):
            return "FOverwrite { path=\(path), source=\(source), snapshot=\(snap) }"
        case .merge(let children):
            return "FMerge { path=\(path), source=\(source) children=\(children)}"
        case let .ackUserWrite(affectedTree, revert):
            return "FAckUserWrite { path=\(path), revert=\(revert), affectedTree=\(affectedTree) }"
        case .listenComplete:
            return "FListenComplete { path=\(path), source=\(source) }"
        }
    }
}
