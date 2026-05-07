//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

class FViewProcessorResult {
    public let viewCache: FViewCache
    /**
     * List of FChanges.
     */
    public let changes: [FChange]

    init(viewCache: FViewCache, changes: [FChange]) {
        self.viewCache = viewCache
        self.changes = changes
    }
}
/*
 */
