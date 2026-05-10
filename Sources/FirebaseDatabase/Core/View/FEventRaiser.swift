//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

@DatabaseActor
final class FEventRaiser: Sendable {
    private let queue: DispatchQueue
    nonisolated
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func raiseEvents(_ eventDataList: [FEvent]) {
        for event in eventDataList {
            event.fireEventOnQueue(queue)
        }
    }

    func raiseCallback(_ callback: @escaping @Sendable () -> Void) {
        queue.async {
            callback()
        }
    }

    func raiseCallbacks(_ callbackList: [@Sendable () -> Void]) {
        for callback in callbackList {
            queue.async {
                callback()
            }
        }
    }
}
