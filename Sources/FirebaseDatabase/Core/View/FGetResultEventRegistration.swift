// Copyright 2026 Google LLC
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

/// Keeps a query's view in place while a `getData` result is applied to it
/// (`FSyncTree.applyGetResultForQuery`), and raises no events.
///
/// Upstream uses a new `FKeepSyncedEventRegistration` for this, which matches
/// only itself. Here registrations are removed by matcher, and `.keepSynced`
/// would also remove the query's shared keepSynced registration, so this one
/// has a matcher of its own.
struct FGetResultEventRegistration: FEventRegistration {
    func responseTo(_ eventType: DataEventType) -> Bool {
        false
    }

    func createEventFrom(_ change: FChange, query: FQuerySpec) -> FDataEvent {
        fatalError("Should never create event for FGetResultEventRegistration")
    }

    func fireEvent(_ event: FEvent) {
        fatalError("Should never raise event for FGetResultEventRegistration")
    }

    func createCancelEventFromError(_ error: Error, path: FPath) -> FCancelEvent? {
        nil
    }

    func matches(_ other: FEventRegistrationMatcher) -> Bool {
        switch other {
        case .all, .getResult:
            return true
        case .allRegular, .handle, .keepSynced:
            return false
        }
    }
}
