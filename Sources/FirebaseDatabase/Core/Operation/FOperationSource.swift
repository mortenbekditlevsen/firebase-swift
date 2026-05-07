//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

enum FOperationSource {
    case user
    case server(taggedParams: FQueryParams?)

    static var serverInstance: FOperationSource {
        .server(taggedParams: nil)
    }

    static func forServerTaggedQuery(_ params: FQueryParams) -> FOperationSource {
        .server(taggedParams: params)
    }

    var fromUser: Bool {
        if case .user = self {
            return true
        }
        return false
    }

    var fromServer: Bool {
        if case .server = self {
            return true
        }
        return false
    }

    var isTagged: Bool {
        if case .server(let taggedParams) = self, taggedParams != nil {
            return true
        }
        return false
    }

    var queryParams: FQueryParams? {
        if case .server(let taggedParams) = self {
            return taggedParams
        }
        return nil
    }

    var description: String {
        "FOperationSource { fromUser=\(fromUser), fromServer=\(fromServer), queryParams=\(String(describing: queryParams)), tagged=\(isTagged) }"
    }
}
