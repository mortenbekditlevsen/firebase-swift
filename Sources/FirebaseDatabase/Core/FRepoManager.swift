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
        for repos in configs.withLock({ Array($0.values) }) {
            for repo in repos.values {
                repo.enqueue { $0.interrupt() }
            }
        }
    }
    
    class func interrupt(_ config: DatabaseConfig) {
        let sessionIdentifier = config.sessionIdentifier
        for repo in configs.withLock({ $0[sessionIdentifier] })?.values ?? [:].values {
            repo.enqueue { $0.interrupt() }
        }
    }
    class func resumeAll() {
        for repos in configs.withLock({ Array($0.values) }) {
            for repo in repos.values {
                repo.enqueue { $0.resume() }
            }
        }

    }
    class func resume(_ config: DatabaseConfig) {
        let sessionIdentifier = config.sessionIdentifier
        for repo in configs.withLock({ $0[sessionIdentifier] })?.values ?? [:].values {
            repo.enqueue { $0.resume() }
        }
    }
    class func disposeRepos(_ config: DatabaseConfig) {
        // Do this synchronously to make sure we release our references to LevelDB
        // before returning, allowing LevelDB to close and release its exclusive
        // locks.
        let sessionIdentifier = config.sessionIdentifier
        FFLog("I-RDB040001", "Disposing all repos for Config with name \(config.sessionIdentifier)")
        let repos = configs.withLock { $0.removeValue(forKey: sessionIdentifier) }
        // After the repos' pending operations.
        for repo in repos?.values ?? [:].values {
            repo.enqueue { $0.dispose() }
        }
    }
}
