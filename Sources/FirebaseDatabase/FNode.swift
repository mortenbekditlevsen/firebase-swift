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
import SortedCollections
import Synchronization

/// What a node keeps outside its inline storage: its priority, and for a
/// children node its data hash once computed. Children nodes always have one
/// (so the hash can be cached), other nodes only with a priority.
///
/// Nodes are immutable values, so a cached hash stays right: a change makes
/// new nodes on the path to the root, which start without one, and unchanged
/// subtrees keep theirs.
private final class NodeExtras: Sendable {
    let priority: NodeBox?
    let hash = Mutex<SHA1Digest?>(nil)

    init(priority: NodeBox?) {
        self.priority = priority
    }
}

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
/// and `{".sv": {"increment": 1}}` becomes `.increment(.int64(1))`.
enum ServerValueOp: Hashable, Sendable {
    case timestamp
    /// The delta is a number (`.int64` or `.double`).
    indirect case increment(LeafValue)
}

/// Represents the value stored in a leaf node of the Firebase Realtime Database tree.
/// Firebase leaf values are always one of: boolean, number, string,
/// or a deferred server value placeholder (e.g. `{".sv": "timestamp"}`).
///
/// Numbers are 64-bit integers when they are integers, else doubles, as
/// upstream keeps NSNumbers and Android has LongNode and DoubleNode: the two
/// are one type for ordering, compare by value, and hash as doubles (as the
/// server does).
enum LeafValue: Hashable, Sendable {
    case bool(Bool)
    case int64(Int64)
    case double(Double)
    case string(String)
    /// Server value placeholders like `{".sv": "timestamp"}` or `{".sv": {"increment": 1}}`.
    /// These exist transiently before being resolved to concrete values.
    case deferredValue(ServerValueOp)

    /// A number as `.int64` or `.double`, by its type, as upstream's
    /// `canBeRepresentedAsLong`: floats and doubles, and unsigned integers
    /// beyond `Int64.max`, are doubles.
    static func number(_ number: NSNumber) -> LeafValue {
        switch UInt8(bitPattern: number.objCType.pointee) {
        case UInt8(ascii: "f"), UInt8(ascii: "d"):
            return .double(number.doubleValue)
        case UInt8(ascii: "L"), UInt8(ascii: "Q"):
            let value = number.uint64Value
            return value <= UInt64(Int64.max) ? .int64(Int64(value)) : .double(number.doubleValue)
        default:
            return .int64(number.int64Value)
        }
    }

    /// The number as a double (for hashing, as the server hashes numbers).
    var doubleValue: Double? {
        switch self {
        case .int64(let v): return Double(v)
        case .double(let v): return v
        default: return nil
        }
    }

    /// The ordering index for Firebase's JavaScript type system.
    /// Order: deferredValue (object) < bool < number < string
    var typeOrder: Int {
        switch self {
        case .deferredValue: return 0
        case .bool: return 1
        case .int64, .double: return 2
        case .string: return 3
        }
    }

    static func == (lhs: LeafValue, rhs: LeafValue) -> Bool {
        switch (lhs, rhs) {
        case let (.bool(l), .bool(r)): return l == r
        case let (.int64(l), .int64(r)): return l == r
        case let (.double(l), .double(r)): return l == r
        // By value, as NSNumber compares them: 1 equals 1.0.
        case let (.int64(i), .double(d)), let (.double(d), .int64(i)): return Int64(exactly: d) == i
        case let (.string(l), .string(r)): return l == r
        case let (.deferredValue(l), .deferredValue(r)): return l == r
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(typeOrder)
        switch self {
        case .bool(let v): hasher.combine(v)
        // Equal numbers have the same double.
        case .int64, .double: hasher.combine(doubleValue)
        case .string(let v): hasher.combine(v)
        case .deferredValue(let v): hasher.combine(v)
        }
    }

    /// Orders two numbers by value, exactly (not through doubles, which can't
    /// tell large integers apart).
    static func compareNumbers(_ lhs: LeafValue, _ rhs: LeafValue) -> ComparisonResult {
        func compare<T: Comparable>(_ l: T, _ r: T) -> ComparisonResult {
            l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        }
        switch (lhs, rhs) {
        case let (.int64(l), .int64(r)):
            return compare(l, r)
        case let (.int64(i), .double(d)):
            let result = compare(Double(i), d)
            guard result == .orderedSame else { return result }
            // Equal as doubles: compare exactly; a double beyond Int64 is larger.
            return Int64(exactly: d).map { compare(i, $0) } ?? .orderedAscending
        case (.double, .int64):
            switch compareNumbers(rhs, lhs) {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        default:
            return compare(lhs.doubleValue ?? 0, rhs.doubleValue ?? 0)
        }
    }

    /// Converts this leaf value to a Foundation type suitable for the public API.
    var foundationValue: AnyHashable {
        switch self {
        case .bool(let v): return NSNumber(booleanLiteral: v)
        case .int64(let v): return NSNumber(value: v)
        case .double(let v): return NSNumber(value: v)
        case .string(let v): return v as AnyHashable
        case .deferredValue(let op):
            switch op {
            case .timestamp:
                return [kServerValueSubKey: ServerValues.timestampKey] as [String: AnyHashable] as AnyHashable
            case .increment(let delta):
                return [kServerValueSubKey: [ServerValues.incrementKey: delta.foundationValue] as [String: AnyHashable]] as [String: AnyHashable] as AnyHashable
            }
        }
    }
}

struct FNode: Equatable, Hashable, Sendable {
    static let empty: FNode = FNode(type: .empty)
    static func leaf(_ value: LeafValue, priority: FNode? = nil) -> FNode {
        FNode(type: .leaf(value), extras: priorityBox(priority).map(NodeExtras.init(priority:)))
    }
    static func children(_ children: FChildren, priority: FNode? = nil) -> FNode {
        FNode(type: .children(children), extras: NodeExtras(priority: priorityBox(priority)))
    }
    static let max: FNode = FNode(type: .empty, isMax: true, extras: nil)

    /// An empty priority is stored as none, which it equals.
    private static func priorityBox(_ priority: FNode?) -> NodeBox? {
        guard let priority, !priority.isEmpty else { return nil }
        return NodeBox(node: priority)
    }

    enum NodeType: Equatable, Hashable, Sendable {
        case leaf(LeafValue)
        case empty
        case children(FChildren)
    }
    var type: NodeType
    var isMax: Bool = false
    private var extras: NodeExtras?
    private var priorityNode: NodeBox? { extras?.priority }

    // As upstream: an empty node equals a children node without children,
    // and the cached hash doesn't count.
    static func == (lhs: FNode, rhs: FNode) -> Bool {
        guard lhs.isMax == rhs.isMax else { return false }
        // The stored priorities: `getPriority()` of an empty node is an empty
        // node, so comparing those would recurse forever.
        switch (lhs.priorityNode?.node, rhs.priorityNode?.node) {
        case (nil, nil):
            break
        case let (lhsPriority?, rhsPriority?):
            guard lhsPriority == rhsPriority else { return false }
        case let (priority?, nil), let (nil, priority?):
            guard priority.isEmpty else { return false }
        }
        switch (lhs.type, rhs.type) {
        case let (.leaf(lhsValue), .leaf(rhsValue)):
            return lhsValue == rhsValue
        case (.leaf, _), (_, .leaf):
            return false
        default:
            return lhs.children == rhs.children
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(isMax)
        if case .leaf(let value) = type {
            hasher.combine(value)
        } else {
            hasher.combine(children)
        }
        if let priority = priorityNode?.node, !priority.isEmpty {
            hasher.combine(priority)
        }
    }

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
            // index(forKey:) is a B-tree lookup; firstIndex(of:) would scan.
            guard let index = children.index(forKey: KeyIndex(key: childKey)), index != children.startIndex else {
                return nil
            }
            return children[children.index(before: index)].key.key
        }
    }
    private func updateImmediateChild(_ childKey: String, withNewChild newChildNode: FNode, children: FChildren) -> FNode {
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
            // As upstream's FMaxNode: the max node isn't empty, so it can be
            // put under a path (the max post of a path index).
            return !isMax
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
    var children: FChildren {
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

    func dataHash() -> String {
        dataHashDigest()?.base64 ?? ""
    }

    /// The data hash's digest, or nil for the empty hash. Cached in children
    /// nodes, so hashing unchanged data again is free.
    func dataHashDigest() -> SHA1Digest? {
        switch type {
        case .leaf:
            var toHash = ""
            FSnapshotUtilities.appendHashRepresentation(for: self, to: &toHash, hashVersion: .v1)
            return FStringUtilities.sha1(toHash)

        case .empty:
            return nil

        case .children(let children):
            if let cached = extras?.hash.withLock({ $0 }) {
                return cached
            }
            var toHash: [UInt8] = []

            if !getPriority().isEmpty {
                var priority = "priority:"
                FSnapshotUtilities
                    .appendHashRepresentation(for: self.getPriority(),
                                                 to: &priority,
                                                 hashVersion: .v1)
                priority += ":"
                toHash.append(contentsOf: priority.utf8)
            }
            var sawPriority = false
            for node in children.values {
                sawPriority = sawPriority || !node.getPriority().isEmpty
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
                    Self.appendChildHash(namedNode.node, key: namedNode.name, to: &toHash)
                }
            } else {
                for (key, node) in children {
                    Self.appendChildHash(node, key: key.key, to: &toHash)
                }
            }

            guard !toHash.isEmpty else { return nil }
            let digest = FStringUtilities.sha1(toHash)
            extras?.hash.withLock { $0 = digest }
            return digest
        }
    }

    /// ":key:hash" for a child with a non-empty hash.
    private static func appendChildHash(_ node: FNode, key: String, to toHash: inout [UInt8]) {
        guard let digest = node.dataHashDigest() else { return }
        toHash.append(UInt8(ascii: ":"))
        toHash.append(contentsOf: key.utf8)
        toHash.append(UInt8(ascii: ":"))
        digest.appendBase64(to: &toHash)
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
        case (.int64, .int64), (.int64, .double), (.double, .int64), (.double, .double):
            return LeafValue.compareNumbers(lhs, rhs)
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
