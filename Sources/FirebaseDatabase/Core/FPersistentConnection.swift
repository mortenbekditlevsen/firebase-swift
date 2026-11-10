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

#if os(iOS) || os(tvOS)
import UIKit
#endif

class FOutstandingQuery {
    fileprivate init(query: FQuerySpec, tagId: Int?, syncTreeHash: FSyncTreeHash, onComplete: ((String) -> Void)?) {
        self.query = query
        self.tagId = tagId
        self.syncTreeHash = syncTreeHash
        self.onComplete = onComplete
    }

    let query: FQuerySpec
    let tagId: Int?
    let syncTreeHash: FSyncTreeHash
    let onComplete: ((String) -> Void)?
}

fileprivate class FOutstandingPut {
    fileprivate init(
        action: String,
        request: [String : Any],
        onComplete: @escaping (String, String?) -> Void,
        sent: Bool
    ) {
        self.action = action
        self.request = request
        self.onComplete = onComplete
        self.sent = sent
    }

    let action: String
    let request: [String : Any]
    let onComplete: ((String, String?) -> Void)?
    var sent: Bool
}

struct FOutstandingGetResultData: @unchecked Sendable {
    let status: String
    let data: Any?
    let errorReason: String?
}

fileprivate class FOutstandingGet {
    fileprivate init(request: [String : Any], onComplete: CheckedContinuation<FOutstandingGetResultData, Never>, sent: Bool) {
        self.request = request
        self.onComplete = onComplete
        self.sent = sent
    }

    let request: [String : Any]
    let onComplete: CheckedContinuation<FOutstandingGetResultData, Never>
    var sent: Bool
}

enum ConnectionState {
    case disconnected
    case gettingToken
    case connecting
    case authenticating
    case connected
}

/// The repo's side of the connection. Called on the actor, in the order the
/// server's messages arrive.
@DatabaseActor
protocol FPersistentConnectionDelegate: AnyObject {
    func onDataUpdate(_ fpconnection: FPersistentConnection,
                      forPath pathString: String,
                      message: Any,
                      isMerge: Bool,
                      tagId: Int?)

    func onRangeMerge(_ ranges: [FRangeMerge],
                      forPath pathString: String,
                      tagId: Int?)

    func onConnect(_ fpconnection: FPersistentConnection)

    func onDisconnect(_ fpconnection: FPersistentConnection)

    func onServerInfoUpdate(_ fpconnection: FPersistentConnection, updates: [String: Any])
}

typealias OnDisconnectTuple = (pathString: String,
                               action: String,
                               data: Any,
                               onComplete: (String, String?) -> Void)

typealias PutToAckTuple = (onComplete: (String, String?) -> Void,
                           status: String,
                           errorReason: String?)

/// What a request's response is for. (Upstream keeps a callback per request.)
private enum PendingResponse {
    case put(index: Int, FOutstandingPut)
    case get(index: Int, FOutstandingGet)
    case listen(FOutstandingQuery)
    case onDisconnect(OnDisconnectTuple)
    case auth(restoreState: Bool)
    case appCheck
    case stats
    /// A liveness check after a network change.
    case probe
}

/// Why a connection ended.
enum SessionEnd: Error, Equatable {
    /// Closed by either side, failed, or interrupted.
    case closed
    /// The server moved the database to another host: reconnect at once.
    case serverReset
    /// The server shut the connection down for good.
    case killed(String)
    /// No handshake within `kWebsocketConnectTimeout`.
    case handshakeTimeout
    /// No answer to a liveness check.
    case probeTimeout
}

/// One connection to the server, from connecting until it closes.
@DatabaseActor
private final class Link {
    let outbox: AsyncStream<DatabaseFrame>.Continuation
    let probes: AsyncStream<Int>.Continuation
    /// Whether the server's handshake has arrived.
    var ready = false
    /// When a message was last sent or received.
    var lastActivity: Duration
    var assembler = FrameAssembler()
    var end: SessionEnd?

    init(outbox: AsyncStream<DatabaseFrame>.Continuation, probes: AsyncStream<Int>.Continuation, now: Duration) {
        self.outbox = outbox
        self.probes = probes
        lastActivity = now
    }
}

/// How long a liveness check may take.
let kPersistentConnectionProbeTimeout: Double = 10

/// The connection to the database's server: connects, keeps the listens,
/// writes and reads the repo asked for, and reconnects when it drops.
///
/// One task (started by `open()`) runs it: it waits until nothing interrupts
/// the connection, waits out the backoff, gets the auth and App Check tokens,
/// and connects. While connected, child tasks send the outgoing messages,
/// the keep-alives and liveness checks, and the loop handles the server's
/// messages on the actor, in order.
@DatabaseActor
final class FPersistentConnection {
    private(set) var connectionState: ConnectionState = .disconnected
    private var firstConnection = true
    private var lastConnectionEstablishedTime: Duration?

    private var listens: [FQuerySpec: FOutstandingQuery] = [:]
    private var outstandingPuts: [Int: FOutstandingPut] = [:]
    private var outstandingGets: [Int: FOutstandingGet] = [:]
    private var onDisconnectQueue: [OnDisconnectTuple] = []
    private var pending: [Int: PendingResponse] = [:]
    private var putCounter = 0
    private var getCounter = 0
    private var requestNumber = 0
    private var unackedListensCount = 0
    private var putsToAck: [PutToAckTuple] = []

    /// The host the server moves the connection to is kept here; upstream's
    /// FRepoInfo is a class, and the port's old FConnection changed a copy,
    /// so a reset only took effect at the next launch.
    private(set) var repoInfo: FRepoInfo
    let config: DatabaseConfig
    private let contextProvider: DatabaseConnectionContextProviderProtocol
    private let clock: DatabaseClock
    var lastSessionID: String?
    private var interruptReasons: Set<String> = [kFInterruptReasonWaitingForOpen]
    private var backoff = Backoff()
    var authToken: String?
    private var forceTokenRefreshes = false

    /// Runs the connection; see the type's documentation.
    private var supervisor: Task<Void, Never>?
    /// The current connection, from connecting until it closes.
    private var sessionTask: Task<(end: SessionEnd, wasReady: Bool), Never>?
    private var link: Link?
    /// The supervisor, while it waits for something to change.
    private var wakeWaiter: CheckedContinuation<Void, Never>?

    weak var delegate: FPersistentConnectionDelegate?

    nonisolated
    init(repoInfo: FRepoInfo, config: DatabaseConfig) {
        self.config = config
        self.repoInfo = repoInfo
        self.contextProvider = config.contextProvider
        self.clock = config.clock
        setupNotifications()
        // Doesn't connect until `open()`, so that the delegate can be set first.
    }

    // MARK: -
    // MARK: Public methods

    func open() {
        if supervisor == nil {
            supervisor = Task { @DatabaseActor in await self.run() }
        }
        resumeForReason(kFInterruptReasonWaitingForOpen)
    }

    /// Closes the connection for good.
    func shutdown() {
        interruptForReason(kFInterruptReasonRepoInterrupt)
        supervisor?.cancel()
        supervisor = nil
    }

    public static var userAgent: String {
        var systemVersion: String = ""
        var deviceName: String = ""

#if os(iOS) || os(tvOS)
        systemVersion = UIDevice.current.systemVersion
        deviceName = UIDevice.current.model
#elseif os(macOS)
        let systemVersionDictionary = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist")
        if let version = systemVersionDictionary?["ProductVersion"] as? String {
            systemVersion = version
        }
        if let name = systemVersionDictionary?["ProductName"] as? String {
            deviceName = name
        }
#endif
        var bundleIdentifier = Bundle.main.bundleIdentifier ?? "-"

        // Sanitize '/'s in deviceName and bundleIdentifier for stats
        deviceName = FStringUtilities.sanitizedForUserAgent(deviceName)
        bundleIdentifier = FStringUtilities.sanitizedForUserAgent(bundleIdentifier)

        // Firebase/5/<semver>_<build date>_<git hash>/<os version>/{device model /
        // os (Mac OS X, iPhone, etc.}_<bundle id>
        let ua = "Firebase/\(kWebsocketProtocolVersion)/\(Database.buildVersion)/\(systemVersion)/\(deviceName)_\(bundleIdentifier)"
        return ua
    }

    var userAgent: String {
        FPersistentConnection.userAgent
    }

    func listen(_ query: FQuerySpec,
                tagId: Int?,
                hash: FSyncTreeHash,
                onComplete: @escaping (String) -> Void) {
        FFLog("I-RDB034001", "Listen called for \(query)")
        assert(self.listens[query] == nil,
               "listen() called twice for the same query")
        assert(query.isDefault || !query.loadsAllData,
               "listen called for non-default but complete query")
        let outstanding = FOutstandingQuery(query: query, tagId: tagId, syncTreeHash: hash, onComplete: onComplete)
        listens[query] = outstanding
        if connected {
            sendListen(outstanding)
        }
    }

    func putData(_ data: Any,
                 forPath pathString: String,
                 withHash hash: String?) async -> (String, String?) {
        await withCheckedContinuation { continuation in
            putData(data, forPath: pathString, withHash: hash) { status, errorReason in
                continuation.resume(returning: (status, errorReason))
            }
        }
    }

    /// Queues the put before returning, which transactions rely on: their
    /// hash must still match the local data when the put is queued.
    func putData(_ data: Any,
                 forPath pathString: String,
                 withHash hash: String?,
                 onComplete: @escaping (String, String?) -> Void) {
        putInternal(data,
                    forAction: kFWPRequestActionPut,
                    forPath: pathString,
                    withHash: hash,
                    onComplete: onComplete)
    }

    func mergeData(_ data: Any,
                   forPath pathString: String) async -> (String, String?) {
        await withCheckedContinuation { continuation in
            putInternal(data,
                        forAction: kFWPRequestActionMerge,
                        forPath: pathString,
                        withHash: nil) { status, errorReason in
                continuation.resume(returning: (status, errorReason))
            }
        }
    }

    func onDisconnectPutData(_ data: Any,
                             forPath path: FPath,
                             withCallback callback: @escaping (String, String?) -> Void) {
        onDisconnectAction(kFWPRequestActionDisconnectPut, forPath: path, withData: data, callback: callback)
    }

    func onDisconnectMergeData(_ data: Any,
                               forPath path: FPath,
                               withCallback callback: @escaping (String, String?) -> Void) {
        onDisconnectAction(kFWPRequestActionDisconnectMerge, forPath: path, withData: data, callback: callback)
    }

    func onDisconnectCancelPath(_ path: FPath,
                                withCallback callback: @escaping (String, String?) -> Void) {
        onDisconnectAction(kFWPRequestActionDisconnectCancel, forPath: path, withData: NSNull(), callback: callback)
    }

    private func onDisconnectAction(_ action: String, forPath path: FPath, withData data: Any,
                                    callback: @escaping (String, String?) -> Void) {
        let tuple: OnDisconnectTuple = (pathString: path.description, action: action, data: data, onComplete: callback)
        if canSendWrites {
            sendOnDisconnectAction(tuple)
        } else {
            onDisconnectQueue.append(tuple)
        }
    }

    func unlisten(_ query: FQuerySpec,
                  tagId: Int?) {
        let path = query.path
        FFLog("I-RDB034002", "Unlistening for \(query)")
        let outstanding = removeListen(query)
        if !outstanding.isEmpty && connected {
            sendUnlisten(path, queryParams: query.params, tagId: tagId)
        }
    }

    func refreshAuthToken(_ token: String?) {
        self.authToken = token
        if connected {
            if token != nil {
                sendAuthAndRestoreStateAfterComplete(false)
            } else {
                sendUnauth()
            }
        }
    }

    // MARK: -
    // MARK: Connection status

    private var connected: Bool {
        switch connectionState {
        case .authenticating, .connected:
            return true
        case .disconnected, .connecting, .gettingToken:
            return false
        }
    }

    private var canSendWrites: Bool {
        connectionState == .connected
    }

    private var canSendReads: Bool {
        connectionState == .connected
    }

    // MARK: -
    // MARK: Interrupts

    func interruptForReason(_ reason: String) {
        FFLog("I-RDB034006", "Connection interrupted for: \(reason)")
        interruptReasons.insert(reason)
        // Ends the connection; the supervisor then waits for a resume.
        sessionTask?.cancel()
        wake()
        // Reset timeouts
        backoff.reset()
    }

    func resumeForReason(_ reason: String) {
        FFLog("I-RDB034007", "Connection no longer interrupted for: \(reason)")
        interruptReasons.remove(reason)
        wake()
    }

    var shouldReconnect: Bool {
        interruptReasons.isEmpty
    }

    func isInterruptedForReason(_ reason: String) -> Bool {
        interruptReasons.contains(reason)
    }

    // MARK: -
    // MARK: Running the connection

    private func run() async {
        await withDiscardingTaskGroup { group in
            if let monitor = config.connectivity {
                group.addTask {
                    for await _ in monitor.changes() {
                        await self.networkMayHaveChanged()
                    }
                }
            }
            await connectLoop()
            group.cancelAll()
        }
    }

    private func connectLoop() async {
        while !Task.isCancelled {
            guard shouldReconnect else {
                await waitForWake()
                continue
            }
            let delay = backoff.nextDelay()
            if delay > .zero {
                FFLog("I-RDB034008", "Scheduling connection attempt in \(delay)")
                // Cut short by a resume or a network change.
                await waitForWake(upTo: delay)
                guard shouldReconnect, !Task.isCancelled else { continue }
            }

            FFLog("I-RDB034009", "Trying to fetch auth token")
            connectionState = .gettingToken
            let forceRefresh = forceTokenRefreshes
            forceTokenRefreshes = false
            let context: DatabaseConnectionContext
            do {
                context = try await contextProvider.fetchContextForcingRefresh(forceRefresh)
            } catch {
                FFLog("I-RDB034010", "Error fetching token: \(error)")
                connectionState = .disconnected
                continue
            }
            guard shouldReconnect, !Task.isCancelled else {
                FFLog("I-RDB034012", "Not opening connection after token refresh, because the connection was interrupted.")
                connectionState = .disconnected
                continue
            }
            FFLog("I-RDB034011", "Successfully fetched token, opening connection")
            authToken = context.authToken
            connectionState = .connecting

            let task = Task { @DatabaseActor in
                await self.session(context, transport: self.config.transport)
            }
            sessionTask = task
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            sessionTask = nil
            sessionEnded(result.end, wasReady: result.wasReady)
        }
        connectionState = .disconnected
    }

    /// Wakes the supervisor if it waits for something to change.
    private func wake() {
        let waiter = wakeWaiter
        wakeWaiter = nil
        waiter?.resume()
    }

    /// Waits for `wake()`, cancellation, or `delay` to pass.
    private func waitForWake(upTo delay: Duration? = nil) async {
        let timer = delay.map { delay in
            Task { @DatabaseActor in
                guard (try? await self.clock.sleep(delay)) != nil else { return }
                self.wake()
            }
        }
        defer { timer?.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                wakeWaiter = continuation
            }
        } onCancel: {
            Task { @DatabaseActor in self.wake() }
        }
    }

    /// Connects, runs the connection until it ends, and says why it ended.
    private func session(_ context: DatabaseConnectionContext,
                         transport: some DatabaseTransport) async -> (end: SessionEnd, wasReady: Bool) {
        let connectionURL = repoInfo.connectionURL(lastSessionID: lastSessionID)
        guard let url = URL(string: connectionURL) else {
            // Don't log the URL, since it can include the session ID.
            FFWarn("I-RDB083022", "Couldn't parse the connection URL")
            return (.closed, false)
        }
        FFLog("I-RDB083001", "Connecting to:\(connectionURL) as \(userAgent))")
        let request = DatabaseTransportRequest(
            url: url,
            headers: connectionHeaders(userAgent: userAgent, googleAppID: config.googleAppID,
                                       appCheckToken: context.appCheckToken)
        )
        let (outbox, outboxContinuation) = AsyncStream<DatabaseFrame>.makeStream()
        let (probes, probeContinuation) = AsyncStream<Int>.makeStream()
        let link = Link(outbox: outboxContinuation, probes: probeContinuation, now: clock.now())
        self.link = link
        defer {
            outboxContinuation.finish()
            probeContinuation.finish()
            if self.link === link {
                self.link = nil
            }
        }

        // Everything runs in child tasks, which end with an error, so that the
        // first to end (the server closing, a timeout, a failure) cancels the
        // others. (A group's own body isn't cancelled with its children.)
        do {
            try await withThrowingDiscardingTaskGroup { group in
                // The handshake must arrive in time, connecting included.
                group.addTask {
                    try await self.clock.sleep(.seconds(kWebsocketConnectTimeout))
                    try await self.checkHandshake(link)
                }
                group.addTask {
                    try await self.connect(transport, request: request, link: link, outbox: outbox, probes: probes)
                }
            }
        } catch let end as SessionEnd {
            FFLog("I-RDB083023", "Connection ended: \(end)")
            link.end = link.end ?? end
        } catch {
            FFLog("I-RDB083023", "Connection failed: \(error)")
        }
        return (link.end ?? .closed, link.ready)
    }

    private func connect(_ transport: some DatabaseTransport, request: DatabaseTransportRequest, link: Link,
                         outbox: AsyncStream<DatabaseFrame>, probes: AsyncStream<Int>) async throws {
        try await transport.withConnection(to: request, isolation: #isolation) { connection in
            try await withThrowingDiscardingTaskGroup { group in
                group.addTask {
                    for await frame in outbox {
                        try await connection.send(frame)
                    }
                }
                group.addTask { try await self.keepAlive(link) }
                group.addTask { try await self.checkLiveness(link, probes: probes) }
                group.addTask { try await self.receiveMessages(from: connection, on: link) }
            }
        }
    }

    /// Handles the server's messages until the connection ends.
    private func receiveMessages(from connection: some DatabaseTransportConnection, on link: Link) async throws {
        for try await frame in connection.inbound {
            receive(frame.string, on: link)
            if link.end != nil { break }
        }
        throw link.end ?? SessionEnd.closed
    }

    private func checkHandshake(_ link: Link) throws {
        if !link.ready {
            FFLog("I-RDB083012", "Websocket timed out on connect")
            throw SessionEnd.handshakeTimeout
        }
    }

    /// Sends a "0" when nothing was sent or received for a while, so the
    /// connection isn't closed as idle.
    private func keepAlive(_ link: Link) async throws {
        let interval = Duration.seconds(kWebsocketKeepaliveInterval)
        while true {
            let idle = clock.now() - link.lastActivity
            if idle < interval {
                try await clock.sleep(interval - idle)
                continue
            }
            FFLog("I-RDB083004", "nop")
            // Note: the backend is expecting a string "0" here, not any special
            // ping/pong from build in websocket APIs.
            link.outbox.yield(DatabaseFrame("0"))
            link.lastActivity = clock.now()
        }
    }

    /// Ends the connection if a liveness check isn't answered in time.
    private func checkLiveness(_ link: Link, probes: AsyncStream<Int>) async throws {
        for await requestNumber in probes {
            try await clock.sleep(.seconds(kPersistentConnectionProbeTimeout))
            if case .probe = pending[requestNumber] {
                FFLog("I-RDB034060", "Connection check wasn't answered; reconnecting")
                pending.removeValue(forKey: requestNumber)
                throw SessionEnd.probeTimeout
            }
        }
    }

    /// After a network change or foregrounding: reconnects at once if
    /// disconnected, and checks that the connection still works if connected.
    /// (The old connection can be dead without the socket noticing.)
    func networkMayHaveChanged() {
        backoff.reset()
        wake()
        guard let link, link.ready,
              let requestNumber = sendAction(kFWPRequestActionStats,
                                             body: [kFWPRequestCounters: [String: Any]()],
                                             sensitive: false, expecting: .probe)
        else { return }
        link.probes.yield(requestNumber)
    }

    private func sessionEnded(_ end: SessionEnd, wasReady: Bool) {
        FFLog("I-RDB034004", "Got on disconnect due to \(end)")
        connectionState = .disconnected
        if !wasReady && shouldReconnect {
            FFLog("I-RDB082006", "Realtime connection failed.")
            // Since we failed to connect at all, clear any cached entry for this
            // namespace in case the machine went away
            repoInfo.clearInternalHostCache()
        }
        cancelSentTransactions()
        // Responses to the connection's requests won't come. Puts and listens
        // are sent again on the next connection; so are onDisconnect actions.
        for requestNumber in pending.keys.sorted() {
            if case .onDisconnect(let tuple) = pending[requestNumber] {
                onDisconnectQueue.append(tuple)
            }
        }
        pending.removeAll()
        failSentGets()
        unackedListensCount = 0
        if case .killed(let reason) = end {
            FFWarn("I-RDB034005",
                   "Firebase Database connection was forcefully killed by the server. Will not attempt reconnect. Reason: \(reason)")
            interruptReasons.insert(kFInterruptReasonServerKill)
        }
        if shouldReconnect {
            let lastConnectionWasSuccessful = lastConnectionEstablishedTime.map {
                clock.now() - $0 > .seconds(kPersistentConnSuccessfulConnectionEstablishedDelay)
            } ?? false
            if end == .serverReset || lastConnectionWasSuccessful {
                backoff.reset()
            }
        }
        lastConnectionEstablishedTime = nil
        delegate?.onDisconnect(self)
    }

    /// Closes the current connection; the supervisor reconnects.
    private func closeConnection() {
        sessionTask?.cancel()
    }

    // MARK: -
    // MARK: Server messages

    private func receive(_ frame: String, on link: Link) {
        link.lastActivity = clock.now()
        guard let message = link.assembler.receive(frame) else { return }
        guard let json = (try? JSONSerialization.jsonObject(with: Data(message.utf8))) as? [String: Any] else {
            FFLog("I-RDB082009", "Unrecognized raw server packet received")
            return
        }
        let type = json[kFWPAsyncServerEnvelopeType] as? String
        let data = json[kFWPAsyncServerEnvelopeData] as? [String: Any]
        switch (type, data) {
        case (kFWPAsyncServerDataMessage, let data?):
            FFLog("I-RDB082010", "Got data message: \(data)")
            onDataMessage(data)
        case (kFWPAsyncServerControlMessage, let data?):
            onControl(data, on: link)
        default:
            FFLog("I-RDB082008", "Unrecognized server packet type: \(type ?? "-")")
        }
    }

    private func onControl(_ message: [String: Any], on link: Link) {
        FFLog("I-RDB082011", "Got control message: \(message)")
        let type = message[kFWPAsyncServerControlMessageType] as? String
        let data = message[kFWPAsyncServerControlMessageData]
        switch (type, data) {
        case (kFWPAsyncServerControlMessageShutdown, let reason as String):
            FFLog("I-RDB082013", "Connection shutdown command received. Shutting down...")
            link.end = .killed(reason)
        case (kFWPAsyncServerControlMessageReset, let host as String):
            guard FRepoInfo.isValidHost(host) else {
                // Go back to the configured host instead. Close without
                // SERVER_RESET, so the reconnect uses the normal backoff and
                // doesn't loop without a delay if the server keeps sending this.
                FFWarn("I-RDB082021", "Reset to invalid host \(host); reconnecting to the configured host.")
                repoInfo.clearInternalHostCache()
                link.end = .closed
                return
            }
            FFLog("I-RDB082015",
                  "Got a reset; killing connection to: \(repoInfo.internalHost); Updating internalHost to: \(host)")
            repoInfo.internalHost = host
            link.end = .serverReset
        case (kFWPAsyncServerHello, let handshake as [String: Any]):
            guard let timestamp = (handshake[kFWPAsyncServerHelloTimestamp] as? NSNumber)?.doubleValue,
                  let sessionID = handshake[kFWPAsyncServerHelloSession] as? String
            else { return }
            if let host = handshake[kFWPAsyncServerHelloConnectedHost] as? String {
                repoInfo.internalHost = host
            }
            if !link.ready {
                FFLog("I-RDB082014", "Realtime connection established")
                link.ready = true
                onReady(atTime: timestamp, sessionID: sessionID)
            }
        default:
            FFLog("I-RDB082012", "Unknown control message returned from server: \(message)")
        }
    }

    private func onReady(atTime timestamp: Double, sessionID: String) {
        FFLog("I-RDB034003", "On ready")
        lastConnectionEstablishedTime = clock.now()
        handleTimestamp(timestamp)

        if firstConnection {
            sendConnectStats()
            firstConnection = false
        }
        restoreAuth()
        lastSessionID = sessionID

        self.delegate?.onConnect(self)
    }

    private func onDataMessage(_ message: [String: Any]) {
        if let number = message[kFWPRequestNumber] as? NSNumber {
            // this is a response to a request we sent
            onResponse(number.intValue, data: message[kFWPResponseForRNData] as? [String: Any])
        } else if let error = message[kFWPRequestError] as? String {
            // Log the error and ignore the message: crashing helps no one.
            FFWarn("I-RDB034058", "Received an error from the server: \(error)")
        } else if let action = message[kFWPAsyncServerAction] as? String,
            let body = message[kFWPAsyncServerPayloadBody] as? [String: Any] {
            // this is a server push of some sort
            onDataPush(action, andBody: body)
        }
    }

    private func onResponse(_ requestNumber: Int, data: [String: Any]?) {
        guard let response = pending.removeValue(forKey: requestNumber) else { return }
        let status = data?[kFWPResponseForActionStatus] as? String
        switch response {
        case .put(let index, let put):
            onPutResponse(index, put, data: data)
        case .get(let index, let get):
            onGetResponse(index, get, data: data)
        case .listen(let listen):
            onListenResponse(listen, data: data)
        case .onDisconnect(let tuple):
            tuple.onComplete(status ?? kFWPResponseForActionStatusFailed,
                             data?[kFWPResponseForActionData] as? String)
        case .auth(let restoreState):
            onAuthResponse(data, restoreState: restoreState)
        case .appCheck:
            onAppCheckResponse(data)
        case .stats:
            if status != kFWPResponseForActionStatusOk {
                let errorReason = data?[kFWPResponseForActionData] as? String
                FFLog("I-RDB034042", "Failed to send stats: \(errorReason ?? "-")")
            }
        case .probe:
            FFLog("I-RDB034061", "Connection check answered")
        }
    }

    // MARK: -
    // MARK: Requests

    private func sendAuthAndRestoreStateAfterComplete(_ restoreStateAfterComplete: Bool) {
        assert(connected, "Must be connected to send auth")
        guard let authToken = authToken else {
            assertionFailure("Can't send auth if there is no credential")
            return
        }
        let requestData = [kFWPRequestCredential: authToken]
        sendAction(kFWPRequestActionAuth, body: requestData, sensitive: true,
                   expecting: .auth(restoreState: restoreStateAfterComplete))
    }

    private func onAuthResponse(_ data: [String: Any]?, restoreState restoreStateAfterComplete: Bool) {
        self.connectionState = .connected
        let status = data?[kFWPResponseForActionStatus] as? String
        let responseData = data?[kFWPResponseForActionData] ?? ("error" as AnyHashable)
        let statusOk = status == kFWPResponseForActionStatusOk
        if statusOk {
            if restoreStateAfterComplete {
                self.restoreState()
            }
        } else {
            self.authToken = nil
            self.forceTokenRefreshes = true
            if status == "expired_token" {
                FFLog("I-RDB034017", "Authentication failed: \(status ?? "-") (\(responseData))")
            } else {
                FFWarn("I-RDB034018", "Authentication failed: \(status ?? "-") (\(responseData))")
            }
            closeConnection()
        }
    }

    private func sendUnauth() {
        sendAction(kFWPRequestActionUnauth, body: [:], sensitive: false, expecting: nil)
    }

    private func onAuthRevokedWithStatus(_ status: String?, andReason reason: String?) {
        // This might be for an earlier token than we just recently sent. But since
        // we need to close the connection anyways, we can set it to null here and
        // we will refresh the token later on reconnect
        if status == "expired_token" {
            FFLog("I-RDB034019", "Auth token revoked: \(status ?? "nil") (\(reason ?? "nil"))")
        } else {
            FFWarn("I-RDB034020", "Auth token revoked: \(status ?? "nil") (\(reason ?? "nil"))")
        }
        self.authToken = nil
        self.forceTokenRefreshes = true
        // Try reconnecting on auth revocation
        closeConnection()
    }

    private func onListenRevoked(_ path: FPath) {
        let queries = removeAllListensAtPath(path)
        for query in queries {
            query.onComplete?("permission_denied")
        }
    }

    private func sendOnDisconnectAction(_ tuple: OnDisconnectTuple) {
        let request: [String: Any] = [
            kFWPRequestPath: tuple.pathString,
            kFWPRequestData: tuple.data
        ]
        FFLog("I-RDB034021", "onDisconnect \(tuple.action): \(request)")
        // Responds without a reason when it succeeds; upstream (and this port
        // before) only called back with one, so successes never completed.
        sendAction(tuple.action, body: request, sensitive: false, expecting: .onDisconnect(tuple))
    }

    private func sendPut(_ index: Int) {
        assert(canSendWrites, "sendPut called when not able to send writes")
        guard let put = outstandingPuts[index] else {
            return
        }
        put.sent = true
        sendAction(put.action, body: put.request, sensitive: false, expecting: .put(index: index, put))
    }

    private func onPutResponse(_ index: Int, _ put: FOutstandingPut, data: [String: Any]?) {
        guard outstandingPuts[index] === put else {
            FFLog("I-RDB034022",
                  "Ignoring on complete for put \(index) because it was already removed")
            return
        }
        outstandingPuts.removeValue(forKey: index)
        guard let onComplete = put.onComplete else { return }
        // Successful puts carry no reason, so it must stay optional.
        let status = data?[kFWPResponseForActionStatus] as? String ?? kFWPResponseForActionStatusFailed
        let errorReason = data?[kFWPResponseForActionData] as? String
        if unackedListensCount == 0 {
            onComplete(status, errorReason)
        } else {
            putsToAck.append((onComplete: onComplete, status: status, errorReason: errorReason))
        }
    }

    private func sendGet(_ index: Int) {
        assert(canSendReads, "sendGet called when not able to send reads")
        guard let get = outstandingGets[index] else {
            assertionFailure("sendGet found no outstanding get at index \(index)")
            return
        }
        guard !get.sent else { return }
        get.sent = true
        sendAction(kFWPRequestActionGet, body: get.request, sensitive: false, expecting: .get(index: index, get))
    }

    private func onGetResponse(_ index: Int, _ get: FOutstandingGet, data: [String: Any]?) {
        guard outstandingGets[index] === get else {
            FFLog("I-RDB034045",
                  "Ignoring on complete for get \(index) because it was already removed")
            return
        }
        outstandingGets.removeValue(forKey: index)
        var resultData: Any? = data?[kFWPResponseForActionData]
        if resultData is NSNull {
            resultData = nil
        }
        // Always resumes: a response without a status is a failure.
        let status = data?[kFWPResponseForActionStatus] as? String ?? kFWPResponseForActionStatusFailed
        if status == kFWPResponseForActionStatusOk {
            get.onComplete.resume(returning: .init(status: status, data: resultData, errorReason: nil))
        } else {
            get.onComplete.resume(returning: .init(status: status, data: nil, errorReason: resultData as? String))
        }
    }

    private func sendUnlisten(_ path: FPath,
                              queryParams: FQueryParams,
                              tagId: Int?) {
        FFLog("I-RDB034023", "Unlisten on \(path) for \(queryParams)")
        var request: [String: Any] = [kFWPRequestPath: path.description]
        if let tagId = tagId {
            request[kFWPRequestQueries] = queryParams.wireProtocolParams
            request[kFWPRequestTag] = tagId
        }
        sendAction(kFWPRequestActionTaggedUnlisten, body: request, sensitive: false, expecting: nil)
    }

    private func putInternal(_ data: Any, forAction action: String, forPath pathString: String, withHash hash: String?, onComplete: @escaping (String, String?) -> Void) {
        var request: [String: Any] = [kFWPRequestPath: pathString,
                                      kFWPRequestData: data]
        if let hash = hash {
            request[kFWPRequestHash] = hash
        }
        let put = FOutstandingPut(action: action,
                                  request: request,
                                  onComplete: onComplete,
                                  sent: false)
        let index = putCounter
        putCounter += 1
        outstandingPuts[index] = put
        if canSendWrites {
            FFLog("I-RDB034024", "Was connected, and added as index: \(index)")
            sendPut(index)
        } else {
            FFLog("I-RDB034025",
                  "Wasn't connected or writes paused, so added to outstanding puts only. Path: \(pathString)")
        }
    }

    /// Fails the gets whose responses were lost with the connection, so their
    /// callers fall back to the cache instead of waiting forever. (Upstream
    /// leaves them marked as sent, so they are never resent or answered.)
    private func failSentGets() {
        for (index, get) in outstandingGets where get.sent {
            outstandingGets.removeValue(forKey: index)
            get.onComplete.resume(returning: .init(status: kFWPResponseForActionStatusFailed, data: nil,
                                                   errorReason: kPersistentConnectionOffline))
        }
    }

    /// Gets the data at the path from the server. Fails if not connected
    /// within `kPersistentConnectionGetConnectTimeout`, or when cancelled.
    func getDataAtPath(_ pathString: String,
                       withParams queryWireProtocolParams: [String: Any]) async -> FOutstandingGetResultData {
        let index = getCounter
        getCounter += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let request: [String: Any] = [
                    kFWPRequestPath: pathString,
                    kFWPRequestQueries: queryWireProtocolParams
                ]
                let get = FOutstandingGet(request: request, onComplete: continuation, sent: false)
                outstandingGets[index] = get

                if canSendReads {
                    FFLog("I-RDB034024", "Sending get: \(index)")
                    sendGet(index)
                } else {
                    Task { @DatabaseActor in
                        try? await self.clock.sleep(.seconds(Double(kPersistentConnectionGetConnectTimeout)))
                        guard let get = self.outstandingGets[index], !get.sent else { return }
                        FFLog("I-RDB034045", "get \(index) timed out waiting for a connection")
                        self.outstandingGets.removeValue(forKey: index)
                        get.onComplete.resume(returning: .init(status: kFWPResponseForActionStatusFailed, data: nil,
                                                               errorReason: kPersistentConnectionOffline))
                    }
                }
            }
        } onCancel: {
            Task { @DatabaseActor in
                guard let get = self.outstandingGets.removeValue(forKey: index) else { return }
                get.onComplete.resume(returning: .init(status: kFWPResponseForActionStatusFailed, data: nil,
                                                       errorReason: "cancelled"))
            }
        }
    }

    private func sendListen(_ listenSpec: FOutstandingQuery) {
        let query = listenSpec.query
        FFLog("I-RDB034026", "Listen for \(query)")
        var request: [String: Any] = [kFWPRequestPath: query.path.description]
        // Only bother to send query if it's non-default
        if let tagId = listenSpec.tagId {
            request[kFWPRequestQueries] = query.params.wireProtocolParams
            request[kFWPRequestTag] = tagId
        }
        request[kFWPRequestHash] = listenSpec.syncTreeHash.simpleHash
        if listenSpec.syncTreeHash.includeCompoundHash {
            let compoundHash = listenSpec.syncTreeHash.compoundHash
            var posts: [String] = []
            for path in compoundHash.posts {
                posts.append(path.wireFormat())
            }
            let hashDict: [String: Any] = [
                kFWPRequestCompoundHashHashes: compoundHash.hashes,
                kFWPRequestCompoundHashPaths: posts
            ]
            request[kFWPRequestCompoundHash] = hashDict
        }
        if sendAction(kFWPRequestActionTaggedListen, body: request, sensitive: false,
                      expecting: .listen(listenSpec)) != nil {
            unackedListensCount += 1
        }
    }

    private func onListenResponse(_ listenSpec: FOutstandingQuery, data response: [String: Any]?) {
        let query = listenSpec.query
        FFLog("I-RDB034027", "Listen response \(response ?? [:])")
        // warn in any case, even if the listener was removed
        warnOnListenWarningsForQuery(query, payload: response?[kFWPResponseForActionData])
        // only trigger actions if the listen hasn't been removed (and maybe
        // readded)
        if listens[query] === listenSpec, let status = response?[kFWPRequestStatus] as? String {
            if status != "ok" {
                _ = removeListen(query)
            }
            listenSpec.onComplete?(status)
        }
        unackedListensCount -= 1
        assert(unackedListensCount >= 0, "unackedListensCount decremented to be negative.")
        if unackedListensCount == 0 {
            ackPuts()
        }
    }

    private func warnOnListenWarningsForQuery(_ query: FQuerySpec, payload: Any?) {
        guard let payloadDict = payload as? [String: Any] else { return }
        guard payloadDict[kFWPResponseDataWarnings] as? [String] != nil else { return }
        let indexSpec = "\".indexOn\": \"\(query.params.index.queryDefinition)\""
        let indexPath = query.path.description
        FFWarn("I-RDB034028", """
Using an unspecified index. Your data will be \
downloaded and filtered on the client. \
Consider adding \(indexSpec) at \(indexPath) to your security rules for \
better performance
""")
    }

    /// Sends a request on the current connection, and records what its
    /// response is for. Returns its request number, or nil if not connected.
    @discardableResult
    private func sendAction(_ action: String, body: [String: Any], sensitive: Bool,
                            expecting response: PendingResponse?) -> Int? {
        guard let link, link.ready else { return nil }
        let requestNumber = self.requestNumber
        self.requestNumber += 1
        let message: [String: Any] = [
            kFWPRequestType: kFWPRequestTypeData,
            kFWPRequestDataPayload: [
                kFWPRequestNumber: requestNumber,
                kFWPRequestAction: action,
                kFWPRequestPayloadBody: body,
            ] as [String: Any],
        ]
        if sensitive {
            FFLog("I-RDB082004", "Sending data (contents hidden)")
        } else {
            FFLog("I-RDB082005", "Sending: \(message)")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else {
            FFWarn("I-RDB082022", "Couldn't encode a \(action) request")
            return nil
        }
        for frame in FrameAssembler.frames(for: text) {
            link.outbox.yield(DatabaseFrame(frame))
        }
        link.lastActivity = clock.now()
        if let response {
            pending[requestNumber] = response
        }
        return requestNumber
    }

    private func cancelSentTransactions() {
        var cancelledOutstandingPuts: [Int: FOutstandingPut] = [:]
        for (index, put) in outstandingPuts {
            if put.request[kFWPRequestHash] != nil && put.sent {
                // This is a sent transaction put.
                cancelledOutstandingPuts[index] = put
            }
        }
        for (index, outstandingPut) in cancelledOutstandingPuts {
            // `onCompleteBlock:` may invoke `rerunTransactionsForPath:` and
            // enqueue new writes. We defer calling it until we have finished
            // enumerating all existing writes.
            outstandingPut.onComplete?(kFTransactionDisconnect,
                                       "Client was disconnected while running a transaction")
            outstandingPuts.removeValue(forKey: index)
        }
    }

    private func onDataPush(_ action: String, andBody body: [String: Any]) {
        FFLog("I-RDB034029", "handleServerMessage: \(action), \(body)")
        switch action {
        case kFWPAsyncServerDataUpdate, kFWPAsyncServerDataMerge:
            let isMerge = action == kFWPAsyncServerDataMerge
            if let path = body[kFWPAsyncServerDataUpdateBodyPath] as? String,
               let payloadData = body[kFWPAsyncServerDataUpdateBodyData] {
                if let dict = payloadData as? [String: Any], dict.isEmpty, isMerge {
                    // ignore empty merge
                } else {
                    let tagId = body[kFWPAsyncServerDataUpdateBodyTag] as? Int
                    delegate?.onDataUpdate(self, forPath: path, message: payloadData, isMerge: isMerge, tagId: tagId)
                }
            } else {
                FFLog(
                    "I-RDB034030",
                    "Malformed data response from server missing path or data: \(body)")
            }
        case kFWPAsyncServerDataRangeMerge:
            guard let path = body[kFWPAsyncServerDataUpdateBodyPath] as? String else { return }
            let ranges = (body[kFWPAsyncServerDataUpdateBodyData] as? [[String: Any]]) ?? []
            let tag = body[kFWPAsyncServerDataUpdateBodyTag] as? Int
            var rangeMerges: [FRangeMerge] = []
            for range in ranges {
                let startString = range[kFWPAsyncServerDataUpdateStartPath] as? String
                let endString = range[kFWPAsyncServerDataUpdateEndPath] as? String
                let updateData = range[kFWPAsyncServerDataUpdateRangeMerge]
                let updates = FSnapshotUtilities.nodeFrom(updateData)
                let start = startString.map(FPath.init(with:))
                let end = endString.map(FPath.init(with:))
                let merge = FRangeMerge(start: start, end: end, updates: updates)
                rangeMerges.append(merge)
            }
            delegate?.onRangeMerge(rangeMerges, forPath: path, tagId: tag)
        case kFWPAsyncServerAuthRevoked:
            let status = body[kFWPResponseForActionStatus] as? String
            let reason = body[kFWPResponseForActionData] as? String
            self.onAuthRevokedWithStatus(status, andReason: reason)
        case kFWPASyncServerListenCancelled:
            guard let pathString = body[kFWPAsyncServerDataUpdateBodyPath] as? String else { return }
            onListenRevoked(FPath(with: pathString))
        case kFWPAsyncServerSecurityDebug:
            if let msg = body["msg"] as? String {
                let msgs = msg.components(separatedBy: "\n")
                for m in msgs {
                    FFWarn("I-RDB034031", m)
                }
            }
        default:
            // TODO: revoke listens, auth, security debug
            FFLog("I-RDB034032", "Unsupported action from server: \(action)")
        }
    }

    private func restoreAuth() {
        FFLog("I-RDB034033", "Calling restore state")
        assert(connectionState == .connecting,
                 "Wanted to restore auth, but was in wrong state: \(connectionState)")
        if authToken == nil {
            FFLog("I-RDB034034", "Not restoring auth because token is nil")
            connectionState = .connected
            restoreState()
        } else {
            FFLog("I-RDB034035", "Restoring auth")
            connectionState = .authenticating
            sendAuthAndRestoreStateAfterComplete(true)
        }
    }

    private func restoreState() {
        assert(connectionState == .connected,
                 "Should be connected if we're restoring state, but we are: \(connectionState)")
        for (query, outstandingListen) in listens {
            FFLog("I-RDB034036", "Restoring listen for \(query)")
            sendListen(outstandingListen)
        }
        for key in outstandingPuts.keys.sorted() {
            FFLog("I-RDB034037", "Restoring put: \(key)")
            sendPut(key)
        }
        for key in outstandingGets.keys.sorted() {
            FFLog("I-RDB034037", "Restoring get: \(key)")
            sendGet(key)
        }
        let queue = onDisconnectQueue
        onDisconnectQueue.removeAll()
        for tuple in queue {
            sendOnDisconnectAction(tuple)
        }
    }

    private func removeListen(_ query: FQuerySpec) -> [FOutstandingQuery] {
        assert(query.isDefault || !query.loadsAllData,
               "removeListen called for non-default but complete query"
        )
        if let outstanding = listens[query] {
            listens.removeValue(forKey: query)
            return [outstanding]
        } else {
            FFLog("I-RDB034039",
                  "Trying to remove listener for query \(query) but no listener exists")
            return []
        }
    }

    private func removeAllListensAtPath(_ path: FPath) -> [FOutstandingQuery] {
        FFLog("I-RDB034040", "Removing all listens at path \(path)")
        var removed: [FOutstandingQuery] = []
        var toRemove: [FQuerySpec] = []
        for (spec, outstanding) in listens {
            if spec.path == path {
                removed.append(outstanding)
                toRemove.append(spec)
            }
        }
        for key in toRemove {
            listens.removeValue(forKey: key)
        }

        return removed
    }

    func purgeOutstandingWrites() {
        // We might have unacked puts in our queue that we need to ack now before we
        // send out any cancels...
        ackPuts()
        // Cancel in order
        let keys = outstandingPuts.keys.sorted()
        for key in keys {
            guard let put = outstandingPuts[key] else { continue }
            put.onComplete?(kFErrorWriteCanceled, nil)
        }
        for onDisconnect in onDisconnectQueue {
            onDisconnect.onComplete(kFErrorWriteCanceled, nil)
        }
        outstandingPuts.removeAll()
        onDisconnectQueue.removeAll()
    }

    private func ackPuts() {
        for put in putsToAck {
            put.onComplete(put.status, put.errorReason)
        }
        putsToAck.removeAll()
    }

    private func handleTimestamp(_ timestamp: Double) {
        FFLog("I-RDB034041", "Handling timestamp: \(timestamp)")
        let timestampDeltaMs = timestamp - Date().timeIntervalSince1970 * 1000
        delegate?.onServerInfoUpdate(self, updates: [kDotInfoServerTimeOffset: timestampDeltaMs])
    }

    private func sendStats(_ stats: [String: Any]) {
        guard !stats.isEmpty else {
            FFLog("I-RDB034043", "Not sending stats because stats are empty")
            return
        }
        sendAction(kFWPRequestActionStats, body: [kFWPRequestCounters: stats], sensitive: false, expecting: .stats)
    }

    private func sendConnectStats() {
        var stats: [String: Any] = [:]
#if os(iOS) || os(tvOS)
        if config.persistenceEnabled {
            stats["persistence.ios.enabled"] = 1
        }
#elseif os(macOS)
        if config.persistenceEnabled {
            stats["persistence.osx.enabled"] = 1
        }
#elseif os(watchOS)
        if config.persistenceEnabled {
            stats["persistence.watchos.enabled"] = 1
        }
#endif
        let sdkVersion = Database.sdkVersion.replacingOccurrences(of: ".", with: "-")
        let sdkStatName = "sdk.swift.\(sdkVersion)"
        stats[sdkStatName] = 1
        FFLog("I-RDB034044", "Sending first connection stats")
        sendStats(stats)
    }

    nonisolated
    private func setupNotifications() {
#if canImport(Darwin)
        // A system clock change makes `.info/serverTimeOffset` stale. Reconnect,
        // so the server's handshake refreshes it.
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange,
                                               object: nil, queue: nil) { [weak self] _ in
            Task { @DatabaseActor in
                self?.interruptForReason(kFInterruptReasonSystemClockChange)
                self?.resumeForReason(kFInterruptReasonSystemClockChange)
            }
        }
#endif
    }

    // Testing methods
    func dumpListens() -> [FQuerySpec: FOutstandingQuery] {
        listens
    }

    /// Whether a liveness check waits for its answer.
    var isCheckingConnection: Bool {
        pending.values.contains { if case .probe = $0 { true } else { false } }
    }

    // MARK: - App Check Token update
    func refreshAppCheckToken(_ token: String) {
        if !connected {
            // A fresh FAC token will be sent as a part of initial handshake.
            return
        }
        if token.isEmpty {
            // No token to send.
            return
        }
        // Send updated FAC token to the open connection.
        sendAction(kFWPRequestActionAppCheck, body: [kFWPRequestAppCheckToken: token], sensitive: true,
                   expecting: .appCheck)
    }

    private func onAppCheckResponse(_ data: [String: Any]?) {
        let status = data?[kFWPResponseForActionStatus] as? String
        let responseData: Any = data?[kFWPResponseForActionData] ?? "Response data was empty."
        if status != kFWPResponseForActionStatusOk {
            self.authToken = nil
            self.forceTokenRefreshes = true
            if status == "invalid_token" {
                FFLog("I-RDB034045", "App check failed: \(status ?? "-") (\(responseData))")
            } else {
                FFWarn("I-RDB034046", "App check failed: \(status ?? "-") (\(responseData))")
            }
            closeConnection()
        }
    }
}
