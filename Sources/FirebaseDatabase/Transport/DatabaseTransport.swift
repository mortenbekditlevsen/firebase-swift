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
import NIOCore

/// Opens the WebSocket connections a `Database` talks to its server over.
///
/// The Database uses `NIODatabaseTransport` by default (`URLSessionDatabaseTransport`
/// on watchOS). Set `Database.transport` to use another one, e.g. your own.
///
/// A transport must:
/// - throw from `withConnection` if connecting, TLS or the WebSocket upgrade fails;
/// - finish the connection's `inbound` sequence when the connection closes, or
///   throw from it on an error;
/// - close the connection when `body` returns or throws;
/// - close the connection promptly when the task is cancelled.
public protocol DatabaseTransport: Sendable {
    associatedtype Connection: DatabaseTransportConnection

    /// Connects to `request.url`, runs `body` with the open connection, and
    /// closes the connection when `body` returns or throws.
    func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)?,
        _ body: (Connection) async throws -> sending Result
    ) async throws -> sending Result
}

/// An open WebSocket connection.
public protocol DatabaseTransportConnection: Sendable {
    associatedtype Inbound: AsyncSequence<DatabaseFrame, any Error>

    /// The text messages the server sends, in order. Finishes when the
    /// connection closes, and throws if it fails.
    var inbound: Inbound { get }

    /// Sends a text message.
    func send(_ frame: DatabaseFrame) async throws
}

/// Where to connect, and the headers to send with the WebSocket upgrade request.
public struct DatabaseTransportRequest: Sendable {
    /// A `ws` or `wss` URL.
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

/// The UTF-8 bytes of one WebSocket text message.
public struct DatabaseFrame: Sendable {
    enum Storage: Sendable {
        case buffer(ByteBuffer)
        case data(Data)
    }

    let storage: Storage

    public init(_ buffer: ByteBuffer) {
        storage = .buffer(buffer)
    }

    public init(_ data: Data) {
        storage = .data(data)
    }

    public init(_ string: String) {
        storage = .buffer(ByteBuffer(string: string))
    }

    public var count: Int {
        switch storage {
        case .buffer(let buffer): buffer.readableBytes
        case .data(let data): data.count
        }
    }

    public func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        switch storage {
        case .buffer(let buffer): try buffer.withUnsafeReadableBytes(body)
        case .data(let data): try data.withUnsafeBytes(body)
        }
    }

    /// The message as text (invalid UTF-8 is repaired).
    public var string: String {
        switch storage {
        case .buffer(let buffer): String(buffer: buffer)
        case .data(let data): String(decoding: data, as: UTF8.self)
        }
    }

    /// The message as a byte buffer, without copying if it is one.
    var byteBuffer: ByteBuffer {
        switch storage {
        case .buffer(let buffer): buffer
        case .data(let data): ByteBuffer(bytes: data)
        }
    }
}

/// The largest message the transports accept (the server splits large
/// payloads into 16 KiB messages itself).
let maxDatabaseMessageSize = 16 << 20

public enum DatabaseTransportError: Error, Sendable {
    /// The URL isn't a `ws` or `wss` URL with a host.
    case invalidURL(URL)
    /// The server didn't upgrade the connection to a WebSocket.
    case upgradeRejected
}

extension Database {
    /// The transport used by default: `NIODatabaseTransport`, or
    /// `URLSessionDatabaseTransport` on watchOS.
    public static let defaultTransport: any DatabaseTransport = {
        #if os(watchOS)
            URLSessionDatabaseTransport()
        #else
            NIODatabaseTransport()
        #endif
    }()
}
