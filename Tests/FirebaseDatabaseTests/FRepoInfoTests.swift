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

@testable import FirebaseDatabase
import Foundation
import Testing

struct FRepoInfoTests {
  @Test(arguments: [
    "s-usc1a-nss-2001.firebaseio.com",
    "my-project-default-rtdb.firebaseio.com",
    "localhost:9000",
    "127.0.0.1:9000",
  ])
  func acceptsServerAndEmulatorHosts(host: String) {
    #expect(FRepoInfo.isValidHost(host))
  }

  @Test(arguments: [
    "",
    "evil host.com",
    "a/b.com",
    "host_name.com",
    "[::1]:9000",
    "host.com:",
    "host.com:123456",
    "host.com:12a",
    "host.com\n",
    "hôst.com",
    String(repeating: "a", count: 254),
  ])
  func rejectsHostsThatCantBeUsedInAURL(host: String) {
    #expect(!FRepoInfo.isValidHost(host))
  }

  @Test func invalidServerHostsAreIgnored() {
    let host = "test-\(UUID().uuidString.lowercased()).firebaseio.com"
    defer { UserDefaults.standard.removeObject(forKey: "firebase:host:\(host)") }
    var info = FRepoInfo(host: host, isSecure: true, withNamespace: "test")

    info.internalHost = "s-usc1a-nss-2001.firebaseio.com"
    #expect(info.internalHost == "s-usc1a-nss-2001.firebaseio.com")
    info.internalHost = "not a host"
    #expect(info.internalHost == "s-usc1a-nss-2001.firebaseio.com")
    #expect(UserDefaults.standard.string(forKey: "firebase:host:\(host)")
      == "s-usc1a-nss-2001.firebaseio.com")
  }

  @Test func anInvalidSavedHostIsDiscarded() {
    // Earlier versions saved any host the server sent.
    let host = "test-\(UUID().uuidString.lowercased()).firebaseio.com"
    let key = "firebase:host:\(host)"
    defer { UserDefaults.standard.removeObject(forKey: key) }
    UserDefaults.standard.set("bad host", forKey: key)

    let info = FRepoInfo(host: host, isSecure: true, withNamespace: "test")
    #expect(info.internalHost == host)
    #expect(UserDefaults.standard.string(forKey: key) == nil)
  }

  @Test func clearingTheCacheAcceptsTheConfiguredHost() {
    // An IPv6 emulator host fails isValidHost, but is the configured host.
    var info = FRepoInfo(host: "[::1]:9000", isSecure: false, withNamespace: "test")
    info.clearInternalHostCache()
    #expect(info.internalHost == "[::1]:9000")
  }
}
