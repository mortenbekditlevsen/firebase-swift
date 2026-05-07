//
//  File.swift
//  File
//
//  Created by Morten Bek Ditlevsen on 21/09/2021.
//

import Foundation

struct FTuplePathValue {
    public private(set) var path: FPath
    public private(set) var value: Any

    init(path: FPath, value: Any) {
        self.path = path
        self.value = value
    }
}
