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

#if os(Windows)
    import CWinHTTP
    import Dispatch
    import Foundation
    import Synchronization

    /// WebSocket connections over WinHTTP, Windows' own HTTP client, with its
    /// TLS and the system's proxy settings. The default transport on Windows.
    ///
    /// (`URLSessionDatabaseTransport` works there too, but swift-corelibs-foundation
    /// splits messages over 16 KB and crashes on fragmented ones.)
    public struct WinHTTPDatabaseTransport: DatabaseTransport {
        private let timeout: Duration

        /// - Parameter timeout: How long resolving the host, connecting, and
        ///   each step of the WebSocket upgrade may take.
        public init(timeout: Duration = .seconds(30)) {
            self.timeout = timeout
        }

        public func withConnection<Result>(
            to request: DatabaseTransportRequest,
            isolation: isolated (any Actor)? = #isolation,
            _ body: (Connection) async throws -> sending Result
        ) async throws -> sending Result {
            let target = try WinHTTPTarget(request)
            let socket = try WinHTTPSocket()
            defer { socket.close() }
            let milliseconds = UInt32(clamping: timeout.components.seconds * 1000
                + timeout.components.attoseconds / 1_000_000_000_000_000)
            try await withTaskCancellationHandler {
                try await socket.open(target, timeoutMilliseconds: milliseconds)
            } onCancel: {
                socket.abort()
            }
            return try await body(Connection(socket: socket, messages: socket.receive()))
        }

        public struct Connection: DatabaseTransportConnection {
            fileprivate let socket: WinHTTPSocket
            fileprivate let messages: AsyncThrowingStream<DatabaseFrame, any Error>

            public var inbound: AsyncThrowingStream<DatabaseFrame, any Error> {
                messages
            }

            public func send(_ frame: DatabaseFrame) async throws {
                try await socket.send(frame)
            }
        }
    }

    extension WinHTTPDatabaseTransport.Connection: DatabaseTransportImmediateSending {
        func sendImmediately(_ frame: DatabaseFrame) {
            socket.sendImmediately(frame)
        }
    }

    /// A WinHTTP call that failed.
    public struct WinHTTPError: Error, Sendable, CustomStringConvertible {
        /// What failed: "open", "receive", "send".
        public let operation: String
        /// The Windows error code (e.g. 12029, ERROR_WINHTTP_CANNOT_CONNECT).
        public let code: UInt32

        public var description: String {
            "WinHTTP \(operation) failed with error \(code)"
        }
    }

    /// A message from the server that's larger than the transports accept.
    struct WinHTTPMessageTooLarge: Error {}

    /// Where a request goes, as WinHTTP takes it.
    private struct WinHTTPTarget: Sendable {
        let host: String
        let port: UInt16
        let secure: Bool
        let pathAndQuery: String
        let userAgent: String
        /// "Name: value\r\n" for each header but User-Agent (the session's).
        let headers: String

        init(_ request: DatabaseTransportRequest) throws {
            let url = request.url
            guard let scheme = url.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
                  let host = url.host, !host.isEmpty,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                throw DatabaseTransportError.invalidURL(url)
            }
            secure = scheme == "wss"
            guard let port = UInt16(exactly: url.port ?? (secure ? 443 : 80)) else {
                throw DatabaseTransportError.invalidURL(url)
            }
            self.host = host
            self.port = port
            var pathAndQuery = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            if let query = components.percentEncodedQuery {
                pathAndQuery += "?\(query)"
            }
            self.pathAndQuery = pathAndQuery
            var userAgent = "firebase-swift"
            var headers = ""
            for (name, value) in request.headers {
                if name.caseInsensitiveCompare("User-Agent") == .orderedSame {
                    userAgent = value
                } else {
                    headers += "\(name): \(value)\r\n"
                }
            }
            self.userAgent = userAgent
            self.headers = headers
        }
    }

    /// A `CWinHTTPSocket`, whose blocking calls run off the cooperative pool:
    /// the upgrade and the sends on a serial queue, in order, and receiving
    /// on a thread of its own.
    private final class WinHTTPSocket: @unchecked Sendable {
        // @unchecked: `socket` is thread-safe (CWinHTTP's calls may run
        // concurrently); the rest is immutable or behind `failure`'s lock.
        private let socket: OpaquePointer
        private let queue = DispatchQueue(label: "WinHTTPDatabaseTransport")
        /// Why the connection ended, if a send failed.
        private let failure = Mutex<(any Error)?>(nil)

        init() throws {
            guard let socket = CWinHTTPSocketCreate() else {
                throw WinHTTPError(operation: "open", code: 8) // ERROR_NOT_ENOUGH_MEMORY
            }
            self.socket = socket
        }

        deinit {
            CWinHTTPSocketDestroy(socket)
        }

        func open(_ target: WinHTTPTarget, timeoutMilliseconds: UInt32) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async {
                    continuation.resume(with: Result {
                        try self.openNow(target, timeoutMilliseconds: timeoutMilliseconds)
                    })
                }
            }
        }

        private func openNow(_ target: WinHTTPTarget, timeoutMilliseconds: UInt32) throws {
            var status: UInt32 = 0
            let error = target.userAgent.withCString(encodedAs: UTF16.self) { userAgent in
                target.host.withCString(encodedAs: UTF16.self) { host in
                    target.pathAndQuery.withCString(encodedAs: UTF16.self) { pathAndQuery in
                        target.headers.withCString(encodedAs: UTF16.self) { headers in
                            CWinHTTPSocketOpen(socket, userAgent, host, target.port, target.secure ? 1 : 0,
                                               pathAndQuery, headers, timeoutMilliseconds, &status)
                        }
                    }
                }
            }
            try check(error, "open")
            guard status == 101 else {
                throw DatabaseTransportError.upgradeRejected
            }
        }

        /// Starts receiving: the messages, until the server closes the
        /// connection or it fails. Call once.
        func receive() -> AsyncThrowingStream<DatabaseFrame, any Error> {
            let (messages, continuation) = AsyncThrowingStream<DatabaseFrame, any Error>.makeStream()
            // Ends the connection when the messages are no longer read (the
            // reader's task was cancelled, say), which ends receiving.
            continuation.onTermination = { [self] _ in
                abort()
            }
            let thread = Thread { [self] in
                receive(into: continuation)
            }
            thread.name = "WinHTTPDatabaseTransport receive"
            thread.start()
            return messages
        }

        private func receive(into continuation: AsyncThrowingStream<DatabaseFrame, any Error>.Continuation) {
            var buffer = [UInt8](repeating: 0, count: 64 << 10)
            var message = Data()
            while true {
                var bytesRead: UInt32 = 0
                var received: Int32 = 0
                let error = buffer.withUnsafeMutableBytes { buffer in
                    CWinHTTPSocketReceive(socket, buffer.baseAddress, UInt32(buffer.count), &bytesRead, &received)
                }
                if error == CWinHTTPErrorCancelled {
                    // Ended here: by close(), the reader, or a failed send.
                    continuation.finish(throwing: failure.withLock { $0 })
                    return
                }
                guard error == 0 else {
                    continuation.finish(throwing: WinHTTPError(operation: "receive", code: error))
                    abort()
                    return
                }
                if received == Int32(CWinHTTPReceivedClose) {
                    continuation.finish()
                    // Answers the close, as the protocol asks.
                    close()
                    return
                }
                message.append(contentsOf: buffer[..<Int(bytesRead)])
                guard message.count <= maxDatabaseMessageSize else {
                    continuation.finish(throwing: WinHTTPMessageTooLarge())
                    abort()
                    return
                }
                if received == Int32(CWinHTTPReceivedMessage) {
                    if case .terminated = continuation.yield(DatabaseFrame(message)) {
                        return
                    }
                    message = Data()
                }
            }
        }

        func send(_ frame: DatabaseFrame) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async {
                    continuation.resume(with: Result { try self.sendNow(frame) })
                }
            }
        }

        /// Sends in order with the other sends; a failure ends the connection.
        func sendImmediately(_ frame: DatabaseFrame) {
            queue.async {
                do {
                    try self.sendNow(frame)
                } catch {
                    self.failure.withLock { $0 = $0 ?? error }
                    self.abort()
                }
            }
        }

        private func sendNow(_ frame: DatabaseFrame) throws {
            let error = frame.withUnsafeBytes { bytes in
                CWinHTTPSocketSend(socket, bytes.baseAddress, UInt32(bytes.count))
            }
            try check(error, "send")
        }

        /// Closes the connection, politely: after the sends already queued,
        /// with a close frame. Doesn't wait. (The queue keeps close frames
        /// apart: CWinHTTP takes one at a time.)
        func close() {
            queue.async {
                _ = CWinHTTPSocketShutdown(self.socket)
                self.abort()
            }
            // In case a send hangs on a connection that died.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self.abort()
            }
        }

        /// Ends the connection, and any call in progress, now.
        func abort() {
            CWinHTTPSocketAbort(socket)
        }

        private func check(_ error: UInt32, _ operation: String) throws {
            if error == CWinHTTPErrorCancelled {
                throw CancellationError()
            }
            if error != 0 {
                throw WinHTTPError(operation: operation, code: error)
            }
        }
    }
#endif
