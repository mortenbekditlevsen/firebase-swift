//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 12/04/2022.
//

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
    /// updated.
    func listenForAuthTokenChanges(_ listener:  @escaping @DatabaseActor (String) -> Void)

    /// Adds a listener to the FAC token updates.
    /// @param listener A block that will be invoked each time the FAC token is
    /// updated.
    func listenForAppCheckTokenChanges(_ listener: @escaping @DatabaseActor (String) -> Void)
}

extension Notification.Name {
    public static let FIRAuthStateDidChangeInternalNotification = Notification.Name("FIRAuthStateDidChangeInternalNotification")
}

let FIRAuthStateDidChangeInternalNotificationTokenKey = "FIRAuthStateDidChangeInternalNotificationTokenKey"

private final class FAuthStateListenerWrapper: @unchecked Sendable {
    private let listener: @DatabaseActor (String) -> Void
    private weak var auth: AuthInterop?

    init(listener: @escaping @DatabaseActor (String) -> Void, auth: AuthInterop) {
        self.listener = listener
        self.auth = auth
        NotificationCenter.default.addObserver(forName: .FIRAuthStateDidChangeInternalNotification, object: nil, queue: nil) { [weak self] notification in
            let userInfo = notification.userInfo
            guard (notification.object as? AnyObject) === self?.auth else { return }
            guard let token = userInfo?[FIRAuthStateDidChangeInternalNotificationTokenKey] as? String else { return }
            Task { @DatabaseActor in
                self?.listener(token)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    func listenForAuthTokenChanges(_ listener: @escaping @DatabaseActor (String) -> Void) {
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
        let observer = NotificationCenter.default
            .addObserver(forName: appCheck.tokenDidChangeNotificationName,
                         object: appCheck,
                         queue: nil) { notification in
                guard let appCheckToken = notification.userInfo?[appCheckTokenKey] as? String else {
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
