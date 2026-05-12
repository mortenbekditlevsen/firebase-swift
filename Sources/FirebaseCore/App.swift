//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 20/06/2023.
//

import Foundation
import Synchronization

// Dummy protocol since I don't have heartbeatlogger working yet
public protocol FIRHeartbeatLoggerProtocol: Sendable {

}

// Dummy protocol since I don't have AppCheck working yet
public protocol AppCheckInterop: Sendable {
    func getToken(forcingRefresh: Bool) async throws -> String

}

public final class FirebaseApp: Equatable, Sendable {
    public static func == (lhs: FirebaseApp, rhs: FirebaseApp) -> Bool {
        lhs.name == rhs.name && lhs.options == rhs.options
    }

    public struct Options: Equatable, Sendable {
        public init(databaseURL: String? = nil, projectID: String? = nil, googleAppID: String, apiKey: String?, clientID: String?) {
            self.databaseURL = databaseURL
            self.projectID = projectID
            self.googleAppID = googleAppID
            self.apiKey = apiKey
            self.clientID = clientID
        }

        public var databaseURL: String?
        public var projectID: String?
        public var googleAppID: String
        public var apiKey: String?
        public var clientID: String?
    }
    public var name: String { _name.withLock { $0} }
    public var options: Options { _options.withLock { $0 } }
    public var auth: AuthInterop? {
        get { _auth.withLock { $0 } }
        set { _auth.withLock { $0 = newValue} }
    }
    public var heartbeatLogger: FIRHeartbeatLoggerProtocol? {
        get { _heartbeatLogger.withLock { $0 } }
        set { _heartbeatLogger.withLock { $0 = newValue} }
    }

    private let _auth: Mutex<AuthInterop?> = .init(nil)
    private let _appCheck: Mutex<AppCheckInterop?> = .init(nil)
    private let _name: Mutex<String>
    private let _options: Mutex<Options>
    private let _heartbeatLogger: Mutex<FIRHeartbeatLoggerProtocol?> = .init(nil)
    public init(options: Options, name: String) {
        self._options = .init(options)
        self._name = .init(name)
    }
    public static var isDefaultAppConfigured: Bool { defaultApp != nil }
    public static func configure(name: String? = nil, options: Options) {
        _defaultApp.withLock {
            $0 = FirebaseApp(options: options, name: name ?? "[DEFAULT]")
        }
    }
    public static var defaultApp: FirebaseApp? { _defaultApp.withLock { $0 } }
    private static let _defaultApp: Mutex<FirebaseApp?> = .init(nil)

    public var appCheck: AppCheckInterop? {
        get { _appCheck.withLock { $0 } }
        set { _appCheck.withLock { $0 = newValue } }
    }
}

public protocol AuthInterop: AnyObject, Sendable {
    func getToken(forcingRefresh forceRefresh: Bool) async throws -> String?
    func getUserID() -> String?
}
