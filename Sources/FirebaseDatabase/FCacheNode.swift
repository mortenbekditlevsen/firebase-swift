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


class FCacheNode {
  var isFullyInitialized: Bool
  var isFiltered: Bool
  var indexedNode: FIndexedNode
  var node: FNode {
    indexedNode.node
  }
  init(indexedNode: FIndexedNode, isFullyInitialized: Bool, isFiltered: Bool) {
    self.indexedNode = indexedNode
    self.isFiltered = isFiltered
    self.isFullyInitialized = isFullyInitialized
  }

  func isComplete(forPath path: FPath) -> Bool {
    if let childKey = path.getFront() {
      return isComplete(forChild: childKey)
    } else { // path is empty
      return isFullyInitialized && !isFiltered
    }
  }

  func isComplete(forChild childKey: String) -> Bool {
    (isFullyInitialized && !isFiltered) || node.hasChild(childKey)
  }
}
