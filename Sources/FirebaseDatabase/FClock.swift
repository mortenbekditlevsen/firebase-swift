//
//  FClock.swift
//  FClock
//
//  Created by Morten Bek Ditlevsen on 09/09/2021.
//

import Foundation

protocol FClock {
    var currentTime: TimeInterval { get }
}

class FSystemClock: FClock {
    public static var clock: FSystemClock = FSystemClock()
    var currentTime: TimeInterval {
        Date().timeIntervalSince1970
    }
}

class FOffsetClock: FClock {
    private let clock: FClock
    private let offset: TimeInterval
    init(clock: FClock, offset: TimeInterval) {
        self.clock = clock
        self.offset = offset
    }
    var currentTime: TimeInterval {
        clock.currentTime + offset
    }
}
