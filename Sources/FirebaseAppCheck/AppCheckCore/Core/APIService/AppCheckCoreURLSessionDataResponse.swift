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

import Foundation
// firebase-swift: URL loading is in FoundationNetworking on Linux.
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The class represents HTTP response received from `URLSession`.
class AppCheckCoreURLSessionDataResponse: NSObject {
  let httpResponse: HTTPURLResponse
  let httpBody: Data?
  let requestDate: Date

  init(response: HTTPURLResponse, httpBody: Data?, requestDate: Date) {
    httpResponse = response
    self.httpBody = httpBody
    self.requestDate = requestDate
    super.init()
  }

  convenience init(response: HTTPURLResponse, httpBody: Data?) {
    self.init(response: response, httpBody: httpBody, requestDate: Date())
  }
}
