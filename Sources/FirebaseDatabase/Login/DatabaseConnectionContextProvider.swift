//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 12/04/2022.
//

import Foundation
import FirebaseCore

class DatabaseConnectionContext {
    /// Auth token if available.
    var authToken: String?

    /// App check token if available.
    var appCheckToken: String?

    init(authToken: String?, appCheckToken: String?) {
        self.authToken = authToken
        self.appCheckToken = appCheckToken
    }
}

protocol DatabaseConnectionContextProviderProtocol {
    func fetchContextForcingRefresh(_ forceRefresh: Bool) async throws -> DatabaseConnectionContext

    /// Adds a listener to the Auth token updates.
    /// @param listener A block that will be invoked each time the Auth token is
    /// updated.
    func listenForAuthTokenChanges(_ listener:  @escaping (String) -> Void)

    /// Adds a listener to the FAC token updates.
    /// @param listener A block that will be invoked each time the FAC token is
    /// updated.
    func listenForAppCheckTokenChanges(_ listener: @escaping (String) -> Void)
}

extension Notification.Name {
    public static let FIRAuthStateDidChangeInternalNotification = Notification.Name("FIRAuthStateDidChangeInternalNotification")
}

let FIRAuthStateDidChangeInternalNotificationTokenKey = "FIRAuthStateDidChangeInternalNotificationTokenKey"

private class FAuthStateListenerWrapper {
    private let listener: (String) -> Void
    private weak var auth: AuthInterop?
    private let queue: DispatchQueue

    init(listener: @escaping (String) -> Void, auth: AuthInterop, queue: DispatchQueue) {
        self.listener = listener
        self.auth = auth
        self.queue = queue
        NotificationCenter.default.addObserver(forName: .FIRAuthStateDidChangeInternalNotification, object: nil, queue: nil) { [weak self] notification in
            let userInfo = notification.userInfo
            guard (notification.object as? AnyObject) === self?.auth else { return }
            guard let token = userInfo?[FIRAuthStateDidChangeInternalNotificationTokenKey] as? String else { return }
            queue.async {
                self?.listener(token)
            }
        }
//        NotificationCenter
//            .default
//            .addObserver(self,
//                         selector: #selector(authStateDidChangeNotification),
//                         name: .FIRAuthStateDidChangeInternalNotification,
//                         object: nil)
    }

//    func authStateDidChangeNotification(_ notification: Notification) {
//        let userInfo = notification.userInfo
//        guard (notification.object as? AnyObject) === self.auth else { return }
//        guard let token = userInfo?[FIRAuthStateDidChangeInternalNotificationTokenKey] as? String else { return }
//        queue.async {
//            self.listener(token)
//        }
//    }
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

protocol DatabaseAppCheckInterop {
    func getTokenForcingRefresh(_ forceRefresh: Bool) async throws -> String
    var notificationTokenKey: String { get }
    var tokenDidChangeNotificationName: Notification.Name { get }
}

// TODO: Make FIRAppCheckInterop conform to FIRDatabaseAppCheckInterop
// TODO: Make FIRAppCheckTokenResultInterop conform to FIRDatabaseAppCheckTokenResultInterop
// TODO: Make FIRAuthInterop conform to FIRDatabaseAuthInterop

class DatabaseConnectionContextProvider: DatabaseConnectionContextProviderProtocol {

    var appCheck: DatabaseAppCheckInterop? // FIRAppCheckInterop
    var auth: AuthInterop? // FIRAuthInterop

    /// Strong references to the auth listeners as they are only weak in
    /// FIRFirebaseApp.
    private var authListeners: [FAuthStateListenerWrapper] = []

    /// Observer objects returned by
    /// `-[NSNotificationCenter addObserverForName:object:queue:usingBlock:]`
    /// method. Required to cleanup the observers on dealloc.
    var appCheckNotificationObservers: [Any] = []

    /// An NSOperationQueue to call listeners on.
    var listenerQueue: OperationQueue

    private let dispatchQueue: DispatchQueue

    private init(auth: AuthInterop?,
                 appCheck: DatabaseAppCheckInterop?,
                 dispatchQueue: DispatchQueue) {
        self.appCheck = appCheck
        self.auth = auth
        self.dispatchQueue = dispatchQueue
        self.listenerQueue = OperationQueue()
        self.listenerQueue.underlyingQueue = dispatchQueue
    }

    var lock = NSLock()

    deinit {
        // NOTE: Using an NSLock is a replacement for objc @synchronized
        // Perhaps switch to a non-NS-prefixed alternative later
        lock.lock()
        defer { lock.unlock() }
        for observer in self.appCheckNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
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

    func listenForAuthTokenChanges(_ listener: @escaping (String) -> Void) {
        guard let auth = auth else {
            return
        }

        let wrapper = FAuthStateListenerWrapper(listener: listener, auth: auth, queue: dispatchQueue)
        authListeners.append(wrapper)
    }

    func listenForAppCheckTokenChanges(_ listener: @escaping (String) -> Void) {
        guard let appCheck = appCheck else {
            return
        }
        let appCheckTokenKey = appCheck.notificationTokenKey
        let observer = NotificationCenter.default
            .addObserver(forName: appCheck.tokenDidChangeNotificationName,
                         object: appCheck,
                         queue: listenerQueue) { notification in
                guard let appCheckToken = notification.userInfo?[appCheckTokenKey] as? String else {
                    return
                }
                listener(appCheckToken)
            }

        // NOTE: Using an NSLock is a replacement for objc @synchronized
        // Perhaps switch to a non-NS-prefixed alternative later
        lock.lock()
        defer { lock.unlock() }
        self.appCheckNotificationObservers.append(observer)
    }

    class func contextProvider(auth: AuthInterop?, appCheck: DatabaseAppCheckInterop?, dispatchQueue: DispatchQueue) -> DatabaseConnectionContextProviderProtocol {
        DatabaseConnectionContextProvider(auth: auth, appCheck: appCheck, dispatchQueue: dispatchQueue)
    }
}
