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

import Foundation

/// Implement StorageTasks that are not directly exposed via the public API.
@StorageActor
final class StorageInternalTask {
    private var fetcher: GTMSessionFetcher?
    private var base: StorageBase<Data>
    
    init(reference: StorageReference) {
        self.base = StorageBase(reference: reference)
    }
            
    func start(
        request: URLRequest? = nil,
        httpMethod: String,
        fetcherComment: String
    ) async throws -> Data {
    // Prepare a task and begins execution.
        let reference = base.reference
        let baseRequest = base.baseRequest
        base.state = .queueing
        let fetcherService = await StorageFetcherService.shared.service(reference.storage)
        var request = request ?? baseRequest
        request.httpMethod = httpMethod
        request.timeoutInterval = reference.storage.maxOperationRetryTime

        let fetcher = fetcherService.fetcher(with: request)
        fetcher.comment = fetcherComment
        self.fetcher = fetcher
        do {
          let data = try await fetcher.beginFetch()
            return data
        } catch {
            throw StorageErrorCode.error(withServerError: error as NSError,
                                                    ref: reference)
        }
      }

  deinit {
      self.fetcher?.stopFetching()
  }
}
