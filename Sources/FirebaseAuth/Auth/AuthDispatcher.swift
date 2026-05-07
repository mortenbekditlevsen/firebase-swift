// Copyright 2023 Google LLC
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

/** @class AuthDispatcher
    @brief A utility class used to facilitate scheduling tasks to be executed in the future.
 */
final class AuthDispatcher: Sendable {
  static let shared = AuthDispatcher()

  /// Allows custom implementation of `dispatch(afterDelay:queue:task:)`.
  /// Set to `nil` to restore default implementation.
  private let _dispatchAfterImplementation:
    Mutex<(@Sendable (TimeInterval, DispatchQueue, @escaping @Sendable () -> Void) -> Void)?> = .init(nil)

  var dispatchAfterImplementation:
    (@Sendable (TimeInterval, DispatchQueue, @escaping @Sendable () -> Void) -> Void)? {
    get { _dispatchAfterImplementation.withLock { $0 } }
    set { _dispatchAfterImplementation.withLock { $0 = newValue } }
  }

  /// Schedules `task` to run after `delay` on `queue`.
  func dispatch(afterDelay delay: TimeInterval,
                queue: DispatchQueue,
                task: @escaping @Sendable () -> Void) {
    if let impl = _dispatchAfterImplementation.withLock({ $0 }) {
      impl(delay, queue, task)
    } else {
      queue.asyncAfter(deadline: DispatchTime.now() + delay, execute: task)
    }
  }
}
