//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 05/03/2022.
//

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

class FNoCachePolicy: FCachePolicy {
    public static var noCachePolicy: FNoCachePolicy = FNoCachePolicy()
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
