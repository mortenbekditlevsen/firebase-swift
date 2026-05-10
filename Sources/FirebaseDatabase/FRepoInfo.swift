//
//  File.swift
//  File
//
//  Created by Morten Bek Ditlevsen on 14/09/2021.
//

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
