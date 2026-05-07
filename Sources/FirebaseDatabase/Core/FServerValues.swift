//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 01/04/2022.
//

import Foundation

let kTimestamp = "timestamp"
let kIncrement = "increment"

func canBeRepresentedAsLong(num: NSNumber) -> Bool {
    switch (num.objCType[0]) {
    case "f".utf8CString[0]: // float;
        fallthrough
    case "d".utf8CString[0]: // double
        return false
    case "L".utf8CString[0]: // unsigned long;
        fallthrough
    case "Q".utf8CString[0]: // unsigned long long; fallthrough
        // Only use ulong(long) if there isn't an overflow.
        if (num.uint64Value > UInt64.max) {
            return false
        }
        fallthrough
    default:
        return true
    }
}

protocol ValueProvider {
    func getChild(_ pathSegment: String) -> ValueProvider
    var value: FNode? { get }
}

class DeferredValueProvider: ValueProvider {
    let tree: FSyncTree
    let path: FPath
    init(syncTree: FSyncTree, atPath path: FPath) {
        self.tree = syncTree
        self.path = path
    }
    func getChild(_ pathSegment: String) -> ValueProvider {
        let child = path.child(fromString: pathSegment)
        return DeferredValueProvider(syncTree: tree, atPath: child)
    }
    var value: FNode? {
        tree.calcCompleteEventCacheAtPath(self.path, excludeWriteIds: [])
    }
}

class ExistingValueProvider: ValueProvider {
    let snapshot: FNode?
    init(snapshot: FNode?) {
        self.snapshot = snapshot
    }
    func getChild(_ pathSegment: String) -> ValueProvider {
        ExistingValueProvider(snapshot: snapshot?.getImmediateChild(pathSegment))
    }
    var value: FNode? { snapshot }
}

class FServerValues {
    private static func resolveScalarServerOp(_ op: String,
                                              withServerValues serverValues: [String: Any]) -> AnyHashable? {
        serverValues[op] as? AnyHashable
    }
    private static func resolveComplexServerOp(_ op: [String: Any],
                                               withValueProvider jitExisting: ValueProvider,
                                              serverValues: [String: Any]) -> AnyHashable? {
        // Only increment is supported as of now
        guard let delta = op[kIncrement] as? NSNumber else {
            return nil
        }
        // Incrementing a non-number sets the value to the incremented amount
        let existing = jitExisting.value
        guard case let .leaf(existingValue) = existing?.type else {
            return delta
        }
        guard let existingNum = existingValue as? NSNumber else {
            return delta
        }
        let incrLong = canBeRepresentedAsLong(num: delta)
        let baseLong = canBeRepresentedAsLong(num: existingNum)
        if incrLong && baseLong {
            let x = delta.uint64Value
            let y = existingNum.uint64Value
            let r = x + y
            // See "Hacker's Delight" 2-12: Overflow if both arguments have the
            // opposite sign of the result
            if ((x ^ r) & (y ^ r)) >= 0 {
                return NSNumber(value: r)
            }
        }
        return NSNumber(value: delta.doubleValue + existingNum.doubleValue)
    }

    private static func resolveDeferredValue(_ val: AnyHashable, withExisting existing: ValueProvider, serverValues: [String: Any]) -> AnyHashable? {
        guard let dict = val as? [String: AnyHashable] else {
            return val
        }
        guard let op = dict[kServerValueSubKey] else {
            return val
        }
        if let stringOp = op as? String {
            return FServerValues.resolveScalarServerOp(stringOp, withServerValues: serverValues)
        } else if let dictOp = op as? [String: Any] {
            return FServerValues.resolveComplexServerOp(dictOp, withValueProvider: existing, serverValues: serverValues)
        }
        return val
    }

    private static func resolveDeferredValueSnapshot(_ node: FNode,
                                                     withValueProvider existing: ValueProvider, serverValues: [String: Any]) -> FNode {

        let priorityVal = FServerValues.resolveDeferredValue(node.getPriority().val(), withExisting: existing.getChild(".priority"), serverValues: serverValues)
        let priority = FSnapshotUtilities.nodeFrom(priorityVal)
        switch node.type {
        case .empty:
            return .empty
        case let .leaf(deferredValue):
            let value = self.resolveDeferredValue(deferredValue, withExisting: existing, serverValues: serverValues)
            if value == node.val() && priority == node.getPriority() {
                return node
            } else {
                return .leaf(value ?? deferredValue, priority: priority)
            }
        case let .children(children):
            var newNode = node
            if priority != node.getPriority() {
                newNode = newNode.updatePriority(priority)
            }
            for (childKey, childNode) in children {
                let newChildNode = FServerValues.resolveDeferredValueSnapshot(childNode, withValueProvider: existing.getChild(childKey.key), serverValues: serverValues)

                if newChildNode != childNode {
                    newNode = newNode.updateImmediateChild(childKey.key, withNewChild: newChildNode)
                }
            }
            return newNode
        }
    }

    static func generateServerValues(_ clock: FClock) -> [String: Any] {
        let millis = UInt64(clock.currentTime * 1000)
        let nsnum = NSNumber(value: millis)
        return [ kTimestamp: nsnum ]
    }

    static func resolveDeferredValueCompoundWrite(_ write: FCompoundWrite, withSyncTree tree: FSyncTree, atPath path: FPath, serverValues: [String: Any]) -> FCompoundWrite {
        var resolved = write
        write.enumerateWrites { subPath, node, stop in
            let existing = DeferredValueProvider(syncTree: tree, atPath: path.child(subPath))
            let resolvedNode = FServerValues.resolveDeferredValueSnapshot(node, withValueProvider: existing, serverValues: serverValues)
            // Node actually changed, use pointer inequality here
            if resolvedNode != node {
                resolved = resolved.addWrite(resolvedNode, atPath: subPath)
            }
        }
        return resolved
    }

    static func resolveDeferredValueSnapshot(_ node: FNode, withSyncTree tree: FSyncTree, atPath path: FPath, serverValues: [String: Any]) -> FNode {
        let jitExisting = DeferredValueProvider(syncTree: tree, atPath: path)
        return FServerValues.resolveDeferredValueSnapshot(node, withValueProvider: jitExisting, serverValues: serverValues)
    }

    static func resolveDeferredValueSnapshot(_ node: FNode, withExisting existing: FNode?, serverValues: [String: Any]) -> FNode {
        let jitExisting = ExistingValueProvider(snapshot: existing)
        return FServerValues.resolveDeferredValueSnapshot(node, withValueProvider: jitExisting, serverValues: serverValues)
    }
}
