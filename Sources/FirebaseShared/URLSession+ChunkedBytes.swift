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

public extension URLSession {
  /// A portable replacement for `bytes(for:)`, which swift-corelibs-foundation
  /// does not provide. The response body arrives as a stream of `Data` chunks.
  ///
  /// The request runs on a dedicated session that uses this session's
  /// configuration. The call returns once the first chunk arrives or the
  /// request completes, whichever happens first.
  func chunkedBytes(for request: URLRequest) async throws
    -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    let (chunks, chunkContinuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let delegate = ChunkedBytesDelegate(chunks: chunkContinuation)
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    let task = session.dataTask(with: request)
    chunkContinuation.onTermination = { _ in task.cancel() }

    let response = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        delegate.setResponseContinuation(continuation)
        task.resume()
        session.finishTasksAndInvalidate()
      }
    } onCancel: {
      task.cancel()
    }
    return (chunks, response)
  }
}

public extension AsyncSequence where Element == Data, Self: Sendable {
  /// The non-empty lines of a chunked byte stream, split on `\n` with any
  /// trailing `\r` removed. Matches `URLSession.AsyncBytes.lines`, which also
  /// skips empty lines.
  var asyncLines: AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var buffer = Data()
        func emit(_ line: Data) {
          var line = line
          if line.last == UInt8(ascii: "\r") { line.removeLast() }
          if !line.isEmpty { continuation.yield(String(decoding: line, as: UTF8.self)) }
        }
        do {
          for try await chunk in self {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
              emit(buffer[buffer.startIndex ..< newline])
              buffer.removeSubrange(buffer.startIndex ... newline)
            }
          }
          emit(buffer)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

private final class ChunkedBytesDelegate: NSObject, URLSessionDataDelegate, Sendable {
  private let chunks: AsyncThrowingStream<Data, Error>.Continuation
  private let responseContinuation = Mutex<CheckedContinuation<URLResponse, Error>?>(nil)

  init(chunks: AsyncThrowingStream<Data, Error>.Continuation) {
    self.chunks = chunks
  }

  func setResponseContinuation(_ continuation: CheckedContinuation<URLResponse, Error>) {
    responseContinuation.withLock { $0 = continuation }
  }

  private func resumeResponse(with result: Result<URLResponse, Error>) {
    responseContinuation.withLock { continuation in
      continuation?.resume(with: result)
      continuation = nil
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    if let response = dataTask.response {
      resumeResponse(with: .success(response))
    }
    chunks.yield(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      resumeResponse(with: .failure(error))
      chunks.finish(throwing: error)
    } else {
      resumeResponse(with: task.response.map { .success($0) }
        ?? .failure(URLError(.badServerResponse)))
      chunks.finish()
    }
  }
}
