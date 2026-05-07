//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

enum FEventRegistrationMatcher: Equatable {
    case handle(DatabaseHandle)
    case all
    case keepSynced
    case allRegular // All except 'keepSynced'
}

protocol FEventRegistration: Any {
    func responseTo(_ eventType: DataEventType) -> Bool
    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent
    func fireEvent(_ event: FEvent, queue: DispatchQueue)
    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent?
    /**
     * Used to figure out what event registration that needs to be removed.
     */
    func matches(_ other: FEventRegistrationMatcher) -> Bool
}
