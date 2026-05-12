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

//private import FirebaseCoreInternal

/// A `HTTPSCallableResult` contains the result of calling a `HTTPSCallable`.
open class HTTPSCallableResult {
  /// The data that was returned from the Callable HTTPS trigger.
  ///
  /// The data is in the form of native objects. For example, if your trigger returned an
  /// array, this object would be an `Array<Any>`. If your trigger returned a JavaScript object with
  /// keys and values, this object would be an instance of `[String: Any]`.
  public let data: Any

  init(data: Any) {
    self.data = data
  }
}

/// A `HTTPSCallable` is a reference to a particular Callable HTTPS trigger in Cloud Functions.
public final class HTTPSCallable: Sendable {
  // MARK: - Private Properties

  // The functions client to use for making calls.
  private let functions: Functions

  private let url: URL

  private let options: HTTPSCallableOptions?

  private let _timeoutInterval: Mutex<TimeInterval> = .init(70)

  // MARK: - Public Properties

  /// The timeout to use when calling the function. Defaults to 70 seconds.
  public var timeoutInterval: TimeInterval {
    get { _timeoutInterval.withLock { $0 } }
    set { _timeoutInterval.withLock { $0 = newValue } }
  }

  init(functions: Functions, url: URL, options: HTTPSCallableOptions? = nil) {
    self.functions = functions
    self.url = url
    self.options = options
  }

  /// Executes this Callable HTTPS trigger asynchronously.
  ///
  /// The request to the Cloud Functions backend made by this method automatically includes a
  /// FCM token to identify the app instance. If a user is logged in with Firebase
  /// Auth, an auth ID token for the user is also automatically included.
  ///
  /// Firebase Cloud Messaging sends data to the Firebase backend periodically to collect
  /// information
  /// regarding the app instance. To stop this, see `Messaging.deleteData()`. It
  /// resumes with a new FCM Token the next time you call this method.
  ///
  /// - Parameter data: Parameters to pass to the trigger.
  /// - Throws: An error if the Cloud Functions invocation failed.
  /// - Returns: The result of the call.
  public func call(_ data: Any? = nil) async throws -> sending HTTPSCallableResult {
    try await functions
      .callFunction(at: url, withObject: data, options: options, timeout: timeoutInterval)
  }

  @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
  func stream(_ data: SendableWrapper? = nil) -> AsyncThrowingStream<JSONStreamResponse, Error> {
    functions.stream(at: url, data: data, options: options, timeout: timeoutInterval)
  }
}
