//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

struct FKeepSyncedEventRegistration: FEventRegistration {
    static let instance: FKeepSyncedEventRegistration = .init()
    func responseTo(_ eventType: DataEventType) -> Bool {
        false
    }
    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent {
        fatalError("Should never create event for FKeepSyncedEventRegistration")
    }

    func fireEvent(_ event: FEvent) {
        fatalError("Should never raise event for FKeepSyncedEventRegistration")
    }
    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent? {
        // Don't create cancel events....
        fatalError()
    }

    func matches(_ other: FEventRegistrationMatcher) -> Bool {
        switch other {
        case .all, .keepSynced:
            return true
        case .allRegular, .handle:
            return false
        }
    }

}
