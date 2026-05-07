//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 23/04/2022.
//

import Foundation

class FChildEventRegistration: FEventRegistration {
    private let repo: FRepo
    init(repo: FRepo, handle: DatabaseHandle, callbacks: [DataEventType: (DataSnapshot, String?) -> Void], cancelCallback: ((Error) -> Void)?) {
        self.repo = repo
        self.handle = handle
        self.callbacks = callbacks
        self.cancelCallback = cancelCallback
    }
    /**
     * Maps FIRDataEventType (as NSNumber) to fbt_void_datasnapshot_nsstring
     */
    private var callbacks: [DataEventType: (DataSnapshot, String?) -> Void]
    var cancelCallback: ((Error) -> Void)?
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

    func fireEvent(_ event: FEvent, queue: DispatchQueue) {
        if let cancelEvent = event as? FCancelEvent {
            FFLog("I-RDB061001", "Raising cancel value event on \(event.path?.description ?? "nil")")
            assert(cancelCallback != nil, "Raising a cancel event on a listener with no cancel callback")
            queue.async {
                self.cancelCallback?(cancelEvent.error)
            }
        } else if let dataEvent = event as? FDataEvent {
            FFLog("I-RDB061002", "Raising event callback (\(dataEvent.eventType)) on \(dataEvent.path?.description ?? "nil")")
            if let callback: (DataSnapshot, String?) -> Void = callbacks[dataEvent.eventType] {
                queue.async {
                    callback(dataEvent.snapshot, dataEvent.prevName)
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

