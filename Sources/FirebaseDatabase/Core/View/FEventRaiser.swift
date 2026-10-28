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

@DatabaseActor
final class FEventRaiser: Sendable {
    nonisolated
    init() {
    }

    func raiseEvents(_ eventDataList: [FEvent]) {
        for event in eventDataList {
            event.fireEventOnQueue()
        }
    }

    // XXX TODO: JUST CALL?
    func raiseCallback(_ callback: @escaping @Sendable () -> Void) {
        Task { @DatabaseActor in
            callback()
        }
    }

    func raiseCallbacks(_ callbackList: [@Sendable () -> Void]) {
        for callback in callbackList {
            // XXX TODO: JUST CALL?
            Task { @DatabaseActor in
                callback()
            }
        }
    }
}
