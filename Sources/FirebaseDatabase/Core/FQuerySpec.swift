//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 03/03/2022.
//

import Foundation

public struct FQuerySpec: Hashable, Sendable {
    public let path: FPath
    public let params: FQueryParams
    init(path: FPath, params: FQueryParams) {
        self.params = params
        self.path = path
    }

    static func defaultQueryAtPath(_ path: FPath) -> FQuerySpec {
        FQuerySpec(path: path, params: .defaultInstance)
    }

    var index: FIndex {
        params.index
    }
    var isDefault: Bool {
        params.isDefault
    }
    var loadsAllData: Bool {
        params.loadsAllData
    }

    var description: String {
        "FQuerySpec (path: \(path), params: \(params)"
    }
}
