//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 19/02/2022.
//

import Foundation

struct FWriteRecord: Hashable, Equatable, Sendable {
    enum Record: Hashable, Equatable {
        case overwrite(FNode)
        case merge(FCompoundWrite)
    }
    let record: Record
    let writeId: Int
    let path: FPath
    let visible: Bool
    init(path: FPath, overwrite: FNode, writeId: Int, visible: Bool) {
        self.path = path
        self.record = .overwrite(overwrite)
        self.writeId = writeId
        self.visible = visible
    }

    init(path: FPath, merge: FCompoundWrite, writeId: Int) {
        self.path = path
        self.record = .merge(merge)
        self.writeId = writeId
        self.visible = true
    }

    var debugDescription: String {
        switch record {
        case .overwrite(let overwrite):
            return "FWriteRecord { writeId = \(writeId), path = \(path), overwrite = \(overwrite), visible = \(visible) }"
        case .merge(let merge):
            return "FWriteRecord { writeId = \(writeId), path = \(path), merge = \(merge) }"
        }
    }
}
