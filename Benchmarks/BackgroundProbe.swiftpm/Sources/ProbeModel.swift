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

import FirebaseCore
import FirebaseDatabase
import Foundation
import Network
import Observation
import os

/// The transports to compare.
enum ProbeTransport: String, CaseIterable, Identifiable, Codable, Sendable {
    case nio
    case networkFramework
    case urlSession

    var id: Self { self }

    var title: String {
        switch self {
        case .nio: "NIO (POSIX sockets, swift-nio-ssl)"
        case .networkFramework: "NIO on Network.framework"
        case .urlSession: "URLSession"
        }
    }

    var transport: any DatabaseTransport {
        switch self {
        case .nio: NIODatabaseTransport()
        case .networkFramework: NIOTSDatabaseTransport()
        case .urlSession: URLSessionDatabaseTransport()
        }
    }
}

/// The situations from the upstream issues, to label the measurements with.
enum ProbeScenario: String, CaseIterable, Identifiable, Codable, Sendable {
    case background30s = "Background 30 s"
    case background5min = "Background 5 min"
    case background30min = "Background 30 min"
    case screenOff10min = "Screen off 10 min"
    case wifiToCellular = "Wi-Fi → cellular"
    case cellularToWifi = "Cellular → Wi-Fi"
    case airplaneMode = "Airplane mode on, then off"
    case lowPowerMode = "Low Power Mode"
    case other = "Other"

    var id: Self { self }

    /// What to do, and which upstream issue it's from.
    var instructions: String {
        switch self {
        case .background30s, .background5min, .background30min:
            "Send the app to the background for that long, then open it again (#14188, #13877)."
        case .screenOff10min:
            "Lock the phone for 10 minutes with the app open, then unlock it (#13855)."
        case .wifiToCellular:
            "Turn Wi-Fi off in Control Center while the app is open."
        case .cellularToWifi:
            "Turn Wi-Fi on again while the app is open."
        case .airplaneMode:
            "Turn airplane mode on for a minute, then off, with the app open."
        case .lowPowerMode:
            "Turn Low Power Mode on, then repeat a background scenario."
        case .other:
            "Anything else; describe it in the note."
        }
    }
}

/// One thing that happened, as a line of the log.
struct ProbeEvent: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case started, background, foreground, connected, disconnected
        case sentNonce, receivedNonce, timedOut, pathChanged, failed
    }

    var id = UUID()
    var date = Date()
    var transport: ProbeTransport
    var scenario: ProbeScenario
    var kind: Kind
    /// Milliseconds since the app came to the foreground, for the events of a
    /// foreground test.
    var sinceForeground: Double?
    var network: String
    var lowPowerMode: Bool
    var detail: String?
}

/// Runs the probe: keeps a connection with the chosen transport, and on each
/// return to the foreground checks how long until the connection delivers a
/// change written meanwhile over REST (which a dead connection never does,
/// though `.info/connected` may still say it's connected).
@MainActor
@Observable
final class ProbeModel {
    var databaseURL = UserDefaults.standard.string(forKey: "databaseURL") ?? "" {
        didSet { UserDefaults.standard.set(databaseURL, forKey: "databaseURL") }
    }

    var transport = ProbeTransport(rawValue: UserDefaults.standard.string(forKey: "transport") ?? "") ?? .nio {
        didSet {
            UserDefaults.standard.set(transport.rawValue, forKey: "transport")
            if isRunning { start() }
        }
    }

    var scenario = ProbeScenario.background30s
    var note = ""
    private(set) var isRunning = false
    private(set) var isConnected = false
    private(set) var events: [ProbeEvent] = []
    private(set) var network = "unknown"

    /// How long a foreground test waits for the change before it counts as a
    /// connection that never recovered.
    let timeout = Duration.seconds(60)

    private let probeID: String = {
        if let id = UserDefaults.standard.string(forKey: "probeID") { return id }
        let id = UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(id, forKey: "probeID")
        return id
    }()

    private var listeners: [Task<Void, Never>] = []
    /// The app for each transport and database URL.
    private var appNames: [String: String] = [:]
    private var database: Database?
    /// The test in progress: its nonce and when the app came to the foreground.
    private var pending: (nonce: String, foreground: ContinuousClock.Instant, timeout: Task<Void, Never>)?
    private var inForeground = true
    private let pathMonitor = NWPathMonitor()
    private let signposter = OSSignposter(subsystem: "dev.firebase-swift.BackgroundProbe", category: "Probe")
    private var signpostState: OSSignpostIntervalState?

    let logURL = URL.documentsDirectory.appending(path: "probe-log.jsonl")

    init() {
        events = Self.loadLog(logURL)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let description = Self.describe(path)
            Task { @MainActor in self?.pathChanged(description) }
        }
        pathMonitor.start(queue: .main)
    }

    // MARK: Running

    /// Connects with the chosen transport and listens.
    func start() {
        stop()
        guard let database = makeDatabase() else { return }
        self.database = database
        isRunning = true
        record(.started, detail: transport.title)
        let connected = database.reference().child(".info/connected")
        listeners.append(Task { [weak self] in
            do {
                for try await snapshot in connected.values() {
                    self?.connectionChanged(snapshot.value as? Bool ?? false)
                }
            } catch {
                self?.record(.failed, detail: "\(error)")
            }
        })
        let ping = pingRef(database)
        listeners.append(Task { [weak self] in
            do {
                for try await snapshot in ping.values() {
                    self?.received(snapshot.childSnapshot(forPath: "nonce").value as? String)
                }
            } catch {
                self?.record(.failed, detail: "\(error)")
            }
        })
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners = []
        pending?.timeout.cancel()
        pending = nil
        database?.goOffline()
        database = nil
        isRunning = false
        isConnected = false
    }

    /// A Database for the chosen transport (an app per transport, as a
    /// database's transport can't change once it's in use).
    private func makeDatabase() -> Database? {
        guard let target = Target(databaseURL) else {
            record(.failed, detail: "Enter a database URL")
            return nil
        }
        // A name per transport and database, as settings can't change once
        // a database is in use.
        let key = "\(transport.rawValue) \(databaseURL)"
        let name = appNames[key] ?? "probe-\(appNames.count)"
        appNames[key] = name
        if let app = FirebaseApp.app(name: name) {
            let database = Database.database(app: app, url: target.databaseURL)
            database.goOnline()
            return database
        }
        var options = FirebaseOptions(googleAppID: "1:1:ios:1", gcmSenderID: "1")
        options.projectID = target.namespace
        options.apiKey = "probe"
        options.databaseURL = target.databaseURL
        FirebaseApp.configure(name: name, options: options)
        guard let app = FirebaseApp.app(name: name) else { return nil }
        let database = Database.database(app: app, url: target.databaseURL)
        if let emulator = target.emulator {
            database.useEmulator(withHost: emulator.host, port: emulator.port)
        }
        database.transport = transport.transport
        return database
    }

    private func pingRef(_ database: Database) -> DatabaseReference {
        database.reference().child("probe/\(probeID)/ping")
    }

    // MARK: Events

    func sceneBecameActive() {
        guard !inForeground else { return }
        inForeground = true
        record(.foreground)
        guard isRunning else { return }
        Task { await sendNonce() }
    }

    func sceneEnteredBackground() {
        inForeground = false
        record(.background)
    }

    /// Writes a nonce over REST, and starts waiting for the connection to
    /// deliver it.
    func sendNonce() async {
        guard let target = Target(databaseURL) else { return }
        let nonce = UUID().uuidString
        let foreground = ContinuousClock.now
        pending?.timeout.cancel()
        let timeout = Task { [weak self, timeout = self.timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.timedOut(nonce)
        }
        pending = (nonce, foreground, timeout)
        signpostState = signposter.beginInterval("Foreground to remote event")
        var request = URLRequest(url: target.restURL(path: "probe/\(probeID)/ping"))
        request.httpMethod = "PUT"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["nonce": nonce, "at": [".sv": "timestamp"]])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            record(.sentNonce, detail: "HTTP \(status)")
        } catch {
            record(.failed, detail: "REST write failed: \(error.localizedDescription)")
        }
    }

    private func received(_ nonce: String?) {
        guard let nonce, let pending, pending.nonce == nonce else { return }
        pending.timeout.cancel()
        self.pending = nil
        if let signpostState {
            signposter.endInterval("Foreground to remote event", signpostState)
        }
        record(.receivedNonce, since: pending.foreground)
    }

    private func timedOut(_ nonce: String) {
        guard let pending, pending.nonce == nonce else { return }
        self.pending = nil
        record(.timedOut, since: pending.foreground, detail: "No change within \(timeout); the connection didn't recover")
    }

    private func connectionChanged(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        // A disconnect in the foreground, without a network change, is spurious.
        record(connected ? .connected : .disconnected, since: pending?.foreground,
               detail: connected || !inForeground ? nil : "while in the foreground")
    }

    private func pathChanged(_ description: String) {
        guard description != network else { return }
        network = description
        record(.pathChanged, detail: description)
    }

    private func record(_ kind: ProbeEvent.Kind, since start: ContinuousClock.Instant? = nil, detail: String? = nil) {
        var detail = detail
        if !note.isEmpty {
            detail = [detail, note].compactMap { $0 }.joined(separator: " · ")
        }
        let event = ProbeEvent(
            transport: transport, scenario: scenario, kind: kind,
            sinceForeground: start.map { (ContinuousClock.now - $0) / .milliseconds(1) },
            network: network, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, detail: detail
        )
        events.append(event)
        signposter.emitEvent("Probe event", "\(kind.rawValue, privacy: .public)")
        Self.append(event, to: logURL)
    }

    func clearLog() {
        events = []
        try? FileManager.default.removeItem(at: logURL)
    }

    // MARK: Summary

    struct Summary: Identifiable {
        var id: String { "\(transport.rawValue)/\(scenario.rawValue)" }
        let transport: ProbeTransport
        let scenario: ProbeScenario
        let tests: Int
        let medianMilliseconds: Double?
        let worstMilliseconds: Double?
        let timeouts: Int
        let spuriousDisconnects: Int
    }

    /// The foreground tests by transport and scenario.
    var summaries: [Summary] {
        let groups = Dictionary(grouping: events) { "\($0.transport.rawValue)/\($0.scenario.rawValue)" }
        return groups.values.compactMap { events -> Summary? in
            guard let first = events.first else { return nil }
            let times = events.filter { $0.kind == .receivedNonce }.compactMap(\.sinceForeground).sorted()
            let timeouts = events.filter { $0.kind == .timedOut }.count
            guard !times.isEmpty || timeouts > 0 else { return nil }
            return Summary(
                transport: first.transport, scenario: first.scenario, tests: times.count + timeouts,
                medianMilliseconds: times.isEmpty ? nil : times[times.count / 2], worstMilliseconds: times.last,
                timeouts: timeouts,
                spuriousDisconnects: events.filter { $0.kind == .disconnected && $0.detail?.contains("foreground") == true }.count
            )
        }
        .sorted { ($0.transport.rawValue, $0.scenario.rawValue) < ($1.transport.rawValue, $1.scenario.rawValue) }
    }

    // MARK: Helpers

    nonisolated private static func describe(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "offline" }
        let interface = [NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet]
            .first { path.usesInterfaceType($0) }
        let name = switch interface {
        case .wifi: "Wi-Fi"
        case .cellular: "cellular"
        case .wiredEthernet: "Ethernet"
        default: "other"
        }
        return path.isConstrained ? "\(name) (Low Data Mode)" : name
    }

    nonisolated private static func append(_ event: ProbeEvent, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(event) else { return }
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    nonisolated private static func loadLog(_ url: URL) -> [ProbeEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(ProbeEvent.self, from: $0) }
    }
}

/// The database to probe: a Realtime Database URL
/// (`https://<project>-default-rtdb.firebaseio.com`), or an emulator on the
/// network (`http://192.168.1.10:9000?ns=<namespace>`).
struct Target {
    let databaseURL: String
    let namespace: String
    let emulator: (host: String, port: Int)?
    private let restBase: URL
    private let restQuery: String?

    init?(_ string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)), let host = url.host,
              let scheme = url.scheme
        else { return nil }
        if scheme == "http" {
            let namespace = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "ns" }?.value ?? "demo-probe"
            self.namespace = namespace
            databaseURL = "https://\(namespace).firebaseio.com"
            emulator = (host, url.port ?? 9000)
            restBase = URL(string: "http://\(host):\(url.port ?? 9000)")!
            restQuery = "ns=\(namespace)"
        } else {
            namespace = String(host.split(separator: ".").first ?? "")
            databaseURL = "https://\(host)"
            emulator = nil
            restBase = URL(string: "https://\(host)")!
            restQuery = nil
        }
    }

    func restURL(path: String) -> URL {
        var components = URLComponents(url: restBase.appending(path: "\(path).json"), resolvingAgainstBaseURL: false)!
        components.query = restQuery
        return components.url!
    }
}
