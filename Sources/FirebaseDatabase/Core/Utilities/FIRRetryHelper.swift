//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 07/04/2022.
//

import Foundation

private class FIRRetryHelperTask {
    var block: (() -> Void)?
    init(block: @escaping () -> Void) {
        self.block = block
    }
    var isCancelled: Bool { block == nil }
    func cancel() {
        block = nil
    }
    func execute() {
        block?()
    }
}

@DatabaseActor
class FIRRetryHelper {
    let minRetryDelayAfterFailure: TimeInterval
    let maxRetryDelay: TimeInterval
    let retryExponent: Double
    let jitterFactor: Double
    var lastWasSuccess: Bool
    var currentRetryDelay: TimeInterval = 0
    fileprivate var scheduledRetry: FIRRetryHelperTask?
    
    nonisolated
    init(minRetryDelayAfterFailure: TimeInterval,
         maxRetryDelay: TimeInterval,
         retryExponent: Double,
         jitterFactor: Double) {
        self.minRetryDelayAfterFailure = minRetryDelayAfterFailure
        self.maxRetryDelay = maxRetryDelay
        self.retryExponent = retryExponent
        self.jitterFactor = jitterFactor
        self.lastWasSuccess = true
    }
    func retry(_ block: @escaping () -> Void) {
        if let scheduledRetry {
            FFLog("I-RDB054001", "Canceling existing retry attempt")
            scheduledRetry.cancel()
            self.scheduledRetry = nil
        }
        let delay: Duration
        if lastWasSuccess {
            delay = .seconds(0)
        } else {
            if currentRetryDelay == 0 {
                currentRetryDelay = minRetryDelayAfterFailure
            } else {
                let newDelay = currentRetryDelay * retryExponent
                currentRetryDelay = min(newDelay, maxRetryDelay)
            }
            delay = .nanoseconds(Int(((1 - jitterFactor) * currentRetryDelay) + (jitterFactor * currentRetryDelay * FUtilities.randomDouble())) * 1_000_000_000)
            FFLog("I-RDB054002", "Scheduling retry in \(delay)")
        }
        lastWasSuccess = false
        let task = FIRRetryHelperTask(block: block)
        scheduledRetry = task
        Task { @DatabaseActor in
            try? await Task.sleep(for: delay)
            if !task.isCancelled {
                self.scheduledRetry = nil
                task.execute()
            }
        }
    }
    func cancel() {
        if let scheduledRetry = scheduledRetry {
            FFLog("I-RDB054003", "Canceling existing retry attempt")
            scheduledRetry.cancel()
            self.scheduledRetry = nil
        } else {
            FFLog("I-RDB054004", "No existing retry attempt to cancel")
        }
        currentRetryDelay = 0
    }

    func signalSuccess() {
        lastWasSuccess = true
        currentRetryDelay = 0
    }
}
