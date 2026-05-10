//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 28/09/2021.
//

import Foundation
/**
 * This class holds a collection of writes that can be applied to nodes in
 * unison. It abstracts away the logic with dealing with priority writes and
 * multiple nested writes. At any given path, there is only allowed to be one
 * write modifying that path. Any write to an existing path or shadowing an
 * existing path will modify that existing write to reflect the write added.
 */
struct FCompoundWrite: Hashable, Sendable {

    let writeTree: FImmutableTree<FNode>
    init(writeTree: FImmutableTree<FNode>) {
        self.writeTree = writeTree
    }

    /**
     * Creates a compound write with NSDictionary from path string to object
     */
    static func compoundWrite(valueDictionary dictionary: [String: Any]) -> FCompoundWrite {
        var writeTree: FImmutableTree<FNode> = .empty
        for (path, value) in dictionary {
            let node = FSnapshotUtilities.nodeFrom(value)
            let tree = FImmutableTree<FNode>(value: node)
            writeTree = writeTree.setTree(tree, atPath: FPath(with: path))
        }
        return FCompoundWrite(writeTree: writeTree)
    }

    static func compoundWrite(nodeDictionary dictionary: [String: FNode]) -> FCompoundWrite {
        var writeTree = FImmutableTree<FNode>.empty
        for (pathString, node) in dictionary {
            let tree = FImmutableTree(value: node)
            writeTree = writeTree.setTree(tree, atPath: FPath(with: pathString))
        }
        return FCompoundWrite(writeTree: writeTree)
    }

    public static let emptyWrite: FCompoundWrite = FCompoundWrite(writeTree: .empty)

    func addWrite(_ node: FNode, atPath path: FPath) -> FCompoundWrite {
        if path.isEmpty {
            return FCompoundWrite(writeTree: FImmutableTree(value: node))
        } else {
            if let rootMost = writeTree.findRootMostValueAndPath(path) {
                let relativePath = FPath.relativePath(from: rootMost.path, to: path)
                let value = rootMost.value.updateChild(relativePath, withNewChild: node)
                return FCompoundWrite(writeTree: self.writeTree.setValue(value, atPath: rootMost.path))
            } else {
                let subtree = FImmutableTree<FNode>(value: node)
                let newWriteTree = self.writeTree.setTree(subtree, atPath: path)
                return FCompoundWrite(writeTree: newWriteTree)
            }
        }
    }

    func addWrite(_ node: FNode, atKey key: String) -> FCompoundWrite {
        addWrite(node, atPath: FPath(with: key))
    }

    func addCompoundWrite(_ compoundWrite: FCompoundWrite, atPath path: FPath) -> FCompoundWrite {
        var newWrite = self
        compoundWrite.writeTree.forEach { childPath, value in
            newWrite = newWrite.addWrite(value, atPath: path.child(childPath))
        }
        return newWrite
    }

    /**
     * Will remove a write at the given path and deeper paths. This will
     * <em>not</em> modify a write at a higher location, which must be removed by
     * calling this method with that path.
     * @param path The path at which a write and all deeper writes should be
     * removed.
     * @return The new FWriteCompound with the removed path.
     */
    func removeWriteAtPath(_ path: FPath) -> FCompoundWrite {
        if path.isEmpty {
            return FCompoundWrite.emptyWrite
        } else {
            let newWriteTree = self.writeTree.setTree(.empty, atPath: path)
            return FCompoundWrite(writeTree: newWriteTree)
        }
    }

    var rootWrite: FNode? {
        writeTree.value
    }

    /**
     * Returns whether this FCompoundWrite will fully overwrite a node at a given
     * location and can therefore be considered "complete".
     * @param path The path to check for
     * @return Whether there is a complete write at that path.
     */
    func hasCompleteWriteAtPath(_ path: FPath) -> Bool {
        completeNodeAtPath(path) != nil
    }

    /**
     * Returns a node for a path if and only if the node is a "complete" overwrite
     * at that path. This will not aggregate writes from depeer paths, but will
     * return child nodes from a more shallow path.
     * @param path The path to get a complete write
     * @return The node if complete at that path, or nil otherwise.
     */
    func completeNodeAtPath(_ path: FPath) -> FNode? {
        guard let rootMost = self.writeTree.findRootMostValueAndPath(path) else {
            return nil
        }
        let relativePath = FPath.relativePath(from: rootMost.path, to: path)
        return rootMost.value.getChild(relativePath)
    }

    // TODO: change into traversal method...
    var completeChildren: [FNamedNode] {
        var children: [FNamedNode] = []
        if let node = writeTree.value {
            node.enumerateChildren { key, node, _ in
                children.append(FNamedNode(name: key, andNode: node))
            }
        } else {
            writeTree.forEachChild { childKey, childValue in
                if let value = childValue {
                    children.append(FNamedNode(name: childKey, andNode: value))
                }
            }
        }
        return children
    }

    var childCompoundWrites: [String: FCompoundWrite] {
        var dict: [String: FCompoundWrite] = [:]
        writeTree.forEachChildTree { childKey, childTree in
            dict[childKey] = FCompoundWrite(writeTree: childTree)
        }
        return dict
    }

    func childCompoundWriteAtPath(_ path: FPath) -> FCompoundWrite {
        if path.isEmpty {
            return self
        } else {
            if let shadowingNode = self.completeNodeAtPath(path) {
                return FCompoundWrite(writeTree: FImmutableTree(value: shadowingNode))
            } else {
                return FCompoundWrite(writeTree: writeTree.subtree(atPath: path))
            }
        }
    }

    func applySubtreeWrite(_ subtreeWrite: FImmutableTree<FNode>, atPath relativePath: FPath, toNode node: FNode) -> FNode {
        if let value = subtreeWrite.value {
            // Since a write there is always a leaf, we're done here.
            return node.updateChild(relativePath, withNewChild: value)
        } else {
            var priorityWrite: FNode? = nil
            var blockNode: FNode = node
            subtreeWrite.forEachChildTree { childKey, childTree in
                if childKey == ".priority" {
                    // Apply priorities at the end so we don't update priorities
                    // for either empty nodes or forget to apply priorities to
                    // empty nodes that are later filled.
                    assert(childTree.value != nil,
                             "Priority writes must always be leaf nodes")
                    priorityWrite = childTree.value

                } else {
                    blockNode = self.applySubtreeWrite(childTree, atPath: relativePath.child(fromString: childKey), toNode: blockNode)
                }
            }
            // If there was a priority write, we only apply it if the node is not
            // empty
            if let priorityWrite = priorityWrite, !blockNode.getChild(relativePath).isEmpty {
                blockNode = blockNode.updateChild(relativePath.child(fromString: ".priority"),
                                                  withNewChild:priorityWrite)
            }
            return blockNode
        }
    }

    /**
     * Applies this FCompoundWrite to a node. The node is returned with all writes
     * from this FCompoundWrite applied to the node.
     * @param node The node to apply this FCompoundWrite to
     * @return The node with all writes applied
     */
    func applyToNode(_ node: FNode) -> FNode {
        applySubtreeWrite(self.writeTree,
                          atPath: .empty,
                          toNode: node)
    }

    func enumerateWrites(_ block: @escaping (FPath, FNode, inout Bool) -> Void) {
        var stop = false
        // TODO: add stop to tree iterator...
        writeTree.forEach { path, value in
            if !stop {
                block(path, value, &stop)
            }
        }
    }
    
    func enumerateWrites(_ block: @escaping @Sendable (FPath, FNode, inout Bool) async -> Void) async {
        var stop = false
        // TODO: add stop to tree iterator...
        await writeTree.forEach { path, value in
            if !stop {
                await block(path, value, &stop)
            }
        }
    }


    func valForExport(_ exportFormat: Bool) -> [String: Any] {
        var dictionary: [String: Any] = [:]
        writeTree.forEach { path, value in
            dictionary[path.wireFormat()] = value.val(forExport: exportFormat)
        }
        return dictionary
    }

    /**
     * Return true if this CompoundWrite is empty and therefore does not modify any
     * nodes.
     * @return Whether this CompoundWrite is empty
     */
    var isEmpty: Bool {
        writeTree.isEmpty
    }

    var description: String {
        valForExport(true).description
    }
}
