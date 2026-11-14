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
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Synchronization

/// WebSocket connections over `URLSessionWebSocketTask`.
///
/// Upstream tried URLSession and went back to SocketRocket because broken
/// connections went unnoticed after backgrounding; it handled the socket's
/// close but not the task's completion with an error. This transport
/// handles both, so every failure ends the connection.
///
/// Off Apple platforms, swift-corelibs-foundation's WebSockets need a libcurl
/// built with them. The Windows toolchain's curl is. In the swift:6.3 (Ubuntu
/// 24.04) image connections never open, so use `NIODatabaseTransport` on Linux.
public struct URLSessionDatabaseTransport: DatabaseTransport {
    private let configuration: @Sendable () -> URLSessionConfiguration

    /// - Parameter configuration: Makes the configuration of each
    ///   connection's session.
    public init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .default }) {
        self.configuration = configuration
    }

    public func withConnection<Result>(
        to request: DatabaseTransportRequest,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (Connection) async throws -> sending Result
    ) async throws -> sending Result {
        guard let scheme = request.url.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
              request.url.host != nil
        else {
            throw DatabaseTransportError.invalidURL(request.url)
        }
        var urlRequest = URLRequest(url: request.url)
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let delegate = Delegate()
        let session = URLSession(configuration: configuration(), delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: urlRequest)
        task.maximumMessageSize = maxDatabaseMessageSize
        // The session keeps its delegate until it's invalidated.
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.onOpen(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
        return try await body(Connection(task: task, delegate: delegate))
    }

    public struct Connection: DatabaseTransportConnection {
        let task: URLSessionWebSocketTask
        fileprivate let delegate: Delegate

        public var inbound: Messages {
            Messages(task: task, delegate: delegate)
        }

        public func send(_ frame: DatabaseFrame) async throws {
            try await task.send(.string(frame.string))
        }
    }

    public struct Messages: AsyncSequence {
        let task: URLSessionWebSocketTask
        fileprivate let delegate: Delegate

        public func makeAsyncIterator() -> Iterator {
            Iterator(task: task, delegate: delegate)
        }

        public struct Iterator: AsyncIteratorProtocol {
            let task: URLSessionWebSocketTask
            fileprivate let delegate: Delegate

            public mutating func next() async throws -> DatabaseFrame? {
                try await next(isolation: nil)
            }

            public mutating func next(isolation actor: isolated (any Actor)?) async throws -> DatabaseFrame? {
                let task = task
                do {
                    let message = try await withTaskCancellationHandler {
                        try await task.receive()
                    } onCancel: {
                        task.cancel(with: .goingAway, reason: nil)
                    }
                    switch message {
                    case .string(let string): return DatabaseFrame(string)
                    case .data(let data): return DatabaseFrame(data)
                    @unknown default: return nil
                    }
                } catch {
                    // A close (or cancellation) finishes the messages;
                    // anything else is the error the task ended with.
                    // (The close code is set when the close frame arrives,
                    // which can be before the delegate hears of it.)
                    if Task.isCancelled || task.closeCode != .invalid || delegate.closedNormally {
                        return nil
                    }
                    throw delegate.failure ?? error
                }
            }
        }
    }
}

private final class Delegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    private struct State {
        var open: CheckedContinuation<Void, any Error>?
        var closedNormally = false
        var failure: (any Error)?
    }

    private let state = Mutex(State())

    var closedNormally: Bool { state.withLock { $0.closedNormally } }
    var failure: (any Error)? { state.withLock { $0.failure } }

    func onOpen(_ continuation: CheckedContinuation<Void, any Error>) {
        state.withLock { $0.open = continuation }
    }

    private func resumeOpen(_ result: Swift.Result<Void, any Error>) {
        state.withLock { state in
            let continuation = state.open
            state.open = nil
            return continuation
        }?.resume(with: result)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        resumeOpen(.success(()))
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        state.withLock { $0.closedNormally = true }
        resumeOpen(.failure(URLError(.networkConnectionLost)))
    }

    // Upstream's URLSession attempt didn't implement this, so failures after
    // backgrounding went unnoticed.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let error = error ?? URLError(.networkConnectionLost)
        state.withLock { $0.failure = $0.failure ?? error }
        resumeOpen(.failure(error))
    }
}
