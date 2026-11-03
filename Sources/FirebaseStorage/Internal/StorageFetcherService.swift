// Copyright 2024 Google LLC
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

/// Manage Storage's fetcherService
actor StorageFetcherService {
  static let shared = StorageFetcherService()

  private var _fetcherService: GTMSessionFetcherService?

  func service(_ storage: Storage) async -> GTMSessionFetcherService {
    if let _fetcherService {
      return _fetcherService
    }
    let app = storage.app
    if let fetcherService = getFromMap(app: app, bucket: storage.storageBucket) {
      return fetcherService
    } else {
      let fetcherService = GTMSessionFetcherService()
      fetcherService.isRetryEnabled = true
      fetcherService.retryBlock = retryWhenOffline
      fetcherService.allowLocalhostRequest = true
      fetcherService.maxRetryInterval = storage.maxOperationRetryInterval
      fetcherService.testBlock = testBlock
      let authorizer = StorageTokenAuthorizer(
        googleAppID: app.options.googleAppID,
        authProvider: storage.auth,
        appCheck: storage.appCheck,
        allowInsecureTokenAttachment: { [weak storage] in
          storage?.allowsInsecureTokenAttachment ?? false
        }
      )
      fetcherService.authorizer = authorizer
      if storage.usesEmulator {
        fetcherService.allowLocalhostRequest = true
        fetcherService.allowedInsecureSchemes = ["http"]
      }
      setMap(app: app, bucket: storage.storageBucket, fetcher: fetcherService)
      return fetcherService
    }
  }

  /// Update the testBlock for unit testing. Save it as a property since this may be called before
  /// fetcherService is initialized.
  func updateTestBlock(_ block: GTMSessionFetcherTestBlock?) {
    testBlock = block
    if let _fetcherService {
      _fetcherService.testBlock = testBlock
    }
    for bucketMap in fetcherServiceMap.values {
      for fetcherService in bucketMap.services.values {
        fetcherService.testBlock = testBlock
      }
    }
  }

  private var testBlock: GTMSessionFetcherTestBlock?

  private var retryWhenOffline: GTMSessionFetcherRetryBlock = {
    (suggestedWillRetry: Bool,
     error: Error?,
     response: @escaping GTMSessionFetcherRetryResponse) in
    var shouldRetry = suggestedWillRetry
    // GTMSessionFetcher does not consider being offline a retryable error, but we do, so we
    // special-case it here.
    if !shouldRetry, error != nil {
      shouldRetry = (error as? NSError)?.code == URLError.notConnectedToInternet.rawValue
    }
    response(shouldRetry)
  }

  /// Map of apps to a dictionary of buckets to GTMSessionFetcherService. Upstream keys it by app
  /// name; here it's the app itself, so an app deleted and configured again under the same name,
  /// or another app with the same name, doesn't get this app's services (and its credentials).
  private var fetcherServiceMap: [ObjectIdentifier: AppServices] = [:]

  private struct AppServices {
    /// Weak, so that a later app at the same address isn't taken for this one.
    weak var app: FirebaseApp?
    var services: [String: GTMSessionFetcherService] = [:]
  }

  private func getFromMap(app: FirebaseApp, bucket: String) -> GTMSessionFetcherService? {
    guard let entry = fetcherServiceMap[ObjectIdentifier(app)], entry.app === app else {
      return nil
    }
    return entry.services[bucket]
  }

  private func setMap(app: FirebaseApp, bucket: String, fetcher: GTMSessionFetcherService) {
    fetcherServiceMap = fetcherServiceMap.filter { $0.value.app != nil }
    var entry = fetcherServiceMap[ObjectIdentifier(app)]
    if entry?.app !== app {
      entry = AppServices(app: app)
    }
    entry?.services[bucket] = fetcher
    fetcherServiceMap[ObjectIdentifier(app)] = entry
  }
}
