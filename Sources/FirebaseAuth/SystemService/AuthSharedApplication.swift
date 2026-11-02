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

#if os(iOS)
  import UIKit

  /// `UIApplication.shared`, looked up on the main actor when it's needed, so `Auth` can be
  /// created on any thread.
  struct AuthSharedApplication: AuthAPNSTokenApplication, AuthNotificationApplication {
    /// The shared application, through reflection as upstream does, to build in extensions.
    @MainActor private static var shared: UIApplication? {
      let selector = NSSelectorFromString("sharedApplication")
      guard UIApplication.responds(to: selector),
            let application = UIApplication.perform(selector)?.takeUnretainedValue() else {
        return nil
      }
      return application as? UIApplication
    }

    @MainActor func registerForRemoteNotifications() {
      Self.shared?.registerForRemoteNotifications()
    }

    @MainActor var delegate: UIApplicationDelegate? {
      Self.shared?.delegate
    }

    /// Only read when `delegate` isn't nil, so there is a shared application.
    @MainActor var applicationForDelegate: UIApplication {
      Self.shared!
    }
  }
#endif
