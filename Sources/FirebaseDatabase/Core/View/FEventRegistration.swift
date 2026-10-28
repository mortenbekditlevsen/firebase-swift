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

enum FEventRegistrationMatcher: Equatable {
    case handle(DatabaseHandle)
    case all
    case keepSynced
    case allRegular // All except 'keepSynced'
}

protocol FEventRegistration: Any {
    func responseTo(_ eventType: DataEventType) -> Bool
    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent
    func fireEvent(_ event: FEvent)
    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent?
    /**
     * Used to figure out what event registration that needs to be removed.
     */
    func matches(_ other: FEventRegistrationMatcher) -> Bool
}
