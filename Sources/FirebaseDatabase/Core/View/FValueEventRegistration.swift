//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

final class FValueEventRegistration: FEventRegistration, Sendable {
    let repo: FRepo
    let handle: DatabaseHandle
    let callback: (@Sendable (DataSnapshot) -> Void)?
    let cancelCallback: (@Sendable (Error) -> Void)?
    init(repo: FRepo, handle: DatabaseHandle, callback: (@Sendable (DataSnapshot) -> Void)?, cancelCallback: (@Sendable (Error) -> Void)?) {
        self.repo = repo
        self.handle = handle
        self.callback = callback
        self.cancelCallback = cancelCallback
    }

    func responseTo(_ eventType: DataEventType) -> Bool {
        eventType == .value
    }

    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent {
        let ref = DatabaseReference(repo: repo, path: query.path)
        let snapshot = DataSnapshot(ref: ref, indexedNode: change.indexedNode)
        let eventData = FDataEvent(eventType: .value, eventRegistration: self, dataSnapshot: snapshot)
        return eventData
    }

    func fireEvent(_ event: FEvent,) {
        if let cancelEvent = event as? FCancelEvent {
            FFLog("I-RDB065001", "Raising cancel value event on \(event.path?.description ?? "nil")")
            // XXX TODO: Just call?
            let error = cancelEvent.error
            Task { @DatabaseActor in
                self.cancelCallback?(error)
            }
        } else if let callback = self.callback {
            guard let dataEvent = event as? FDataEvent else { return }
            FFLog("I-RDB065002", "Raising value event on \(dataEvent.snapshot.key ?? "-")")
            // XXX TODO: Just call?
            let snapshot = dataEvent.snapshot
            Task { @DatabaseActor in
                callback(snapshot)
            }
        }
    }

    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent? {
        guard cancelCallback != nil else {
            return nil
        }
        return FCancelEvent(eventRegistration: self, error: error, path: path)
    }

    func matches(_ other: FEventRegistrationMatcher) -> Bool {
        switch other {
        case .all, .allRegular:
            return true
        case .handle(let otherHandle):
            return otherHandle == handle
        case .keepSynced:
            return false
        }
    }
}
