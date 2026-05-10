//
//  File.swift
//  
//
//  Created by Morten Bek Ditlevsen on 24/04/2022.
//

import Foundation
import Synchronization

class FRepoManager {
    private static let configs: Mutex<[String: [FRepoInfo: FRepo]]> = Mutex([:])

    /**
     * Used for legacy unit tests.  The public API should go through
     * FirebaseDatabase which calls createRepo.
     */

    class func getRepo(_ repoInfo: FRepoInfo, config: DatabaseConfig) -> FRepo {
        let repos = configs.withLock {
            $0[config.sessionIdentifier]
        }
        if let repo = repos?[repoInfo] {
            return repo
        } else {
            // Calling this should create the repo.
            let (_, repo) = Database.createDatabaseForTests(repoInfo, config: config)
            return repo
        }
    }

    class func createRepo(_ repoInfo: FRepoInfo, config: inout DatabaseConfig, database: Database) -> FRepo {
        config.freeze()
        let sessionIdentifier = config.sessionIdentifier
        let repo = FRepo(repoInfo: repoInfo, config: config, database: database)

        configs.withLock {
            var repos = $0[sessionIdentifier, default: [:]]
            if repos[repoInfo] != nil {
                fatalError("createRepo called for Repo that already exists.")
            } else {
                repos[repoInfo] = repo
                $0[sessionIdentifier] = repos
            }
        }
        return repo
    }

    class func interruptAll() {
        // was: DatabaseQuery.sharedQueue.async {
        Task { @DatabaseActor in
            let configValues = configs.withLock { $0.values }
            for repos in configValues {
                for repo in repos.values {
                    repo.interrupt()
                }
            }
        }
    }
    
    class func interrupt(_ config: DatabaseConfig) {
        let sessionIdentifier = config.sessionIdentifier
        // was: DatabaseQuery.sharedQueue.async {
        Task { @DatabaseActor in
            let repos = configs.withLock { $0[sessionIdentifier] }
            guard let repos else { return }
            for repo in repos.values {
                repo.interrupt()
            }
        }
    }
    class func resumeAll() {
        // was: DatabaseQuery.sharedQueue.async {
        Task { @DatabaseActor in
            let configValues = configs.withLock { $0.values }
            for repos in configValues {
                for repo in repos.values {
                    repo.resume()
                }
            }
        }

    }
    class func resume(_ config: DatabaseConfig) {
        let sessionIdentifier = config.sessionIdentifier
        // was: DatabaseQuery.sharedQueue.async {
        Task { @DatabaseActor in
            let repos = configs.withLock { $0[sessionIdentifier] }
            guard let repos else { return }
            for repo in repos.values {
                repo.resume()
            }
        }
    }
    class func disposeRepos(_ config: DatabaseConfig) {
        // Do this synchronously to make sure we release our references to LevelDB
        // before returning, allowing LevelDB to close and release its exclusive
        // locks.
        let sessionIdentifier = config.sessionIdentifier
        // was: DatabaseQuery.sharedQueue.async {
        Task { @DatabaseActor in
            FFLog("I-RDB040001", "Disposing all repos for Config with name \(config.sessionIdentifier)")
            let repos = configs.withLock { $0[sessionIdentifier] }
            guard let repos else { return }
            for repo in repos.values {
                repo.dispose()
            }
            configs.withLock {
                _ = $0.removeValue(forKey: sessionIdentifier)
            }
        }
    }
}
