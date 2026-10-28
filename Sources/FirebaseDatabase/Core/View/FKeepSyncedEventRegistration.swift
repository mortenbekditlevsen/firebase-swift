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
