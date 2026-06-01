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
 * A superclass to all Storage tasks, including `StorageUploadTask`
 * and `StorageDownloadTask`, to provide state transitions, event raising, and common storage
 * for metadata and errors.
 *
 * Callbacks are always fired on the developer-specified callback queue.
 * If no queue is specified, it defaults to the main queue.
 * This class is thread-safe.
 */
public struct StorageBase<T: Sendable>: Sendable {
  /**
   * An immutable view of the task and associated metadata, progress, error, etc.
   */
   public var snapshot: StorageTaskSnapshot<T> {
       let progress = Progress(
        totalUnitCount: self.progress.totalUnitCount
       )
       progress.completedUnitCount = self.progress.completedUnitCount
       return StorageTaskSnapshot<T>(
        base: self,
        state: state,
        reference: reference,
        progress: progress,
        metadata: metadata
       )
   }

  // MARK: - Internal Implementations

  /**
   * State for the current task in progress.
   */
  var state: StorageTaskState<T>

  /**
   * StorageMetadata for the task in progress, or nil if none present.
   */
  var metadata: StorageMetadata?

  /**
   * Error which occurred during task execution, or nil if no error occurred.
   */
    var error: Error? {
        if case .failed(let error) = state {
            return error
        }
        return nil
    }

  /**
   * NSProgress object which tracks the progress of an observable task.
   */
  var progress: Progress

  /**
   * Reference pointing to the location the task is being performed against.
   */
  let reference: StorageReference

  let baseRequest: URLRequest

  init(reference: StorageReference) {
    self.reference = reference
      state = .queueing // XXX TODO: Part of initializer?
      progress =  Progress(totalUnitCount: 0)
    baseRequest = StorageUtils.defaultRequestForReference(reference: reference)
  }
}

/**
 * Defines task operations such as pause, resume, cancel, and enqueue for all tasks.
 *
 * All tasks are required to implement enqueue, which begins the task, and may optionally
 * implement pause, resume, and cancel, which operate on the task to pause, resume, and cancel
 * operations.
 */
public protocol StorageTaskManagement {
  /**
   * Prepares a task and begins execution.
   */
   func enqueue()

  /**
   * Pauses a task currently in progress.
   */
   func pause()

  /**
   * Cancels a task.
   */
   func cancel()

  /**
   * Resumes a paused task.
   */
   func resume()
}
