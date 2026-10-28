// Copyright 2017 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
