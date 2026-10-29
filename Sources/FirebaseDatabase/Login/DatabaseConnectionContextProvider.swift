// Copyright 2021 Google LLC
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
import FirebaseCore
import Synchronization

struct DatabaseConnectionContext: Sendable {
    /// Auth token if available.
    var authToken: String?

    /// App check token if available.
    var appCheckToken: String?

    init(authToken: String?, appCheckToken: String?) {
        self.authToken = authToken
        self.appCheckToken = appCheckToken
    }
}

protocol DatabaseConnectionContextProviderProtocol: Sendable {
    func fetchContextForcingRefresh(_ forceRefresh: Bool) async throws -> DatabaseConnectionContext

    /// Adds a listener to the Auth token updates.
    /// @param listener A block that will be invoked each time the Auth token is
    /// updated, with `nil` when the user signs out.
    func listenForAuthTokenChanges(_ listener:  @escaping @DatabaseActor (String?) -> Void)

    /// Adds a listener to the FAC token updates.
    /// @param listener A block that will be invoked each time the FAC token is
    /// updated.
    func listenForAppCheckTokenChanges(_ listener: @escaping @DatabaseActor (String) -> Void)
}

private final class FAuthStateListenerWrapper: @unchecked Sendable {
    private let listener: @DatabaseActor (String?) -> Void
    private weak var auth: AuthInterop?
    private var observer: (any NSObjectProtocol)?

    init(listener: @escaping @DatabaseActor (String?) -> Void, auth: AuthInterop) {
        self.listener = listener
        self.auth = auth
        observer = NotificationCenter.default.addObserver(forName: .FIRAuthStateDidChangeInternalNotification, object: nil, queue: nil) { [weak self] notification in
            let userInfo = notification.userInfo
            guard (notification.object as? AnyObject) === self?.auth else { return }
            // No token means the user signed out; the connection then unauthenticates.
            let token = userInfo?[FIRAuthStateDidChangeInternalNotificationTokenKey] as? String
            Task { @DatabaseActor in
                self?.listener(token)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

//protocol DatabaseAuthInterop: AnyObject {
//    func getTokenForcingRefresh(_ forceRefresh: Bool, withCallback callback: (String?, Error?) -> Void)
//}

protocol DatabaseAppCheckTokenResultInterop {
    var token: String? { get }
    var error: Error? { get }
}

protocol DatabaseAppCheckInterop: Sendable {
    func getTokenForcingRefresh(_ forceRefresh: Bool) async throws -> String
    var notificationTokenKey: String { get }
    var tokenDidChangeNotificationName: Notification.Name { get }
}

// TODO: Make FIRAppCheckInterop conform to FIRDatabaseAppCheckInterop
// TODO: Make FIRAppCheckTokenResultInterop conform to FIRDatabaseAppCheckTokenResultInterop
// TODO: Make FIRAuthInterop conform to FIRDatabaseAuthInterop

struct SendableObserver: @unchecked Sendable {
    let observer: Any
}

final class DatabaseConnectionContextProvider: DatabaseConnectionContextProviderProtocol {

    let appCheck: DatabaseAppCheckInterop? // FIRAppCheckInterop
    let auth: AuthInterop? // FIRAuthInterop

    /// Strong references to the auth listeners as they are only weak in
    /// FIRFirebaseApp.
    private let authListeners: Mutex<[FAuthStateListenerWrapper]> = .init([])

    /// Observer objects returned by
    /// `-[NSNotificationCenter addObserverForName:object:queue:usingBlock:]`
    /// method. Required to cleanup the observers on dealloc.
    let appCheckNotificationObservers: Mutex<[SendableObserver]> = .init([])

    private init(auth: AuthInterop?,
                 appCheck: DatabaseAppCheckInterop?) {
        self.appCheck = appCheck
        self.auth = auth
    }

    deinit {
        for wrapper in self.appCheckNotificationObservers.withLock({ $0 }) {
            NotificationCenter.default.removeObserver(wrapper.observer)
        }
    }

    func fetchContextForcingRefresh(_ forceRefresh: Bool) async throws -> DatabaseConnectionContext {
        guard self.auth != nil || self.appCheck != nil else {
            // Nothing to fetch. Finish straight away.
            return DatabaseConnectionContext(authToken: nil, appCheckToken: nil)
        }
        // Use dispatch group to call the callback when both Auth and FAC operations
        // finished.
        let authToken = try await auth?.getToken(forcingRefresh: forceRefresh)
        let appCheckToken: String?
            
        do {
            appCheckToken = try await appCheck?.getTokenForcingRefresh(forceRefresh)
        } catch {
            FFLog("I-RDB096001", "Failed to fetch App Check token: \(error)")
            appCheckToken = nil
        }
        return DatabaseConnectionContext(authToken: authToken, appCheckToken: appCheckToken)
    }

    func listenForAuthTokenChanges(_ listener: @escaping @DatabaseActor (String?) -> Void) {
        guard let auth = auth else {
            return
        }

        let wrapper = FAuthStateListenerWrapper(listener: listener, auth: auth)
        authListeners.withLock({
            $0.append(wrapper)
        })
    }

    func listenForAppCheckTokenChanges(_ listener: @escaping @DatabaseActor (String) -> Void) {
        guard let appCheck = appCheck else {
            return
        }
        let appCheckTokenKey = appCheck.notificationTokenKey
        // swift-corelibs-foundation never matches an `object:` filter that is a
        // pure Swift class, so filter by identity in the block instead.
        let sender = ObjectIdentifier(appCheck as AnyObject)
        let observer = NotificationCenter.default
            .addObserver(forName: appCheck.tokenDidChangeNotificationName,
                         object: nil,
                         queue: nil) { notification in
                guard let object = notification.object,
                      ObjectIdentifier(object as AnyObject) == sender,
                      let appCheckToken = notification.userInfo?[appCheckTokenKey] as? String else {
                    return
                }
                Task { @DatabaseActor in
                    listener(appCheckToken)
                }
            }
        let sendableObserver = SendableObserver(observer: observer)
        self.appCheckNotificationObservers.withLock {
            $0.append(sendableObserver)
        }
    }

    class func contextProvider(auth: AuthInterop?, appCheck: DatabaseAppCheckInterop?) -> DatabaseConnectionContextProviderProtocol {
        DatabaseConnectionContextProvider(auth: auth, appCheck: appCheck)
    }
}
