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
 * A FIRDataSnapshot contains data from a Firebase Database location. Any time
 * you read Firebase data, you receive the data as a FIRDataSnapshot.
 *
 * FIRDataSnapshots are passed to the blocks you attach with
 * observeEventType:withBlock: or observeSingleEvent:withBlock:. They are
 * efficiently-generated immutable copies of the data at a Firebase Database
 * location. They can't be modified and will never change. To modify data at a
 * location, use a FIRDatabaseReference (e.g. with setValue:).
 */
public struct DataSnapshot: Sendable {
    let node: FIndexedNode

    init(ref: DatabaseReference, indexedNode: FIndexedNode) {
        self.ref = ref
        self.node = indexedNode
    }

    // MARK: - Navigating and inspecting a snapshot

    /**
     * Gets a FIRDataSnapshot for the location at the specified relative path.
     * The relative path can either be a simple child key (e.g. 'fred')
     * or a deeper slash-separated path (e.g. 'fred/name/first'). If the child
     * location has no data, an empty FIRDataSnapshot is returned.
     *
     * @param childPathString A relative path to the location of child data.
     * @return The FIRDataSnapshot for the child location.
     */
    public func childSnapshot(forPath childPathString: String) -> DataSnapshot {
        FValidation.validateFrom("child:", validPathString: childPathString)
        let childPath = FPath(with: childPathString)
        let childRef = self.ref.child(childPathString)
        let childNode = node.node.getChild(childPath)
        return DataSnapshot(ref: childRef, indexedNode: FIndexedNode.indexedNode(node: childNode))
    }

    /**
     * Return YES if the specified child exists.
     *
     * @param childPathString A relative path to the location of a potential child.
     * @return YES if data exists at the specified childPathString, else NO.
     */
    public func hasChild(_ childPathString: String) -> Bool {
        FValidation.validateFrom("hasChild:", validPathString: childPathString)
        let childPath = FPath(with: childPathString)
        return !node.node.getChild(childPath).isEmpty
    }

    /**
     * Return YES if the DataSnapshot has any children.
     *
     * @return YES if this snapshot has any children, else NO.
     */
    public func hasChildren() -> Bool {
        if node.node.isLeafNode() {
            return false
        } else {
            return !self.node.node.isEmpty
        }
    }

    /**
     * Return YES if the DataSnapshot contains a non-null value.
     *
     * @return YES if this snapshot contains a non-null value, else NO.
     */
    public func exists() -> Bool {
        !node.node.isEmpty
    }

    // MARK: - Data export

    /**
     * Returns the raw value at this location, coupled with any metadata, such as
     * priority.
     *
     * Priorities, where they exist, are accessible under the ".priority" key in
     * instances of NSDictionary. For leaf locations with priorities, the value will
     * be under the ".value" key.
     */
    func valueInExportFormat() -> Any? {
        node.node.val(forExport: true)
    }

    // MARK: - Properties

    /**
     * Returns the contents of this data snapshot as native types.
     *
     * Data types returned:
     * + NSDictionary
     * + NSArray
     * + NSNumber (also includes booleans)
     * + NSString
     *
     * @return The data as a native object.
     */
    public var value: Any? {
        node.node.val()
    }

    /**
     * Gets the number of children for this DataSnapshot.
     *
     * @return An integer indicating the number of children.
     */
    public var childrenCount: Int {
        node.node.numChildren()
    }

    /**
     * Gets a FIRDatabaseReference for the location that this data came from.
     *
     * @return A FIRDatabaseReference instance for the location of this data.
     */
    public let ref: DatabaseReference

    /**
     * The key of the location that generated this FIRDataSnapshot.
     *
     * @return An NSString containing the key for the location of this
     * FIRDataSnapshot.
     */
    public var key: String? {
        ref.key
    }

    public var children: [DataSnapshot] {
        node.children.map { namedNode -> DataSnapshot in
            let childRef = self.ref.child(namedNode.name)
            return DataSnapshot(ref: childRef, indexedNode: FIndexedNode(node: namedNode.node))
        }
    }

    var description: String {
        "Snap (\(key ?? "-")) \(node.node)"
    }

    /**
     * The priority of the data in this FIRDataSnapshot.
     *
     * @return The priority as a string, or nil if no priority was set.
     */
    public var priority: Any? {
        node.node.getPriority().val()
    }
}
