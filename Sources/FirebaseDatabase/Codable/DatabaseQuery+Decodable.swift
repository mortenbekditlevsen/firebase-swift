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

import FirebaseShared
import Foundation
import Synchronization

/// A change to one of a location's children, with the child decoded.
public struct DecodedChildEvent<Value: Sendable>: Sendable {
    public let kind: ChildEvent.Kind
    /// The child's key.
    public let key: String
    /// The child (for a removal, its last data).
    public let value: Value
    /// The key of the child before it in the query's order, or nil if it's
    /// the first. (Nil for removals.)
    public let previousSiblingKey: String?
}

extension DatabaseQuery {
    /**
     * The data at this location or query, decoded as `T`, now and after each
     * change (see `values()`).
     *
     * The data is decoded on the cooperative thread pool, neither on the
     * database's actor nor on the caller's, in order. The sequence throws if
     * the data doesn't decode.
     */
    public func values<T: Decodable & Sendable>(
        as type: T.Type,
        decoder: Database.Decoder = Database.Decoder(),
        bufferingPolicy: AsyncThrowingStream<DataSnapshot, any Error>.Continuation.BufferingPolicy = .unbounded
    ) -> some AsyncSequence<T, any Error> & Sendable {
        DecodedDatabaseEvents(events: values(bufferingPolicy: bufferingPolicy)) { snapshot in
            try snapshot.data(as: T.self, decoder: decoder)
        }
    }

    /**
     * The changes to this location's (or query's) children, with each child
     * decoded as `T` (see `childEvents(_:)` and `values(as:)`).
     */
    public func childEvents<T: Decodable & Sendable>(
        as type: T.Type,
        _ kinds: Set<ChildEvent.Kind> = Set(ChildEvent.Kind.allCases),
        decoder: Database.Decoder = Database.Decoder(),
        bufferingPolicy: AsyncThrowingStream<ChildEvent, any Error>.Continuation.BufferingPolicy = .unbounded
    ) -> some AsyncSequence<DecodedChildEvent<T>, any Error> & Sendable {
        DecodedDatabaseEvents(events: childEvents(kinds, bufferingPolicy: bufferingPolicy)) { event in
            DecodedChildEvent(kind: event.kind, key: event.snapshot.key ?? "",
                              value: try event.snapshot.data(as: T.self, decoder: decoder),
                              previousSiblingKey: event.previousSiblingKey)
        }
    }

    /// `getData()`, decoded as `T`.
    @concurrent
    public func get<T: Decodable>(as type: T.Type,
                                  decoder: Database.Decoder = Database.Decoder()) async throws -> sending T {
        try await getData().data(as: T.self, decoder: decoder)
    }

    /// `firstValue()`, decoded as `T` (off the database's actor and the caller's).
    @concurrent
    public func firstValue<T: Decodable>(as type: T.Type,
                                         decoder: Database.Decoder = Database.Decoder()) async throws -> sending T {
        try await firstValue().data(as: T.self, decoder: decoder)
    }
}

extension DatabaseReference {
    /**
     * Runs a transaction on the data here, decoded as `T`: `update` gets the
     * current value (nil if there's none) and changes it, and the new value
     * is encoded and written if the data didn't change meanwhile (else
     * `update` runs again with the new data).
     *
     * If `update` throws, or the data doesn't decode, the transaction is
     * aborted and the error rethrown.
     *
     * - Returns: The value committed.
     */
    @discardableResult
    public func runTransaction<T: Codable & Sendable>(
        as type: T.Type,
        applyLocally: Bool = true,
        decoder: Database.Decoder = Database.Decoder(),
        encoder: Database.Encoder = Database.Encoder(),
        _ update: @escaping @Sendable (inout T?) throws -> Void
    ) async throws -> T? {
        let failure = Mutex<(any Error)?>(nil)
        let decoding = FNodeDecoder(decoder)
        let encoding = FNodeEncoder(encoder)
        let (committed, snapshot) = try await runTransaction(applyLocally: applyLocally) { data in
            do {
                var value = data.nodeValue.isEmpty ? nil : try decoding.decode(T.self, from: data.nodeValue)
                try update(&value)
                data = MutableData(node: try value.map(encoding.encode) ?? .empty, key: data.key)
                failure.withLock { $0 = nil }
                return .success(withValue: data)
            } catch {
                failure.withLock { $0 = error }
                return .abort()
            }
        }
        if let error = failure.withLock({ $0 }) {
            throw error
        }
        guard committed else { return nil }
        return snapshot.exists() ? try snapshot.data(as: T.self, decoder: decoder) : nil
    }
}

/// Elements of a database event sequence, decoded in order on the
/// cooperative thread pool.
struct DecodedDatabaseEvents<Source: Sendable, Element: Sendable>: AsyncSequence, Sendable {
    typealias Failure = any Error

    let events: DatabaseEvents<Source>
    let decode: @Sendable (Source) throws -> Element

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(events: events.makeAsyncIterator(), decode: decode)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var events: DatabaseEvents<Source>.AsyncIterator
        let decode: @Sendable (Source) throws -> Element

        mutating func next() async throws -> Element? {
            try await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws -> Element? {
            guard let source = try await events.next(isolation: actor) else { return nil }
            return try await Self.decoded(source, decode)
        }

        @concurrent
        private static func decoded(_ source: Source,
                                    _ decode: @Sendable (Source) throws -> Element) async throws -> Element {
            try decode(source)
        }
    }
}
