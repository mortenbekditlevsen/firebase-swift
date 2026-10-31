// Copyright 2017 Google LLC
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
import NIOHTTP1

@DatabaseActor
protocol FWebSocketDelegate: AnyObject {
    func onMessage(_ fwebSocket: AnyObject, withMessage message: [String: Any])
    func onDisconnect(_ fwebSocket: AnyObject, wasEverConnected: Bool)
}

private let kAppCheckTokenHeader = "X-Firebase-AppCheck"
private let kUserAgentHeader = "User-Agent"
private let kGoogleAppIDHeader = "X-Firebase-GMPID"

extension String {
    func split(by length: Int) -> [Substring] {
        var startIndex = self.startIndex
        var results = [Substring]()

        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }

        return results
    }
}

@DatabaseActor
class FWebSocketConnection {
    var connectionId: Int
    var totalFrames: Int
    var buffering: Bool {
        frame != nil
    }
    var frame: String?
    var everConnected: Bool
    var isClosed: Bool
    var keepAlive: Task<Void, Never>?
    var keepAliveFireDate: Date?
    var client: WebSocketClient?

    public weak var delegate: FWebSocketDelegate?
    func open() {
        FFLog("I-RDB083002", "(wsc:\(self.connectionId)) FWebSocketConnection open)")
        assert(delegate != nil)
        everConnected = false
        guard client != nil else {
            Task { @DatabaseActor in self.closeIfNeverConnected() }
            return
        }
        do {
            try client?.open()
        } catch {
            // print("ERROR connecting: \(error)")
        }
        Task { @DatabaseActor in
            try? await Task.sleep(for: .seconds(kWebsocketConnectTimeout))
            closeIfNeverConnected()
        }
    }

    private func closeIfNeverConnected() {
        if !everConnected {
            FFLog("I-RDB083012", "(wsc:\(connectionId)) Websocket timed out on connect")
            client?.close()
        }
    }

    func close() {
        FFLog("I-RDB083003", "(wsc:\(connectionId)) FWebSocketConnection is being closed.")
        isClosed = true
        client?.close()
    }

    func start() {
//        print("START")
    }

    private func resetKeepAlive() {
        guard keepAlive != nil, let fireDate = keepAliveFireDate else {
            return
        }

        let newTime = Date(timeIntervalSinceNow: kWebsocketKeepaliveInterval)
        // Only bother postponing once the fire date is at least 5 seconds stale.
        if newTime.timeIntervalSince(fireDate) > 5 {
            FFLog("I-RDB083014", "(wsc:\(self.connectionId)) resetting keepalive, to \(newTime) ; old: \(fireDate)")
            keepAliveFireDate = newTime
        }
    }

    /// Sends a "nop" frame whenever `keepAliveFireDate` passes. A `Timer` can't
    /// be used here: tasks on `DatabaseActor` don't run on a thread with a run loop.
    private func startKeepAlive() {
        keepAliveFireDate = Date(timeIntervalSinceNow: kWebsocketKeepaliveInterval)
        keepAlive = Task { @DatabaseActor [weak self] in
            while !Task.isCancelled {
                guard let fireDate = self?.keepAliveFireDate else { return }
                let delay = fireDate.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                guard let self else { return }
                if !self.isClosed {
                    FFLog("I-RDB083004", "(wsc:\(self.connectionId)) nop")
                    // Note: the backend is expecting a string "0" here, not any special
                    // ping/pong from build in websocket APIs.
                    self.client?.send(string: "0")
                    self.keepAliveFireDate = Date(timeIntervalSinceNow: kWebsocketKeepaliveInterval)
                } else {
                    FFLog("I-RDB083005",
                          "(wsc:\(self.connectionId) No more websocket; invalidating nop timer.")
                    self.keepAlive = nil
                    return
                }
            }
        }
    }

    func send(_ dictionary: [String: Any]) {
        resetKeepAlive()

        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return
        }
        guard let string = String(data: data, encoding: .utf8) else {
            return
        }

        let chunks = string.split(by: kWebsocketMaxFrameSize)
        if chunks.count > 1 {
            client?.send(string: "\(chunks.count)")
        }
        for chunk in chunks {
            client?.send(string: chunk)
        }
    }

    init(with connectionURL: String,
         googleAppID: String,
         appCheckToken: String?,
         userAgent: String) {
        self.everConnected = false
        self.isClosed = false
        self.connectionId =  FUtilities.LUIDGenerator()
        self.totalFrames = 0
        self.frame = nil

        FFLog("I-RDB083001", "(wsc: \(connectionId)) Connecting to:\(connectionURL) as \(userAgent))")

        guard let url = URL(string: connectionURL) else {
            // No client; open() reports a failed connection attempt instead.
            // Don't log the URL, since it can include the session ID.
            FFWarn("I-RDB083022", "(wsc:\(connectionId)) Couldn't parse the connection URL")
            return
        }

        let headers = createHeaders(with: connectionURL,
                                    userAgent: userAgent,
                                    googleAppID: googleAppID,
                                    appCheckToken: appCheckToken)

        self.client = WebSocketClient(url: url,
                                      headers: headers,
                                      onOpen: { [weak self] in

            Task { @DatabaseActor in
                guard let self = self else { return }
                FFLog("I-RDB083008", "(wsc:\(self.connectionId)) webSocketDidOpen")
                self.everConnected = true

                self.startKeepAlive()
                FFLog("I-RDB083009", "(wsc:\(self.connectionId) nop timer kicked off")
            }
        }, onMessage: { [weak self] message in
            guard let self else { return }
            // XXX TODO?
            Task { @DatabaseActor in
                self.handleIncomingFrame(message)
            }
        }, onClose: { [weak self] in
            guard let self  else { return }
            // XXX TODO?
            Task { @DatabaseActor in
                self.onClose()
            }
        })
    }

    private func shutdown() {
        isClosed = true
        self.delegate?.onDisconnect(self, wasEverConnected: self.everConnected)
    }

    private func onClose() {
        if !isClosed {
            FFLog("I-RDB083013", "Websocket is closing itself")
            self.shutdown()
        }
        client = nil
        keepAlive?.cancel()
        keepAlive = nil
    }

    private func appendFrame(_ message: String) {
        let combined = (frame ?? "") + message
        frame = combined
        totalFrames -= 1

        if totalFrames == 0 {
            // Call delegate and pass an immutable version of the frame
            let data = Data(combined.utf8)
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
//                print("Websocket: Received \(json)")
                self.delegate?.onMessage(self, withMessage: json)
            }

            frame = nil
            FFLog("I-RDB083007",
                  "(wsc:\(connectionId)) handleIncomingFrame sending complete frame: \(totalFrames)")
        }
    }

    private func handleNewFrameCount(_ count: Int) {
        totalFrames = count
        frame = ""
        FFLog("I-RDB083006", "(wsc:\(connectionId)) handleNewFrameCount: \(count)")
    }

    private func extractFrameCount(_ message: String) -> String? {
        if message.count <= 4 {
            let frameCount = Int(message) ?? 0
            if frameCount > 0 {
                handleNewFrameCount(frameCount)
                return nil
            }
        }
        handleNewFrameCount(1)
        return message
    }

    private func handleIncomingFrame(_ message: String) {
        resetKeepAlive()
        if buffering {
            appendFrame(message)
        } else {
            if let remaining = extractFrameCount(message) {
                appendFrame(remaining)
            }
        }
    }
}

private  func createHeaders(with url: String,
                            userAgent: String,
                            googleAppID: String,
                            appCheckToken: String?) -> HTTPHeaders {

    var headers = HTTPHeaders()
    if let appCheckToken = appCheckToken {
        headers.add(name: kAppCheckTokenHeader, value: appCheckToken)
    }
    headers.add(name: kUserAgentHeader, value: userAgent)
    headers.add(name: kGoogleAppIDHeader, value: googleAppID)
    return headers
}

enum FDisconnectReason {
    case serverReset
    case other

    var description: String {
        switch self {
        case .other:
            return "other"
        case .serverReset:
            return "server_reset"
        }
    }
}

@DatabaseActor
protocol FConnectionDelegate: AnyObject {
    func onReady(_ connection: FConnection,
                 atTime timestamp: Double,
                 sessionID: String)

    func onDataMessage(_ connection: FConnection, withMessage message: [String: Any])
    func onDisconnect(_ connection: FConnection, withReason reason: FDisconnectReason)
    func onKill(_ connection: FConnection, withReason: String)
}
