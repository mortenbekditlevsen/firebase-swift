//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/03/2022.
//

import Foundation

class FEventRaiser {
    private let queue: DispatchQueue
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func raiseEvents(_ eventDataList: [FEvent]) {
        for event in eventDataList {
            event.fireEventOnQueue(queue)
        }
    }

    func raiseCallback(_ callback: @escaping () -> Void) {
        queue.async {
            callback()
        }
    }

    func raiseCallbacks(_ callbackList: [() -> Void]) {
        for callback in callbackList {
            queue.async {
                callback()
            }
        }
    }
}
