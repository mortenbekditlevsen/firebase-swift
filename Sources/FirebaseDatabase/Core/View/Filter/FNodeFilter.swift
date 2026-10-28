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
 * FNodeFilter is used to update nodes and complete children of nodes while
 * applying queries on the fly and keeping track of any child changes. This
 * class does not track value changes as value changes depend on more than just
 * the node itself. Different kind of queries require different kind of
 * implementations of this interface.
 */
protocol FNodeFilter {

/**
 * Update a single complete child in the snap. If the child equals the old child
 * in the snap, this is a no-op. The method expects an indexed snap.
 */
    func updateChildIn(_ oldSnap: FIndexedNode, forChildKey childKey: String, newChild newChildSnap: FNode, affectedPath: FPath, fromSource source: FCompleteChildSource, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode

/**
 * Update a node in full and output any resulting change from this complete
 * update.
 */
    func updateFullNode(_ oldSnap: FIndexedNode, withNewNode newSnap: FIndexedNode, accumulator optChangeAccumulator: FChildChangeAccumulator?) -> FIndexedNode


/**
 * Update the priority of the root node
 */
    func updatePriority(_ priority: FNode, forNode oldSnap: FIndexedNode) -> FIndexedNode

/**
 * Returns true if children might be filtered due to query critiera
 */
    var filtersNodes: Bool { get }

/**
 * Returns the index filter that this filter uses to get a NodeFilter that
 * doesn't filter any children.
 */
    var indexedFilter: FNodeFilter { get }

/**
 * Returns the index that this filter uses
 */
    var index: FIndex { get }
}
