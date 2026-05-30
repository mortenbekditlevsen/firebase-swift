// Copyright 2022 Google LLC
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
import Synchronization

/**
 * An extended `StorageTask` providing observable semantics that can be used for responding to changes
 * in task state.
 *
 * Observers produce a `StorageHandle`, which is used to keep track of and remove specific
 * observers at a later date.
 */
open class StorageObservableTask: StorageTask, @unchecked Sendable {
  // MARK: - Mutex-protected mutable state

  struct ObserverState: ~Copyable, Sendable {
    var handlerDictionaries: [StorageTaskStatus: [String: @Sendable (StorageTaskSnapshot) -> Void]]
    var handleToStatusMap: [String: StorageTaskStatus]
  }

  let observerState: Mutex<ObserverState>

  /**
   * The file to download to or upload from
   */
  let fileURL: URL?

  // MARK: - Internal Implementations

  init(reference: StorageReference,
       queue: DispatchQueue,
       file: URL?) {
    observerState = Mutex(ObserverState(
      handlerDictionaries: [
        .resume: [String: @Sendable (StorageTaskSnapshot) -> Void](),
        .pause: [String: @Sendable (StorageTaskSnapshot) -> Void](),
        .progress: [String: @Sendable (StorageTaskSnapshot) -> Void](),
        .success: [String: @Sendable (StorageTaskSnapshot) -> Void](),
        .failure: [String: @Sendable (StorageTaskSnapshot) -> Void](),
      ],
      handleToStatusMap: [:]
    ))
    fileURL = file
    super.init(reference: reference, queue: queue)
  }

  /**
   * Observes changes in the upload status: Resume, Pause, Progress, Success, and Failure.
   * - Parameters:
   *   - status: The `StorageTaskStatus` change to observe.
   *   - handler: A callback that fires every time the status event occurs,
   *        containing a `StorageTaskSnapshot` describing task state.
   * - Returns: A task handle that can be used to remove the observer at a later date.
   */
  @discardableResult
  open func observe(_ status: StorageTaskStatus,
                    handler: @escaping @Sendable (StorageTaskSnapshot) -> Void) -> String {
    // Note: self.snapshot is synchronized
    let snapshot = self.snapshot

    // TODO: use an increasing counter instead of a random UUID
    let uuidString = updateHandlerDictionary(for: status, with: handler)

    let handlerDictionary = observerState.withLock {
      $0.handlerDictionaries[status]
    }
    if let handlerDictionary {
      switch status {
      case .pause:
        if state == .pausing || state == .paused {
          fire(handlers: handlerDictionary, snapshot: snapshot)
        }
      case .resume:
        if state == .resuming || state == .running {
          fire(handlers: handlerDictionary, snapshot: snapshot)
        }
      case .progress:
        if state == .running || state == .progress {
          fire(handlers: handlerDictionary, snapshot: snapshot)
        }
      case .success:
        if state == .success {
          fire(handlers: handlerDictionary, snapshot: snapshot)
        }
      case .failure:
        if state == .failed || state == .failing {
          fire(handlers: handlerDictionary, snapshot: snapshot)
        }
      case .unknown: fatalError("Invalid observer status requested, use one " +
          "of: Pause, Resume, Progress, Complete, or Failure")
      }
    }

    observerState.withLock { $0.handleToStatusMap[uuidString] = status }

    return uuidString
  }

  /**
   * Removes the single observer with the provided handle.
   * - Parameter handle: The handle of the task to remove.
   */
  open func removeObserver(withHandle handle: String) {
    observerState.withLock { state in
      if let status = state.handleToStatusMap[handle] {
        state.handlerDictionaries[status]?.removeValue(forKey: handle)
        state.handleToStatusMap.removeValue(forKey: handle)
      }
    }
  }

  /**
   * Removes all observers for a single status.
   * - Parameter status: A `StorageTaskStatus` to remove all listeners for.
   */
  open func removeAllObservers(for status: StorageTaskStatus) {
    observerState.withLock { state in
      if let handlerDictionary = state.handlerDictionaries[status] {
        for (key, _) in handlerDictionary {
          state.handleToStatusMap.removeValue(forKey: key)
        }
        state.handlerDictionaries[status]?.removeAll()
      }
    }
  }

  /**
   * Removes all observers.
   */
  open func removeAllObservers() {
    observerState.withLock { state in
      for (status, _) in state.handlerDictionaries {
        state.handlerDictionaries[status]?.removeAll()
      }
      state.handleToStatusMap.removeAll()
    }
  }

  func updateHandlerDictionary(for status: StorageTaskStatus,
                               with handler: @escaping (@Sendable (StorageTaskSnapshot) -> Void))
    -> String {
    // TODO: use an increasing counter instead of a random UUID
    let uuidString = NSUUID().uuidString
    observerState.withLock { $0.handlerDictionaries[status]?[uuidString] = handler }
    return uuidString
  }

  func fire(for status: StorageTaskStatus, snapshot: StorageTaskSnapshot) {
    let observerDictionary = observerState.withLock {
      $0.handlerDictionaries[status]
    }
    if let observerDictionary {
      fire(handlers: observerDictionary, snapshot: snapshot)
    }
  }

  func fire(handlers: [String: (StorageTaskSnapshot) -> Void],
            snapshot: StorageTaskSnapshot) {
    for (_, handler) in handlers {
      reference.storage.callbackQueue.async {
        handler(snapshot)
      }
    }
  }
}
