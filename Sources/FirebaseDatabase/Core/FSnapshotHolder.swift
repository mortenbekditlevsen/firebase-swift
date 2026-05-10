//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

struct FSnapshotHolder: Sendable {
    var rootNode = FNode.empty

    init() {}

    func getNode(_ path: FPath) -> FNode {
        rootNode.getChild(path)
    }

    mutating func updateSnapshot(_ path: FPath, withNewSnapshot newSnapshotNode: FNode) {
        self.rootNode = self.rootNode.updateChild(path, withNewChild: newSnapshotNode)
    }
}
