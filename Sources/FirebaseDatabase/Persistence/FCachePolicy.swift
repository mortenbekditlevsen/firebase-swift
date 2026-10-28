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

private let kFServerUpdatesBetweenCacheSizeChecks = 1000
private let kFMaxNumberOfPrunableQueriesToKeep = 1000
private let kFPercentOfQueriesToPruneAtOnce = 0.2

protocol FCachePolicy {
    func shouldPruneCache(size cacheSize: Int, numberOfTrackedQueries numTrackedQueries: Int) -> Bool
    func shouldCheckCacheSize(_ serverUpdatesSinceLastCheck: Int) -> Bool
    var percentOfQueriesToPruneAtOnce: Double { get }
    var maxNumberOfQueriesToKeep: Int { get }
}

class FLRUCachePolicy: FCachePolicy {
    public let maxSize: Int
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    func shouldPruneCache(size cacheSize: Int, numberOfTrackedQueries numTrackedQueries: Int) -> Bool {
        cacheSize > maxSize ||
        numTrackedQueries > kFMaxNumberOfPrunableQueriesToKeep
    }

    func shouldCheckCacheSize(_ serverUpdatesSinceLastCheck: Int) -> Bool {
        serverUpdatesSinceLastCheck > kFServerUpdatesBetweenCacheSizeChecks
    }

    var percentOfQueriesToPruneAtOnce: Double { kFPercentOfQueriesToPruneAtOnce }
    var maxNumberOfQueriesToKeep: Int { kFMaxNumberOfPrunableQueriesToKeep }
}

struct FNoCachePolicy: FCachePolicy {
    public static let noCachePolicy: FNoCachePolicy = FNoCachePolicy()
    func shouldCheckCacheSize(_ serverUpdatesSinceLastCheck: Int) -> Bool {
        false
    }

    func shouldPruneCache(size cacheSize: Int, numberOfTrackedQueries numTrackedQueries: Int) -> Bool {
        false
    }

    var maxNumberOfQueriesToKeep: Int {
        Int.max
    }

    var percentOfQueriesToPruneAtOnce: Double { 0 }
}
