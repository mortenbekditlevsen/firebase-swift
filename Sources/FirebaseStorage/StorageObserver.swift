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

/**
 * An extended `StorageTask` providing observable semantics that can be used for responding to changes
 * in task state.
 *
 * Observers produce a `StorageHandle`, which is used to keep track of and remove specific
 * observers at a later date.
 */

@StorageActor
class StorageObserver<T: Sendable> {
    typealias Stream = AsyncThrowingStream<StorageTaskSnapshot<T>, Error>
    typealias Handler = Stream.Continuation

    var handlers: [String: Handler] = [:]
    var base: StorageBase<T>
  /**
   * The file to download to or upload from
   */
  let fileURL: URL?

  // MARK: - Internal Implementations

  nonisolated init(reference: StorageReference,
                   file: URL?) {
      fileURL = file
      self.base = StorageBase(reference: reference)
  }

  /**
   * Observes changes in the upload status: Resume, Pause, Progress, Success, and Failure.
   * - Parameters:
   *   - status: The `StorageTaskStatus` change to observe.
   *   - handler: A callback that fires every time the status event occurs,
   *        containing a `StorageTaskSnapshot` describing task state.
   * - Returns: A task handle that can be used to remove the observer at a later date.
   */
    func observe(handle: String) -> Stream {
        let snapshot = base.snapshot
        
        let (stream, continuation) = Stream.makeStream()
        
        updateHandlerDictionary(handle: handle, with: continuation)
        
        defer {
            fire(snapshot: snapshot)
        }
        
        return stream
    }

  /**
   * Removes the single observer with the provided handle.
   * - Parameter handle: The handle of the task to remove.
   */
  open func removeObserver(withHandle handle: String) {
      handlers.removeValue(forKey: handle)
  }

  /**
   * Removes all observers.
   */
    private func removeAllObservers() {
      handlers.removeAll()
  }

    func updateHandlerDictionary(handle: String,
                                 with continuation: Handler) {
        handlers[handle] = continuation
    }

  func fire(state: StorageTaskState<T>) {
      base.state = state
      let snapshot = base.snapshot
      fire(snapshot: snapshot)
  }
    
    func succeed(with result: T) {
        self.fire(state: .success(result))
    }
    
    func fail(with error: Error) {
        self.fire(state: .failed(error))
    }
    
    func fire(snapshot: StorageTaskSnapshot<T>) {
        for handler in handlers.values {
            handler.yield(snapshot)

            switch snapshot.status {
            case .failure:
                handler.finish(throwing: snapshot.error!)
            case .success:
                handler.finish()
            case .pause, .progress, .resume:
                ()
            }
        }
        
        switch snapshot.status {
        case .failure, .success:
            self.removeAllObservers()
        case .pause, .progress, .resume:
            ()
        }
        
  }
}
