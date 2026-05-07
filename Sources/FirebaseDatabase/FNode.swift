//
//  File.swift
//  File
//
//  Created by Morten Bek Ditlevsen on 14/09/2021.
//

import Foundation
import SortedCollections

private final class NodeBox: Hashable, Sendable {
    static func == (lhs: NodeBox, rhs: NodeBox) -> Bool {
        lhs.node == rhs.node
    }

    let node: FNode

    init(node: FNode) {
        self.node = node
    }

    func hash(into hasher: inout Hasher) {
        node.hash(into: &hasher)
    }
}

/// Represents the server operation inside a deferred value placeholder.
/// For example, `{".sv": "timestamp"}` becomes `.timestamp`,
/// and `{".sv": {"increment": 1}}` becomes `.increment(1.0)`.
enum ServerValueOp: Hashable, Sendable {
    case timestamp
    case increment(Double)
}

/// Represents the value stored in a leaf node of the Firebase Realtime Database tree.
/// Firebase leaf values are always one of: boolean, number (double), string,
/// or a deferred server value placeholder (e.g. `{".sv": "timestamp"}`).
enum LeafValue: Hashable, Sendable {
    case bool(Bool)
    case double(Double)
    case string(String)
    /// Server value placeholders like `{".sv": "timestamp"}` or `{".sv": {"increment": 1}}`.
    /// These exist transiently before being resolved to concrete values.
    case deferredValue(ServerValueOp)

    /// The ordering index for Firebase's JavaScript type system.
    /// Order: deferredValue (object) < bool < double (number) < string
    var typeOrder: Int {
        switch self {
        case .deferredValue: return 0
        case .bool: return 1
        case .double: return 2
        case .string: return 3
        }
    }

    /// Converts this leaf value to a Foundation type suitable for the public API.
    var foundationValue: AnyHashable {
        switch self {
        case .bool(let v): return NSNumber(booleanLiteral: v)
        case .double(let v): return NSNumber(value: v)
        case .string(let v): return v as AnyHashable
        case .deferredValue(let op):
            switch op {
            case .timestamp:
                return [kServerValueSubKey: ServerValues.timestampKey] as [String: AnyHashable] as AnyHashable
            case .increment(let delta):
                return [kServerValueSubKey: [ServerValues.incrementKey: delta] as [String: Double]] as [String: AnyHashable] as AnyHashable
            }
        }
    }
}

struct FNode: Equatable, Hashable, Sendable {
    static let empty: FNode = FNode(type: .empty)
    static func leaf(_ value: LeafValue, priority: FNode? = nil) -> FNode {
        FNode(type: .leaf(value), priorityNode: priority.map(NodeBox.init(node:)))
    }
    static func children(_ children: SortedDictionary<KeyIndex, FNode>, priority: FNode? = nil) -> FNode {
        FNode(type: .children(children), priorityNode: priority.map(NodeBox.init(node:)))
    }
    static let max: FNode = FNode(type: .empty, isMax: true, priorityNode: nil)

    enum NodeType: Equatable, Hashable, Sendable {
        case leaf(LeafValue)
        case empty
        case children(SortedDictionary<KeyIndex, FNode>)
    }
    var type: NodeType
    var lazyHash: String?
    var isMax: Bool = false
    private var priorityNode: NodeBox?

    func isLeafNode() -> Bool {
        if case .leaf = type { return true } else { return false }
    }

    func getPriority() -> FNode {
        priorityNode?.node ?? .empty
    }

    func updatePriority(_ priority: FNode) -> FNode {
        switch type {
        case .empty:
            return .empty
        case .leaf(let value):
            return .leaf(value, priority: priority)
        case .children(let children):
            return .children(children, priority: priority)
        }
    }

    func getImmediateChild(_ childKey: String) -> FNode {
        if childKey == ".priority" {
            return getPriority()
        } else {
            switch type {
            case .empty, .leaf:
                return .empty
            case .children(let children):
                return children[KeyIndex(key: childKey)] ?? .empty
            }
        }
    }
    func getChild(_ path: FPath) -> FNode {
        guard let front = path.getFront() else {
            return self
        }
        if front == ".priority" {
            return getPriority()
        } else {
            switch type {
            case .empty, .leaf:
                return .empty
            case .children:
                return getImmediateChild(front).getChild(path.popFront())
            }
        }
    }
    func predecessorChildKey(_ childKey: String) -> String? {
        switch type {
        case .leaf, .empty:
            return nil
        case .children(let children):
            let wrapped = KeyIndex(key: childKey)
            guard let keyIndex = children.keys.firstIndex(of: wrapped), keyIndex != children.keys.startIndex else {
                return nil
            }
            return children.keys[children.keys.index(before: keyIndex)].key
        }
    }
    private func updateImmediateChild(_ childKey: String, withNewChild newChildNode: FNode, children: SortedDictionary<KeyIndex, FNode>) -> FNode {
        var newChildren = children
        if newChildNode.isEmpty {
            _ = newChildren.removeValue(forKey: KeyIndex(key: childKey))
        } else {
            newChildren[KeyIndex(key: childKey)] = newChildNode
        }

        if newChildren.isEmpty {
            return .empty
        } else {
            return .children(newChildren, priority: getPriority())
        }
    }

    func updateImmediateChild(
            _ childKey: String,
            withNewChild newChildNode: FNode
    ) -> FNode {
        guard childKey != ".priority" else {
            return updatePriority(newChildNode)
        }

        switch type {
        case .empty:
            return updateImmediateChild(childKey, withNewChild: newChildNode, children: [:])
        case .children(let children):
            return updateImmediateChild(childKey, withNewChild: newChildNode, children: children)
        case .leaf:
            if newChildNode.isEmpty {
                return self
            } else {
                return .empty
                    .updateImmediateChild(childKey, withNewChild: newChildNode)
                    .updatePriority(getPriority())
            }
        }
    }
    func updateChild(_ path: FPath, withNewChild newChildNode: FNode) -> FNode {
        guard let front = path.getFront() else {
            return newChildNode
        }
        switch type {
        case .leaf:
            if newChildNode.isEmpty && front != ".priority" {
                return self
            } else {
                assert(front != ".priority" || path.length() == 1, ".priority must be the last token in a path.")
                return self.updateImmediateChild(front, withNewChild: .empty.updateChild(path.popFront(), withNewChild: newChildNode))
            }

        case .children, .empty:
            assert(front != ".priority" || path.length() == 1, ".priority must be the last token in a path.")
            let newImmediateChild = getImmediateChild(front).updateChild(path.popFront(), withNewChild: newChildNode)
            return updateImmediateChild(front, withNewChild: newImmediateChild)

        }
    }

    func hasChild(_ childKey: String) -> Bool {
        !getImmediateChild(childKey).isEmpty
    }

    var isEmpty: Bool {
        switch type {
        case .empty:
            return true
        case .leaf:
            return false
        case .children(let children):
            return children.isEmpty
        }
    }
    func numChildren() -> Int {
        switch type {
        case .empty, .leaf:
            return 0
        case .children(let children):
            return children.count
        }
    }
    var count: Int {
        numChildren()
    }

    // XXX TODO: Ought to be an opaque collection in the future
    // Alternatively, children should just return an iterator...
    var children: SortedDictionary<KeyIndex, FNode> {
        switch type {
        case .leaf, .empty:
            return [:]
        case .children(let children):
            return children
        }
    }

    func val(forExport exp: Bool = false) -> AnyHashable {
        switch type {
        case .leaf(let value):
            let foundationVal = value.foundationValue
            if exp && !getPriority().isEmpty {
                return [
                    kPayloadValue: foundationVal,
                    kPayloadPriority: getPriority().val()
                ]
            } else {
                return foundationVal
            }
        case .empty:
            return NSNull()
        case .children(let children):
            guard !isEmpty else {
                return NSNull()
            }
            var numKeys = 0
            var maxKey = 0
            var allIntegerKeys = true
            let obj = NSMutableDictionary(capacity: children.count)
            for (key, childNode) in children {
                obj.setObject(childNode.val(forExport: exp), forKey: key.key as NSString)
                numKeys += 1

                // If we already found a string key, don't bother with any of this
                if !allIntegerKeys { continue }

                // Treat leading zeroes that are not exactly "0" as strings
                if key.key.first == "0" && key.key.count > 1 {
                    allIntegerKeys = false
                    continue
                }
                if let keyAsInt = FUtilities.intForString(key.key) {
                    maxKey = Swift.max(maxKey, keyAsInt)
                } else {
                    allIntegerKeys = false
                }
            }
            if !exp && allIntegerKeys && maxKey < 2 * numKeys {
                // convert to an array
                let array = NSMutableArray(capacity: maxKey + 1)
                for i in 0...maxKey {
                    if let child = obj["\(i)"] {
                        array.add(child)
                    } else {
                        array.add(NSNull())
                    }
                }
                return array
            } else {
                if exp && !self.getPriority().isEmpty {
                    obj[".priority"] = getPriority().val()
                }
                return obj
            }
        }
    }

    /*mutating*/ func dataHash() -> String {
        if let lazyHash {
            return lazyHash
        }
        let calculatedHash: String
        switch type {
        case .leaf:
            var toHash = ""
            FSnapshotUtilities.appendHashRepresentation(for: self, to: &toHash, hashVersion: .v1)
            calculatedHash = FStringUtilities.base64EncodedSha1(toHash)

        case .empty:
            calculatedHash = ""

        case .children(let children):
            var toHash = ""

            if !getPriority().isEmpty {
                toHash += "priority:"
                FSnapshotUtilities
                    .appendHashRepresentation(for: self.getPriority(),
                                                 to: &toHash,
                                                 hashVersion: .v1)
                toHash += ":"
            }
            var sawPriority = false
            for node in children.values {
                sawPriority = sawPriority || node.getPriority().isEmpty
                if sawPriority { break }
            }
            if sawPriority {
                var array: [FNamedNode] = []
                for (key, node) in children {
                    array.append(FNamedNode(name: key.key, andNode: node))
                }
                array.sort { a, b in
                    FIndex
                        .priority
                        .compareNamedNode(lhs: a, rhs: b) == .orderedAscending
                }
                for namedNode in array {
                    let childHash = namedNode.node.dataHash()
                    if !children.isEmpty {
                        toHash += ":\(namedNode.name):\(childHash)"
                    }
                }
            } else {
                for (key, node) in children {
                    let childHash = node.dataHash()
                    if !childHash.isEmpty {
                        toHash += ":\(key.key):\(childHash)"
                    }
                }
            }

            calculatedHash = toHash.isEmpty ? "" : FStringUtilities.base64EncodedSha1(toHash)

        }
        // XXX TODO: Box the cached hash somehow?
//        lazyHash = calculatedHash
        return calculatedHash;
    }

    func enumerateChildrenAndPriority(usingBlock block: @escaping (_ key: String, _ node: FNode, _ stop: inout Bool) -> Void) {
        guard !self.getPriority().isEmpty else {
            enumerateChildren(usingBlock: block)
            return
        }
        var passedPriorityKey = false
        enumerateChildren { key, node, stop in
            if !passedPriorityKey && FUtilities.compareKey(key, ".priority") == .orderedDescending {
                passedPriorityKey = true
                var stopAfterPriority = false
                block(".priority", self.getPriority(), &stopAfterPriority)
                if stopAfterPriority {
                    return
                }
            }
            block(key, node, &stop)
        }
    }


    func enumerateChildren(usingBlock block: @escaping (_ key: String, _ node: FNode, _ stop: inout Bool) -> Void) {
        switch type {
        case .leaf, .empty:
            // Nothing to iterate over
            ()
        case .children(let children):
            var stop = false
            for (key, value) in children {
                block(key.key, value, &stop)
                if stop { break }
            }
        }
    }
        func enumerateChildrenReverse(
                _ reverse: Bool,
                usingBlock block: @escaping (_ key: String, _ node: FNode, _ stop: inout Bool) -> Void
        ) {
            switch type {
            case .leaf, .empty:
                // Nothing to iterate over
                ()
            case .children(let children):
                var stop = false
                if reverse {
                    for (key, value) in children.reversed() {
                        block(key.key, value, &stop)
                        if stop { break }
                    }
                } else {
                    for (key, value) in children {
                        block(key.key, value, &stop)
                        if stop { break }
                    }
                }
            }
        }


//    func val() -> Any
//    func val(forExport exp: Bool) -> Any
//    func dataHash() -> String
    func compare(_ other: FNode) -> ComparisonResult {
        switch (self.isMax, other.isMax) {
        case (true, true):
            return .orderedSame
        case (true, false):
            return .orderedDescending
        case (false, true):
            return .orderedAscending
        case (false, false):
            ()
        }
        switch (self.type, other.type) {
        case (.leaf, .empty):
            return .orderedDescending
        case (.empty, .leaf):
            return .orderedAscending
        case (.leaf, .children):
            return .orderedAscending
        case (.children, .leaf):
            return .orderedDescending
        case (.empty, .children):
            return .orderedAscending
        case (.children, .empty):
            return .orderedDescending
        case (.empty, .empty):
            return .orderedSame
        case (.leaf(let lVal), .leaf(let rVal)):
            return FNode.compareLeafNodeValue(lhs: lVal, rhs: rVal)
        case (.children, .children):
            return .orderedSame
        }
    }

    private static func compareLeafNodeValue(lhs: LeafValue, rhs: LeafValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.bool(let l), .bool(let r)):
            return l == r ? .orderedSame : (l ? .orderedDescending : .orderedAscending)
        case (.double(let l), .double(let r)):
            return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        case (.string(let l), .string(let r)):
            return l.compare(r, options: .literal)
        case (.deferredValue, .deferredValue):
            // Deferred value nodes are all equal
            return .orderedSame
        default:
            // Different types: compare by type order
            return lhs.typeOrder < rhs.typeOrder ? .orderedAscending : .orderedDescending
        }
    }
}
