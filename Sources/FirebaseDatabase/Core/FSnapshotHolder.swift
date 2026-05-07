//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

class FSnapshotHolder {
    var rootNode = FNode.empty

    init() {}

    func getNode(_ path: FPath) -> FNode {
        rootNode.getChild(path)
    }

    func updateSnapshot(_ path: FPath, withNewSnapshot newSnapshotNode: FNode) {
        self.rootNode = self.rootNode.updateChild(path, withNewChild: newSnapshotNode)
    }
}
