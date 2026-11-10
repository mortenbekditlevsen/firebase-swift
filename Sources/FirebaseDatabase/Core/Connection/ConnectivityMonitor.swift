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
#if canImport(Network)
    import Network
#endif
#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#elseif os(watchOS)
    import WatchKit
#endif

/// Tells the connection when the network may have changed: when a network
/// path becomes usable, and when the app returns to the foreground. The
/// connection then retries at once if it's disconnected, and checks that
/// it's still alive if it's connected.
protocol ConnectivityMonitor: Sendable {
    /// Yields on each change; finishes when cancelled.
    func changes() -> AsyncStream<Void>
}

/// The platform's monitor: Network framework paths and app foregrounding on
/// Apple platforms; none elsewhere.
var platformConnectivityMonitor: (any ConnectivityMonitor)? {
    #if canImport(Network)
        SystemConnectivityMonitor()
    #else
        nil
    #endif
}

#if canImport(Network)
    struct SystemConnectivityMonitor: ConnectivityMonitor {
        private static let queue = DispatchQueue(label: "com.google.firebase.database.connectivity")

        func changes() -> AsyncStream<Void> {
            AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                // Unlike SCNetworkReachability, this sees changes between
                // usable paths too (e.g. Wi-Fi to cellular), after which the
                // old connection may be dead.
                let monitor = NWPathMonitor()
                let state = PathState()
                monitor.pathUpdateHandler = { path in
                    if state.changed(to: path), path.status == .satisfied {
                        FFLog("I-RDB034014", "Network path changed. Checking the connection")
                        continuation.yield()
                    }
                }
                monitor.start(queue: Self.queue)

                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                    let foreground = Task { @MainActor in
                        #if os(watchOS)
                            let name = WKApplication.willEnterForegroundNotification
                        #else
                            let name = UIApplication.willEnterForegroundNotification
                        #endif
                        for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                            continuation.yield()
                        }
                    }
                #endif
                continuation.onTermination = { _ in
                    monitor.cancel()
                    #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                        foreground.cancel()
                    #endif
                }
            }
        }
    }

    /// The last path seen, to skip the first update (the current path) and
    /// updates that change nothing.
    private final class PathState: @unchecked Sendable {
        // Only used on the monitor's serial queue.
        private var last: NWPath?

        func changed(to path: NWPath) -> Bool {
            defer { last = path }
            guard let last else { return false }
            return last != path
        }
    }
#endif
