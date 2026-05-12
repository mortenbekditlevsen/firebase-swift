//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

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
