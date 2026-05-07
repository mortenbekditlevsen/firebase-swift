//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 11/10/2021.
//

import Foundation

class FParsedUrl {
    var repoInfo: FRepoInfo
    var path: FPath
    init(repoInfo: FRepoInfo, path: FPath) {
        self.repoInfo = repoInfo
        self.path = path
    }
}
