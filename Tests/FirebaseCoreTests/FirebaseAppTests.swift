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

import FirebaseCore
import Foundation
import Synchronization
import Testing

/// The registry of named apps, and the SDKs' per-app components. The default app is left alone:
/// other test targets share this process on macOS and may configure it.
struct FirebaseAppTests {
  private let options = FirebaseOptions(googleAppID: "1:123:ios:abc", gcmSenderID: "123")

  @Test func namedAppsAreRegistered() async throws {
    let name = "app-\(UUID().uuidString)"
    FirebaseApp.configure(name: name, options: options)
    let app = try #require(FirebaseApp.app(name: name))
    #expect(app.name == name)
    #expect(app.options == options)
    #expect(app.isDefaultApp == false)
    #expect(FirebaseApp.app(name: name) === app)
    #expect(FirebaseApp.allApps?[name] === app)

    #expect(await app.delete())
    #expect(FirebaseApp.app(name: name) == nil)
    #expect(FirebaseApp.allApps?[name] == nil)
    #expect(await app.delete() == false)

    // The name can be used again, for a new app.
    FirebaseApp.configure(name: name, options: options)
    let again = try #require(FirebaseApp.app(name: name))
    #expect(again !== app)
    #expect(again != app)
    #expect(await again.delete())
  }

  @Test func appsOutsideTheRegistryCannotBeDeleted() async {
    let app = FirebaseApp(options: options, name: "unregistered")
    #expect(FirebaseApp.app(name: "unregistered") == nil)
    #expect(await app.delete() == false)
  }

  @Test func theOptionsCannotBeChangedThroughTheApp() throws {
    let name = "app-\(UUID().uuidString)"
    FirebaseApp.configure(name: name, options: options)
    let app = try #require(FirebaseApp.app(name: name))
    var copy = app.options
    copy.projectID = "changed"
    #expect(app.options.projectID == nil)
  }

  @Test func componentsAreCreatedOncePerApp() async throws {
    let name = "app-\(UUID().uuidString)"
    FirebaseApp.configure(name: name, options: options)
    let app = try #require(FirebaseApp.app(name: name))
    let component = app.component(TestComponent.self)
    #expect(app.component(TestComponent.self) === component)
    #expect(FirebaseApp(options: options, name: "other").component(TestComponent.self)
      !== component)

    #expect(await app.delete())
    #expect(component.deletedApps.withLock { $0 } == [name])
  }

  @Test func theVersionIsTheUpstreamRelease() {
    let parts = FirebaseVersion().split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
  }
}

private final class TestComponent: FirebaseAppComponent {
  let deletedApps = Mutex<[String]>([])

  init() {}

  func appWillBeDeleted(_ app: FirebaseApp) async {
    deletedApps.withLock { $0.append(app.name) }
  }
}
