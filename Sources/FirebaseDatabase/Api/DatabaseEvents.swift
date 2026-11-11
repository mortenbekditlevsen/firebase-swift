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

/// A change to one of a location's children.
public struct ChildEvent: Sendable {
    public enum Kind: Sendable, CaseIterable {
        /// A child was added.
        case added
        /// A child was removed; `snapshot` has its last data.
        case removed
        /// A child's data changed.
        case changed
        /// A child moved relative to the others (in the query's order).
        case moved
    }

    public let kind: Kind
    /// The child.
    public let snapshot: DataSnapshot
    /// The key of the child before it in the query's order, or nil if it's
    /// the first. (Nil for removals.)
    public let previousSiblingKey: String?
}

extension ChildEvent.Kind {
    var eventType: DataEventType {
        switch self {
        case .added: .childAdded
        case .removed: .childRemoved
        case .changed: .childChanged
        case .moved: .childMoved
        }
    }
}

/**
 * The events at a location or query, as they happen.
 *
 * Iterating (making an iterator) starts listening, in order with the other
 * calls made on the database: a write made after it is seen. The first
 * element is the current data (from the cache if there is some, else once the
 * server sends it), and later elements follow its changes. Stopping the
 * iteration (or cancelling its task) stops listening. Each iteration listens
 * on its own.
 *
 * Throws if the client loses permission to read the data.
 */
public struct DatabaseEvents<Element: Sendable>: AsyncSequence, Sendable {
    public typealias Failure = any Error
    typealias Continuation = AsyncThrowingStream<Element, any Error>.Continuation

    private let query: DatabaseQuery
    private let bufferingPolicy: Continuation.BufferingPolicy
    private let makeRegistration: @Sendable (FRepo, DatabaseHandle, Continuation) -> FEventRegistration

    init(query: DatabaseQuery,
         bufferingPolicy: Continuation.BufferingPolicy,
         makeRegistration: @escaping @Sendable (FRepo, DatabaseHandle, Continuation) -> FEventRegistration) {
        self.query = query
        self.bufferingPolicy = bufferingPolicy
        self.makeRegistration = makeRegistration
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(stream: listen())
    }

    /// Starts listening, in order with the repo's other operations.
    private func listen() -> AsyncThrowingStream<Element, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        let repo = query.repo
        let querySpec = query.querySpec
        let handle = FUtilities.LUIDGenerator()
        let registration = makeRegistration(repo, handle, continuation)
        repo.enqueue { $0.addEventRegistration(registration, forQuery: querySpec) }
        continuation.onTermination = { _ in
            repo.enqueue { $0.removeEventRegistration(.handle(handle), forQuery: querySpec) }
        }
        return stream
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var stream: AsyncThrowingStream<Element, any Error>.AsyncIterator

        fileprivate init(stream: AsyncThrowingStream<Element, any Error>) {
            self.stream = stream.makeAsyncIterator()
        }

        public mutating func next() async throws -> Element? {
            try await stream.next()
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async throws -> Element? {
            try await stream.next(isolation: actor)
        }
    }
}

extension DatabaseQuery {
    /**
     * The data at this location or query, now and after each change.
     *
     * - Parameter bufferingPolicy: The snapshots kept while the iteration
     *   doesn't keep up. `.bufferingNewest(1)` skips to the latest, which
     *   suits a UI; by default all are kept.
     */
    public func values(
        bufferingPolicy: AsyncThrowingStream<DataSnapshot, any Error>.Continuation.BufferingPolicy = .unbounded
    ) -> DatabaseEvents<DataSnapshot> {
        DatabaseEvents(query: self, bufferingPolicy: bufferingPolicy) { repo, handle, continuation in
            FValueEventRegistration(repo: repo, handle: handle,
                                    callback: { continuation.yield($0) },
                                    cancelCallback: { continuation.finish(throwing: $0) })
        }
    }

    /**
     * The changes to this location's (or query's) children: first an `.added`
     * for each current child, in order, then each change as it happens.
     *
     * - Parameter kinds: The kinds of changes to report.
     */
    public func childEvents(
        _ kinds: Set<ChildEvent.Kind> = Set(ChildEvent.Kind.allCases),
        bufferingPolicy: AsyncThrowingStream<ChildEvent, any Error>.Continuation.BufferingPolicy = .unbounded
    ) -> DatabaseEvents<ChildEvent> {
        DatabaseEvents(query: self, bufferingPolicy: bufferingPolicy) { repo, handle, continuation in
            var callbacks: [DataEventType: @Sendable (DataSnapshot, String?) -> Void] = [:]
            for kind in kinds {
                callbacks[kind.eventType] = { snapshot, previousSiblingKey in
                    continuation.yield(ChildEvent(kind: kind, snapshot: snapshot,
                                                  previousSiblingKey: previousSiblingKey))
                }
            }
            return FChildEventRegistration(repo: repo, handle: handle, callbacks: callbacks,
                                           cancelCallback: { continuation.finish(throwing: $0) })
        }
    }

    /**
     * The current data at this location or query: from the cache if there's
     * some, else from the server. (`getData()` asks the server first.)
     */
    public func firstValue() async throws -> DataSnapshot {
        for try await snapshot in values() {
            return snapshot
        }
        throw CancellationError()
    }
}
