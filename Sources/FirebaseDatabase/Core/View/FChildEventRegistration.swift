//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 23/04/2022.
//

import Foundation

// XXX TODO: unchecked
final class FChildEventRegistration: FEventRegistration, @unchecked Sendable {
    private let repo: FRepo
    init(repo: FRepo, handle: DatabaseHandle, callbacks: [DataEventType: @Sendable (DataSnapshot, String?) -> Void], cancelCallback: (@Sendable (Error) -> Void)?) {
        self.repo = repo
        self.handle = handle
        self.callbacks = callbacks
        self.cancelCallback = cancelCallback
    }
    /**
     * Maps FIRDataEventType (as NSNumber) to fbt_void_datasnapshot_nsstring
     */
    private var callbacks: [DataEventType: @Sendable (DataSnapshot, String?) -> Void]
    var cancelCallback: (@Sendable (Error) -> Void)?
    var handle: DatabaseHandle

    func responseTo(_ eventType: DataEventType) -> Bool {
        callbacks[eventType] != nil
    }

    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent {
        let ref = DatabaseReference(repo: repo, path: query.path.child(fromString: change.childKey ?? ""))
        let snapshot = DataSnapshot(ref: ref, indexedNode: change.indexedNode)
        let eventData = FDataEvent(eventType: change.type, eventRegistration: self, dataSnapshot: snapshot, prevName: change.prevKey)
        return eventData
    }

    func fireEvent(_ event: FEvent) {
        if let cancelEvent = event as? FCancelEvent {
            FFLog("I-RDB061001", "Raising cancel value event on \(event.path?.description ?? "nil")")
            assert(cancelCallback != nil, "Raising a cancel event on a listener with no cancel callback")
            // XXX TODO: Just call?
            let error = cancelEvent.error
            Task { @DatabaseActor in
                self.cancelCallback?(error)
            }
        } else if let dataEvent = event as? FDataEvent {
            FFLog("I-RDB061002", "Raising event callback (\(dataEvent.eventType)) on \(dataEvent.path?.description ?? "nil")")
            if let callback: (DataSnapshot, String?) -> Void = callbacks[dataEvent.eventType] {
                // XXX TODO: Just call?
                let snapshot = dataEvent.snapshot
                let prevName = dataEvent.prevName
                Task { @DatabaseActor in
                    callback(snapshot, prevName)
                }
            }
        }
    }

    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent? {
        if cancelCallback != nil {
            return FCancelEvent(eventRegistration: self, error: error, path: path)
        } else {
            return nil
        }
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

