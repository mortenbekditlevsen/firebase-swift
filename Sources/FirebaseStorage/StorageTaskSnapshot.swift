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
 * `StorageTaskSnapshot` represents an immutable view of a task.
 * A snapshot contains a task, storage reference, metadata (if it exists),
 * progress, and an error (if one occurred).
 */
public struct StorageTaskSnapshot<T: Sendable>: Sendable {
  /**
   * The task this snapshot represents.
   */
   public let base: StorageBase<T>

  /**
   * Metadata returned by the task, or `nil` if no metadata returned.
   */
   public let metadata: StorageMetadata?

  /**
   * The `StorageReference` this task operates on.
   */
   public let reference: StorageReference

  /**
   * An object which tracks the progress of an upload or download.
   */
   public let progress: Progress?

  /**
   * An error raised during task execution, or `nil` if no error occurred.
   */
    public var error: Error? {
        if case .failure(let error) = status { return error }
        return nil
    }

  /**
   * The status of the task.
   */
   public let status: StorageTaskStatus<T>

  // MARK: NSObject overrides

    public var description: String {
    switch status {
    case .resume: return "<State: Resume>"
    case .progress: return "<State: Progress, Progress: \(String(describing: progress))>"
    case .pause: return "<State: Paused>"
    case .success: return "<State: Success>"
    case .failure: return "<State: Failed, Error: \(String(describing: error))"
    }
  }

  init(base: StorageBase<T>,
       state: StorageTaskState<T>,
       reference: StorageReference,
       progress: Progress,
       metadata: StorageMetadata? = nil) {
      self.base = base
      self.reference = reference
      self.progress = progress
      self.metadata = metadata
      self.status = state.status
  }
}
