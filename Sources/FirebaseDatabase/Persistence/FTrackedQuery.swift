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

public struct FTrackedQuery: Hashable {
    public let queryId: Int
    public let query: FQuerySpec
    public let lastUse: TimeInterval
    public let isComplete: Bool
    public let isActive: Bool

    init(id queryId: Int, query: FQuerySpec, lastUse: TimeInterval, isActive: Bool, isComplete: Bool) {
        self.queryId = queryId
        self.query = query
        self.lastUse = lastUse
        self.isActive = isActive
        self.isComplete = isComplete
    }

    init(id queryId: Int, query: FQuerySpec, lastUse: TimeInterval, isActive: Bool) {
        self.queryId = queryId
        self.query = query
        self.lastUse = lastUse
        self.isActive = isActive
        self.isComplete = false
    }

    func updateLastUse(_ lastUse: TimeInterval) -> FTrackedQuery {
        .init(id: queryId, query: query, lastUse: lastUse, isActive: isActive, isComplete: isComplete)
    }

    func setComplete() -> FTrackedQuery {
        .init(id: queryId, query: query, lastUse: lastUse, isActive: isActive, isComplete: true)
    }

    func setActiveState(_ isActive: Bool) -> FTrackedQuery {
        .init(id: queryId, query: query, lastUse: lastUse, isActive: isActive, isComplete: true)
    }
}
