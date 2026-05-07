//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 22/09/2021.
//

import Foundation

enum FIndex: Equatable, Hashable {
    case key
    case priority
    case value
    case path(FPath)

    func compare(lhs: (key: String, node: FNode), rhs: (key: String, node: FNode)) -> ComparisonResult {
        switch self {
        case .key:
            return FUtilities.compareKey(lhs.key, rhs.key)
        case .value:
            let indexCmp = lhs.node.compare(rhs.node)
            if indexCmp == .orderedSame {
                return FUtilities.compareKey(lhs.key, rhs.key)
            } else {
                return indexCmp
            }
        case .priority:
            let lhsChild = lhs.node.getPriority()
            let rhsChild = rhs.node.getPriority()

            let indexCmp = lhsChild.compare(rhsChild)
            if indexCmp == .orderedSame {
                return FUtilities.compareKey(lhs.key, rhs.key)
            } else {
                return indexCmp
            }
        case .path(let path):
            let lhsChild = lhs.node.getChild(path)
            let rhsChild = rhs.node.getChild(path)

            let indexCmp = lhsChild.compare(rhsChild)
            if indexCmp == .orderedSame {
                return FUtilities.compareKey(lhs.key, rhs.key)
            } else {
                return indexCmp
            }
        }
    }

    func isDefined(on node: FNode) -> Bool {
        switch self {
        case .key:
            return true
        case .value:
            return true
        case .priority:
            return !node.getPriority().isEmpty
        case .path(let path):
            return !node.getChild(path).isEmpty
        }
    }

    func indexedValueChanged(between oldNode: FNode?, and newNode: FNode) -> Bool {
        switch self {
        case .key:
            // The key for a node never changes.
            return false
        case .value:
            return oldNode != newNode

        case .priority:
            let oldValue = oldNode?.getPriority()
            let newValue = newNode.getPriority()
            return oldValue != newValue

        case .path(let path):
            let oldValue = oldNode?.getChild(path)
            let newValue = newNode.getChild(path)
            return oldValue != newValue
        }
    }

    var minPost: FNamedNode { .min }
    var maxPost: FNamedNode {
        switch self {
        case .key:
            return FNamedNode(name: FUtilities.maxName, andNode: .empty)
        case .value:
            return .max
        case .priority:
            return makePost(.max, name: FUtilities.maxName)
        case .path:
            return makePost(.max, name: FUtilities.maxName)
        }
    }

    func makePost(_ indexValue: FNode, name: String) -> FNamedNode {
        switch self {
        case .key:
            let key = indexValue.val() as? String
            assert(key != nil, "KeyIndex indexValue must always be a string.")

            // We just use empty node, but it'll never be compared, since our comparator
            // only looks at name.
            return FNamedNode(name: key ?? "", andNode: .empty)

        case .value:
            return FNamedNode(name: name, andNode: indexValue)

        case .priority:
            let node = FNode.leaf("[PRIORITY-POST]", priority: indexValue)
            return FNamedNode(name: name, andNode: node)

        case .path(let path):
            let node = FNode.empty
                .updateChild(path, withNewChild: indexValue)
            return FNamedNode(name: name, andNode: node)
        }
    }

    var description: String {
        switch self {
        case .key:
            return "FKeyIndex"
        case .priority:
            return "FPriorityIndex"
        case .value:
            return "FValueIndex"
        case .path(let path):
            return "FPathIndex(\(path))"
        }
    }

    var queryDefinition: String {
        switch self {
        case .key:
            return ".key"
        case .value:
            return ".value"
        case .priority:
            return ".priority"
        case .path(let path):
            return path.wireFormat()
        }
    }

//    var objc: FIndex {
//        switch self {
//        case .key:
//            return FKeyIndex.keyIndex
//        case .value:
//            return FValueIndex.valueIndex
//        case .priority:
//            return FPriorityIndex.priorityIndex
//        case .path(let path):
//            return FPathIndex(path: path)
//        }
//    }
}

extension FIndex {
    func compareNamedNode(lhs: FNamedNode, rhs: FNamedNode) -> ComparisonResult {
        compare(lhs: (key: lhs.name, node: lhs.node), rhs: (key: rhs.name, node: rhs.node))
    }
    func compare(lhs: (key: String, node: FNode), rhs: (key: String, node: FNode), reversed: Bool) -> ComparisonResult {
        if reversed {
            return compare(lhs: rhs, rhs: lhs)
        } else {
            return compare(lhs: lhs, rhs: rhs)
        }
    }

    static func fromQueryDefinition(_ definition: String) -> FIndex {
        switch definition {
        case ".key":
            return .key
        case ".value":
            return .value
        case ".priority":
            return .priority
        default:
            return .path(FPath(with: definition))
        }
    }
}
