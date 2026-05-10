//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 09/05/2022.
//

import Foundation
import FirebaseCore

/// This protocol is used in the interop registration process to register an
/// instance provider for individual FIRApps.
protocol DatabaseProvider {
    /// Gets a FirebaseDatabase instance for the specified URL, using the specified
    /// FirebaseApp.
    func databaseForApp(_ app: FirebaseApp, URL url: String) -> Database
}

/// A concrete implementation for FIRDatabaseProvider to create Database
/// instances.

class DatabaseComponent: DatabaseProvider {
    var lock: NSLock = NSLock()
    internal init(app: FirebaseApp) {
        self.app = app
    }

    func databaseForApp(_ app: FirebaseApp, URL url: String) -> Database {
        guard let databaseUrl = URL(string: url) else {
            fatalError("The Database URL '\(url)' cannot be parsed. Specify a valid DatabaseURL within FIRApp or from your databaseForApp:URL: call.")
        }
        guard databaseUrl.path == "" || databaseUrl.path == "/" else {
            fatalError("Configured Database URL '\(databaseUrl)' is invalid. It should point to the root of a Firebase Database but it includes a path: \(databaseUrl.path)")
        }
        // NOTE: Using an NSLock is a replacement for objc @synchronized
        // Perhaps switch to a non-NS-prefixed alternative later
        lock.lock()
        defer { lock.unlock() }

        let parsedUrl = FUtilities.parseUrl(databaseUrl.absoluteString)
        let urlIndex = "\(parsedUrl.repoInfo.host):\(parsedUrl.path)"
        if let database = instances[urlIndex] {
            return database
        }
        // XXX TODO: Inject auth and app check interop
        let contextProvider = DatabaseConnectionContextProvider.contextProvider(auth: app.auth, appCheck: nil)

        // If this is the default app, don't set the session persistence key
        // so that we use our default ("default") instead of the FIRApp
        // default ("[DEFAULT]") so that we preserve the default location
        // used by the legacy Firebase SDK.
        var sessionIdentifier = "default"
        if !FirebaseApp.isDefaultAppConfigured || app != FirebaseApp.defaultApp {
            sessionIdentifier = app.name
        }
        let config = DatabaseConfig(sessionIdentifier: sessionIdentifier,
                                    googleAppID: app.options.googleAppID,
                                    contextProvider: contextProvider)
        let database = Database(app: app, repoInfo: parsedUrl.repoInfo, config: config)
        instances[urlIndex] = database
        return database
    }

    // MARK: - Instance management.
    func appWillBeDeleted(_ app: FirebaseApp) {
        // NOTE: Using an NSLock is a replacement for objc @synchronized
        // Perhaps switch to a non-NS-prefixed alternative later
        lock.lock()
        defer { lock.unlock() }
        // Clean up the deleted instance in an effort to remove any resources
        // still in use. Note: Any leftover instances of this exact database
        // will be invalid.
        for database in instances.values {
            FRepoManager.disposeRepos(database.config)
        }
        instances.removeAll()
    }

    private var app: FirebaseApp
    private var instances: [String: Database] = [:]

    /*
     #pragma mark - Lifecycle

     + (void)load {
         [FIRApp registerInternalLibrary:(Class<FIRLibrary>)self
                                withName:@"fire-db"];
     }

     #pragma mark - FIRComponentRegistrant

     + (NSArray<FIRComponent *> *)componentsToRegister {
         FIRDependency *authDep =
             [FIRDependency dependencyWithProtocol:@protocol(FIRAuthInterop)
                                        isRequired:NO];
         FIRComponentCreationBlock creationBlock =
             ^id _Nullable(FIRComponentContainer *container, BOOL *isCacheable) {
             *isCacheable = YES;
             return [[FIRDatabaseComponent alloc] initWithApp:container.app];
         };
         FIRComponent *databaseProvider =
             [FIRComponent componentWithProtocol:@protocol(FIRDatabaseProvider)
                             instantiationTiming:FIRInstantiationTimingLazy
                                    dependencies:@[ authDep ]
                                   creationBlock:creationBlock];
         return @[ databaseProvider ];
     }
     ---
     
     @interface FIRAppCheckTokenResult () <FIRDatabaseAppCheckTokenResultInterop>
     @end


     */
}
