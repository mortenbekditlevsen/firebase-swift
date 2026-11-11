// Copyright 2026 Google LLC
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
 * The writes the server makes at a location when this client disconnects
 * (`DatabaseReference.onDisconnect`).
 *
 * As with the reference's writes, each has a plain form that queues it, and an
 * `…AndWait` form that returns once the server has accepted it (and throws if
 * it didn't).
 */
public struct OnDisconnect: Sendable {
    /// The location the writes are made at.
    public let ref: DatabaseReference

    /// Sets the value at this location when the client disconnects.
    public func setValue(_ value: Any?) {
        set(value, priority: nil, from: "onDisconnectSetValue:", completion: nil)
    }

    /// `setValue(_:)`, returning once the server has accepted it.
    public func setValueAndWait(_ value: Any?) async throws {
        try await wait { set(value, priority: nil, from: "onDisconnectSetValue:withCompletionBlock:", completion: $0) }
    }

    /// Sets the value and priority at this location when the client
    /// disconnects.
    public func setValue(_ value: Any?, andPriority priority: Any?) {
        set(value, priority: priority, from: "onDisconnectSetValue:andPriority:", completion: nil)
    }

    /// `setValue(_:andPriority:)`, returning once the server has accepted it.
    public func setValueAndWait(_ value: Any?, andPriority priority: Any?) async throws {
        try await wait {
            set(value, priority: priority, from: "onDisconnectSetValue:andPriority:withCompletionBlock:", completion: $0)
        }
    }

    /// Removes the data at this location when the client disconnects.
    public func removeValue() {
        set(nil, priority: nil, from: "onDisconnectRemoveValue", completion: nil)
    }

    /// `removeValue()`, returning once the server has accepted it.
    public func removeValueAndWait() async throws {
        try await wait { set(nil, priority: nil, from: "onDisconnectRemoveValueWithCompletionBlock:", completion: $0) }
    }

    /// Updates the children at this location when the client disconnects.
    public func updateChildValues(_ values: [String: Any]) {
        update(values, from: "onDisconnectUpdateChildValues:", completion: nil)
    }

    /// `updateChildValues(_:)`, returning once the server has accepted it.
    public func updateChildValuesAndWait(_ values: [String: Any]) async throws {
        try await wait { update(values, from: "onDisconnectUpdateChildValues:withCompletionBlock:", completion: $0) }
    }

    /// Cancels the writes queued for this location and its children.
    public func cancel() {
        cancel(completion: nil)
    }

    /// `cancel()`, returning once the server has cancelled them.
    public func cancelAndWait() async throws {
        try await wait { cancel(completion: $0) }
    }

    // MARK: -

    private typealias Completion = @Sendable (Error?, DatabaseReference) -> Void

    private func set(_ value: Any?, priority: Any?, from fn: String, completion: Completion?) {
        FValidation.validateFrom(fn, writablePath: ref.path)
        let node = FSnapshotUtilities.nodeFrom(value, priority: priority, withValidationFrom: fn)
        ref.repo.enqueue { [path = ref.path] repo in
            repo.onDisconnectSet(path, withNode: node, withCallback: completion)
        }
    }

    private func update(_ values: [String: Any], from fn: String, completion: Completion?) {
        FValidation.validateFrom(fn, writablePath: ref.path)
        let merge = FSnapshotUtilities.compoundWriteFromDictionary(values, withValidationFrom: fn)
        ref.repo.enqueue { [path = ref.path] repo in
            repo.onDisconnectUpdate(path, withNodes: merge, withCallback: completion)
        }
    }

    private func cancel(completion: Completion?) {
        ref.repo.enqueue { [path = ref.path] repo in
            repo.onDisconnectCancel(path, withCallback: completion)
        }
    }

    private func wait(_ start: (@escaping Completion) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            start { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
