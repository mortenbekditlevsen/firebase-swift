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

public struct DatabaseConfig: Sendable {
    let sessionIdentifier: String
    let googleAppID: String

    let contextProvider: DatabaseConnectionContextProviderProtocol

    init(sessionIdentifier: String, googleAppID: String, contextProvider: DatabaseConnectionContextProviderProtocol) {
        self.sessionIdentifier = sessionIdentifier
        self.googleAppID = googleAppID
        self.contextProvider = contextProvider
        self.persistenceCacheSizeBytes = 10 * 1024 * 1024 // Default cache size is 10MB
        self.persistenceEnabled = false
    }

    private var isFrozen: Bool = false

    private func assertUnfrozen() {
        guard !isFrozen else {
            fatalError("Can't modify config objects after they are in use for FIRDatabaseReferences.")
        }
    }

    mutating func freeze() {
        isFrozen = true
    }

    var forceStorageEngine: FStorageEngine? { nil }

    /**
     * By default the Firebase Database client will keep data in memory while your
     * application is running, but not when it is restarted. By setting this value
     * to YES, the data will be persisted to on-device (disk) storage and will thus
     * be available again when the app is restarted (even when there is no network
     * connectivity at that time). Note that this property must be set before
     * creating your first FIRDatabaseReference and only needs to be called once per
     * application.
     *
     * If your app uses Firebase Authentication, the client will automatically
     * persist the user's authentication token across restarts, even without
     * persistence enabled. But if the auth token expired while offline and you've
     * enabled persistence, the client will pause write operations until you
     * successfully re-authenticate (or explicitly unauthenticate) to prevent your
     * writes from being sent unauthenticated and failing due to security rules.
     */
    public var persistenceEnabled: Bool {
        willSet {
            assertUnfrozen()
        }
    }

    /**
     * By default the Firebase Database client will use up to 10MB of disk space to
     * cache data. If the cache grows beyond this size, the client will start
     * removing data that hasn't been recently used. If you find that your
     * application caches too little or too much data, call this method to change
     * the cache size. This property must be set before creating your first
     * FIRDatabaseReference and only needs to be called once per application.
     *
     * Note that the specified cache size is only an approximation and the size on
     * disk may temporarily exceed it at times.
     */

    public var persistenceCacheSizeBytes: Int {
        willSet {
            assertUnfrozen()
            // Can't be less than 1MB
            if newValue < 1024 * 1024 {
                fatalError("The minimum cache size must be at least 1MB")
            }
            if newValue > 100 * 1024 * 1024 {
                fatalError("Firebase Database currently doesn't support a cache size larger than 100MB")
            }
        }
    }
}
