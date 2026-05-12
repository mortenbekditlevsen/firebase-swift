//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

class FDataEvent: FEvent {
    public let eventRegistration: FEventRegistration
    public let snapshot: DataSnapshot
    public let prevName: String?
    public let eventType: DataEventType

    init(eventType: DataEventType, eventRegistration: FEventRegistration, dataSnapshot: DataSnapshot) {
        self.eventType = eventType
        self.eventRegistration = eventRegistration
        self.snapshot = dataSnapshot
        self.prevName = nil
    }
    init(eventType: DataEventType, eventRegistration: FEventRegistration, dataSnapshot: DataSnapshot, prevName: String?) {
        self.eventType = eventType
        self.eventRegistration = eventRegistration
        self.snapshot = dataSnapshot
        self.prevName = prevName
    }

    var path: FPath? {
        // Used for logging, so delay calculation
        let ref = self.snapshot.ref
        if (eventType == .value) {
            return ref.path
        } else {
            return ref.parent?.path
        }
    }

    func fireEventOnQueue() {
        eventRegistration.fireEvent(self)
    }
    var isCancelEvent: Bool { false }

    var description: String {
        if let value = snapshot.value {
            return "event \(eventType), data: \(value)"
        } else {
            return "event \(eventType), data: nil"
        }
    }
}
