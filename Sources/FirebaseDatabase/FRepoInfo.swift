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
    var internalHost: String {
        didSet {
            if internalHost != oldValue {
                let internalHostKey = "firebase:host:\(host)"
                UserDefaults.standard.set(internalHost, forKey: internalHostKey)
            }
        }
    }
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
        if let cachedInternalHost = UserDefaults.standard.string(forKey: internalHostKey) {
            self.internalHost = cachedInternalHost
        } else {
            self.internalHost = host
        }
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
        // Remove the cached entry
        self.internalHost = self.host
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
