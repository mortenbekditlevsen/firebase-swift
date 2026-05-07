//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 24/03/2022.
//

import Foundation

struct FTupleRemovedQueriesEvents {
    /**
     * `FQuerySpec`s removed with [SyncPoint removeEventRegistration:]
     */
    public let removedQueries: [FQuerySpec]
    /**
     * cancel events as FEvent
     */
    public let cancelEvents: [FEvent]
    init(removedQueries: [FQuerySpec], cancelEvents: [FEvent]) {
        self.removedQueries = removedQueries
        self.cancelEvents = cancelEvents
    }
}
