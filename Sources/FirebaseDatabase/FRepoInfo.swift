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

public struct FRepoInfo: Hashable, Sendable {

    /// The host that the database should connect to.
    public let host: String

    public let namespace: String

    /// The host to connect to: a host the server provided, if any, else
    /// `host`. It's saved across launches. Setting a host that isn't valid
    /// (see `isValidHost(_:)`) has no effect.
    var internalHost: String {
        get { _internalHost }
        set {
            guard newValue != _internalHost else { return }
            // The host comes from the server and is saved across launches, so
            // ignore a host that can't be used in a URL.
            guard Self.isValidHost(newValue) else {
                FFWarn("I-RDB039002", "Ignoring invalid database host: \(newValue)")
                return
            }
            _internalHost = newValue
            let internalHostKey = "firebase:host:\(host)"
            UserDefaults.standard.set(newValue, forKey: internalHostKey)
        }
    }
    private var _internalHost: String
    var secure: Bool
    public let domain: String

    init(host: String, isSecure: Bool, withNamespace namespace: String) {
        self.host = host
        self.namespace = namespace
        self.secure = isSecure
        if let index = host.firstIndex(of: ".") {
            let after = host.index(after: index)
            self.domain = String(host[after...])
        } else {
            self.domain = host
        }
        let internalHostKey = "firebase:host:\(host)"
        if let cachedInternalHost = UserDefaults.standard.string(forKey: internalHostKey),
           Self.isValidHost(cachedInternalHost) {
            self._internalHost = cachedInternalHost
        } else {
            if let cachedInternalHost = UserDefaults.standard.string(forKey: internalHostKey) {
                // Earlier versions saved any host the server sent, and one that
                // can't be used in a URL crashed the app at every launch.
                FFWarn("I-RDB039001", "Ignoring invalid saved database host: \(cachedInternalHost)")
                UserDefaults.standard.removeObject(forKey: internalHostKey)
            }
            self._internalHost = host
        }
    }

    /// Whether `host` is acceptable as a server-provided host: 1 to 253 ASCII
    /// letters, digits, '.' or '-', with an optional numeric port. IPv6
    /// literals and '_' are rejected. Server hosts look like
    /// `s-usc1a-nss-2001.firebaseio.com`; emulator hosts like `localhost:9000`.
    static func isValidHost(_ host: String) -> Bool {
        var name = Substring(host)
        if let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard (1 ... 5).contains(port.count),
                  port.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            name = host[..<colon]
        }
        guard (1 ... 253).contains(name.count),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return false }
        // Defense in depth: URL must accept the host too.
        return URL(string: "wss://\(host)/")?.host?.isEmpty == false
    }

    var description: String {
        return "http\(secure ? "s" : ""):\(host)"
    }

    init(info: FRepoInfo, emulatedHost: String) {
        self.init(host: emulatedHost, isSecure: false, withNamespace: info.namespace)
    }

    func connectionURL(lastSessionID: String?) -> String {
        let scheme: String
        if secure {
            scheme = "wss"
        } else {
            scheme = "ws"
        }
        var url = "\(scheme)://\(internalHost)/.ws?\(kWireProtocolVersionParam)=\(kWebsocketProtocolVersion)&ns=\(namespace)"

        if let lastSessionID = lastSessionID {
            url += "&ls=\(lastSessionID)"
        }
        return url
    }

    var connectionURL: String {
        connectionURL(lastSessionID: nil)
    }

    public mutating func clearInternalHostCache() {
        // Assign directly rather than through the setter: the configured host
        // must always be accepted, even if it doesn't pass `isValidHost(_:)`
        // (e.g. an IPv6 emulator host).
        self._internalHost = self.host
        // Remove the cached entry
        let internalHostKey = "firebase:host:\(host)"
        UserDefaults.standard.removeObject(forKey: internalHostKey)
    }

    var isDemoHost: Bool {
        domain == "firebaseio-demo.com"
    }

    var isCustomHost: Bool {
        domain != "firebaseio-demo.com" &&
        domain != "firebaseio.com"
    }
}
