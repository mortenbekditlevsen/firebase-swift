//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 19/02/2022.
//

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
