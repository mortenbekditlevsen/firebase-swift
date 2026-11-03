// Copyright 2023 Google LLC
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


import FirebaseCore
import Foundation
import Synchronization

/// Auth's state for an app: its one `Auth` instance, as upstream's `AuthComponent`.
@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
final class AuthComponent: FirebaseAppComponent {
  private let instance = Mutex<Auth?>(nil)

  init() {}

  func auth(app: FirebaseApp) -> Auth {
    instance.withLock { instance in
      if let instance {
        return instance
      }
      let auth = Auth(app: app, keychainStorageProvider: Auth.storageProvider)
      app.auth = auth
      instance = auth
      return auth
    }
  }

  func appWillBeDeleted(_ app: FirebaseApp) async {
    // This doesn't stop any request already issued, see b/27704535
    let serviceName = Auth.keychainServiceName(forAppName: app.name)
      ?? Auth.keychainServiceForAppID(app.options.googleAppID)
    Auth.deleteKeychainServiceNameForAppName(app.name)
    let keychain = Auth.storageProvider.init(service: serviceName)
    let userKey = "\(app.name)_firebase_user"
    try? keychain.removeData(forKey: userKey)
    DispatchQueue.main.async {
      // TODO(ObjC): Move over to fire an event instead, once ready.
      NotificationCenter.default.post(name: Auth.authStateDidChangeNotification, object: nil)
    }
  }
}
