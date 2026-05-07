//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 01/04/2022.
//

import Foundation

/// Holds the resolved server values (currently just a timestamp).
/// Replaces the previous `[String: Any]` dictionary that was passed around.
struct ServerValues: Sendable {
    /// The key used in scalar server value placeholders, e.g. `{".sv": "timestamp"}`.
    static let timestampKey = "timestamp"
    /// The key used in increment server value placeholders, e.g. `{".sv": {"increment": 1}}`.
    static let incrementKey = "increment"

    /// The server timestamp in milliseconds since epoch.
    let timestamp: Double

    /// Resolves a server value operation to a concrete leaf value.
    func resolve(_ op: ServerValueOp, withExisting existing: ValueProvider) -> LeafValue {
        switch op {
        case .timestamp:
            return .double(timestamp)
        case .increment(let delta):
            return Self.resolveIncrement(delta, withExisting: existing)
        }
    }

    private static func resolveIncrement(_ delta: Double, withExisting jitExisting: ValueProvider) -> LeafValue {
        // Incrementing a non-number sets the value to the incremented amount
        guard case let .leaf(existingValue) = jitExisting.value?.type else {
            return .double(delta)
        }
        guard case let .double(existingDouble) = existingValue else {
            return .double(delta)
        }
        if isIntegerDouble(delta) && isIntegerDouble(existingDouble) {
            let x = Int64(delta)
            let y = Int64(existingDouble)
            let (r, overflow) = x.addingReportingOverflow(y)
            if !overflow {
                return .double(Double(r))
            }
        }
        return .double(delta + existingDouble)
    }
}

/// Checks if a Double value can be exactly represented as an integer (Int64).
private func isIntegerDouble(_ value: Double) -> Bool {
    value == value.rounded(.towardZero) &&
    value >= Double(Int64.min) &&
    value <= Double(Int64.max)
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
    private static func resolveDeferredValue(_ val: LeafValue, withExisting existing: ValueProvider, serverValues: ServerValues) -> LeafValue {
        guard case let .deferredValue(op) = val else {
            return val
        }
        return serverValues.resolve(op, withExisting: existing)
    }

    private static func resolveDeferredValueSnapshot(_ node: FNode,
                                                     withValueProvider existing: ValueProvider, serverValues: ServerValues) -> FNode {

        // Resolve priority if it's a deferred value
        let priority: FNode
        if case let .leaf(priorityLeaf) = node.getPriority().type {
            let resolvedPriority = FServerValues.resolveDeferredValue(priorityLeaf, withExisting: existing.getChild(".priority"), serverValues: serverValues)
            priority = FSnapshotUtilities.nodeFrom(resolvedPriority.foundationValue)
        } else {
            priority = node.getPriority()
        }

        switch node.type {
        case .empty:
            return .empty
        case let .leaf(leafValue):
            let resolvedValue = self.resolveDeferredValue(leafValue, withExisting: existing, serverValues: serverValues)
            if resolvedValue == leafValue && priority == node.getPriority() {
                return node
            } else {
                return .leaf(resolvedValue, priority: priority)
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

    static func generateServerValues(_ clock: FClock) -> ServerValues {
        let millis = Double(UInt64(clock.currentTime * 1000))
        return ServerValues(timestamp: millis)
    }

    static func resolveDeferredValueCompoundWrite(_ write: FCompoundWrite, withSyncTree tree: FSyncTree, atPath path: FPath, serverValues: ServerValues) -> FCompoundWrite {
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

    static func resolveDeferredValueSnapshot(_ node: FNode, withSyncTree tree: FSyncTree, atPath path: FPath, serverValues: ServerValues) -> FNode {
        let jitExisting = DeferredValueProvider(syncTree: tree, atPath: path)
        return FServerValues.resolveDeferredValueSnapshot(node, withValueProvider: jitExisting, serverValues: serverValues)
    }

    static func resolveDeferredValueSnapshot(_ node: FNode, withExisting existing: FNode?, serverValues: ServerValues) -> FNode {
        let jitExisting = ExistingValueProvider(snapshot: existing)
        return FServerValues.resolveDeferredValueSnapshot(node, withValueProvider: jitExisting, serverValues: serverValues)
    }
}
