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
import Synchronization

/// The firebase-ios-sdk release this package corresponds to, sent to the
/// backends in version headers. Keep it in sync with `firebaseVersion` in
/// Package.swift; UPSTREAM.md has each module's actual baseline.
public func FirebaseVersion() -> String {
    "12.14.0"
}


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
        public init(
            databaseURL: String? = nil,
            projectID: String? = nil,
            googleAppID: String,
            apiKey: String?,
            clientID: String?,
            storageBucket: String?
        ) {
            self.databaseURL = databaseURL
            self.projectID = projectID
            self.googleAppID = googleAppID
            self.apiKey = apiKey
            self.clientID = clientID
            self.storageBucket = storageBucket
        }

        public var databaseURL: String?
        public var projectID: String?
        public var googleAppID: String
        public var apiKey: String?
        public var clientID: String?
        public var storageBucket: String?

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

    // XXX TODO: Should this call configure and return non-nil?
    public static func app() -> FirebaseApp? {
        defaultApp
    }
    
    public var appCheck: AppCheckInterop? {
        get { _appCheck.withLock { $0 } }
        set { _appCheck.withLock { $0 = newValue } }
    }
}

public protocol AuthInterop: AnyObject, Sendable {
    func getToken(forcingRefresh forceRefresh: Bool) async throws -> String?
    func getUserID() -> String?
}

extension Notification.Name {
    /// Posted by Auth whenever the signed-in user or their ID token changes,
    /// for other Firebase SDKs (Database, Firestore) to refresh credentials.
    /// `object` is the `AuthInterop` instance and `userInfo` holds the
    /// `FIRAuthStateDidChangeInternalNotification…Key` entries. Unlike the
    /// public Auth notification, it is not posted on the main queue.
    public static let FIRAuthStateDidChangeInternalNotification =
        Notification.Name("FIRAuthStateDidChangeInternalNotification")
}

/// The `FirebaseApp` the notifying Auth instance belongs to.
public let FIRAuthStateDidChangeInternalNotificationAppKey =
    "FIRAuthStateDidChangeInternalNotificationAppKey"
/// The new ID token; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationTokenKey =
    "FIRAuthStateDidChangeInternalNotificationTokenKey"
/// The new user's UID; absent when signed out.
public let FIRAuthStateDidChangeInternalNotificationUIDKey =
    "FIRAuthStateDidChangeInternalNotificationUIDKey"
