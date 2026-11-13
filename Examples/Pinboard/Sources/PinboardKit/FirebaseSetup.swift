// Copyright 2026 Google LLC
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

import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Configures Firebase before the window opens.
///
/// - With `PINBOARD_EMULATORS` set (to `1`, or to the emulators' host), the app
///   uses the `demo-pinboard` project on the Firebase emulators: no Firebase
///   project needed. The ports are the ones in `firebase.json`.
/// - Otherwise, the app's options come from `FIREBASE_OPTIONS` (the options as
///   JSON, or a file's path), as `FirebaseApp.configure()` reads them.
package enum FirebaseSetup {
    package static func configure() {
        let environment = ProcessInfo.processInfo.environment
        guard let emulators = environment["PINBOARD_EMULATORS"] else {
            guard environment["FIREBASE_OPTIONS"] != nil else {
                print("""
                Set FIREBASE_OPTIONS to your app's options (JSON, or a file's path),
                or PINBOARD_EMULATORS=1 to use the Firebase emulators. See README.md.
                """)
                exit(1)
            }
            FirebaseApp.configure()
            return
        }

        var options = FirebaseOptions(googleAppID: "1:123456789012:web:0123456789abcdef",
                                      gcmSenderID: "123456789012")
        options.projectID = "demo-pinboard"
        options.apiKey = "demo-api-key"
        options.databaseURL = "https://demo-pinboard-default-rtdb.firebaseio.com"
        options.storageBucket = "demo-pinboard.appspot.com"
        FirebaseApp.configure(options: options)

        let host = emulators == "1" ? "127.0.0.1" : emulators
        Auth.auth().useEmulator(withHost: host, port: 9099)
        let firestore = Firestore.firestore()
        firestore.useEmulator(withHost: host, port: 8080)
        // The emulator doesn't use TLS (as upstream, `useEmulator` only sets
        // the host), and it starts empty, so don't keep a cache between runs.
        let settings = firestore.settings
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        Database.database().useEmulator(withHost: host, port: 9000)
        Storage.storage().useEmulator(withHost: host, port: 9199)
        Functions.functions().useEmulator(withHost: host, port: 5001)
        if !["127.0.0.1", "localhost", "::1"].contains(host) {
            // Emulators on another machine (or from a container) are reached
            // over plain HTTP, where Storage and Functions don't send tokens
            // unless told to, as upstream.
            Storage.storage().allowInsecureTokenAttachment = true
            Functions.functions().allowInsecureTokenAttachment = true
        }
    }
}
