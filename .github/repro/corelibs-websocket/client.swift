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

// Connects to server.py's route (the first argument) and prints what
// URLSessionWebSocketTask reports. Run: swift client.swift /fragments
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let start = Date()
func elapsed() -> String { String(format: "%.1f s", Date().timeIntervalSince(start)) }

final class Delegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("didOpen, status \((webSocketTask.response as? HTTPURLResponse)?.statusCode ?? -1)")
    }
    // Optional on Apple platforms, but swift-corelibs-foundation's default
    // implementations aren't public.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("didClose after \(elapsed()), code \(closeCode.rawValue)")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        print("didComplete after \(elapsed()), error: \(error.map { "\($0)" } ?? "none")")
    }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/fragments"
let session = URLSession(configuration: .default, delegate: Delegate(), delegateQueue: nil)
// /refused: a port where nothing listens.
let port = path == "/refused" ? 8766 : 8765
let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)\(path)")!)
task.resume()
Task {
    do {
        while true {
            switch try await task.receive() {
            case .string(let text) where text.utf8.count > 100: print("message: \(text.utf8.count) bytes of text")
            case .string(let text): print("message: \(text.debugDescription)")
            case .data(let data): print("message: \(data.count) bytes")
            @unknown default: print("message: unknown")
            }
        }
    } catch {
        print("receive failed after \(elapsed()): \(error)")
    }
}
// Long enough for a refused connection to time out (60 seconds by default).
Thread.sleep(forTimeInterval: path == "/refused" ? 75 : 3)
task.cancel(with: .normalClosure, reason: nil)
