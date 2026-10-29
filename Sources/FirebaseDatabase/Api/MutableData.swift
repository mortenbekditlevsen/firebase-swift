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
 * A MutableData value is populated with data from a Firebase Database
 * location. When you are using runTransactionBlock:, you will be given a
 * value containing the current data at that location. Your block will be
 * responsible for updating it to the data you wish to save at that
 * location, and then returning using `TransactionResult.success(withValue:)`.
 *
 * To modify the data, set its value property to any of the native types support
 * by Firebase Database:
 *
 * + NSNumber (includes BOOL)
 * + NSDictionary
 * + NSArray
 * + NSString
 * + nil / NSNull to remove the data
 *
 * Unlike upstream's FIRMutableData, this is a value type: a copy can't change
 * the data of the transaction it came from. `childData(byAppendingPath:)` and
 * `children` return copies; to change a child in place, use
 * `self[childPath:]`, e.g. `currentData[childPath: "count"].value = 1`.
 */
public struct MutableData: Sendable {

    internal private(set) var nodeValue: FNode

    /**
     * @return The key name of this node, or nil if it is the top-most location
     */
    public let key: String?

    internal init(node: FNode, key: String? = nil) {
        self.nodeValue = node
        self.key = key
    }

    // MARK: - Inspecting and navigating the data

    /**
     * Returns boolean indicating whether this mutable data has children.
     *
     * @return YES if this data contains child nodes.
     */
    public func hasChildren() -> Bool {
        !nodeValue.children.isEmpty
    }

    /**
     * Indicates whether this mutable data has a child at the given path.
     *
     * @param path A path string, consisting either of a single segment, like
     * 'child', or multiple segments, 'a/deeper/child'
     * @return YES if this data contains a child at the specified relative path
     */
    public func hasChild(atPath path: String) -> Bool {
        !nodeValue.getChild(FPath(with: path)).isEmpty
    }

    /**
     * Returns a copy of the data at the given relative path. Changes made to
     * the copy don't affect this value; use `self[childPath:]` for that.
     *
     * @param path A path string, consisting either of a single segment, like
     * 'child', or multiple segments, 'a/deeper/child'
     * @return A MutableData value containing the data at the given path
     */
    public func childData(byAppendingPath path: String) -> MutableData {
        self[childPath: path]
    }

    /**
     * The data at the given relative path. Setting it replaces that child,
     * so `currentData[childPath: "a/b"].value = 1` changes this value.
     *
     * @param path A path string, consisting either of a single segment, like
     * 'child', or multiple segments, 'a/deeper/child'
     */
    public subscript(childPath path: String) -> MutableData {
        get {
            let childPath = FPath(with: path)
            return MutableData(node: nodeValue.getChild(childPath), key: childPath.getBack() ?? key)
        }
        set {
            nodeValue = nodeValue.updateChild(FPath(with: path), withNewChild: newValue.nodeValue)
        }
    }

    // MARK: - Properties

    /**
     * To modify the data contained by this value, set this to
     * any of the native types supported by Firebase Database:
     *
     * + NSNumber (includes BOOL)
     * + NSDictionary
     * + NSArray
     * + NSString
     * + nil / NSNull to remove the data
     *
     * Note that setting this value will override the priority at this location.
     *
     * @return The current data at this location as a native object
     */
    public var value: Any? {
        get {
            nodeValue.val()
        }
        set {
            nodeValue = FSnapshotUtilities.nodeFrom(newValue, withValidationFrom: "setValue:")
        }
    }

    /**
     * Set this property to update the priority of the data at this location. Can be
     * set to the following types:
     *
     * + NSNumber
     * + NSString
     * + nil / NSNull to remove the priority
     *
     * @return The priority of the data at this location
     */
    public var priority: Any? {
        get {
            nodeValue.getPriority().val()
        }
        set {
            nodeValue = nodeValue.updatePriority(FSnapshotUtilities.nodeFrom(newValue))
        }
    }

    /**
     * @return The number of child nodes at this location
     */
    public var childrenCount: Int {
        nodeValue.numChildren()
    }

    /**
     * Copies of the immediate children of this location, in priority order.
     */
    public var children: [MutableData] {
        FIndexedNode(node: nodeValue).children.map { namedNode in
            MutableData(node: namedNode.node, key: namedNode.name)
        }
    }
}

extension MutableData: CustomStringConvertible {
    public var description: String {
        if let key = key {
            return "MutableData (\(key)) \(String(describing: value))"
        } else {
            return "MutableData (top-most transaction) \(String(describing: value))"
        }
    }
}
