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

import Foundation


struct VerifyClientResponse: AuthRPCResponse {
  /// Receipt that the APNS token was successfully validated with APNS.
  let receipt: String?

  /// How long to wait for the silent push notification. The port decoded a
  /// `suggestedTimeOutDate` date, which the backend never sends.
  let suggestedTimeout: TimeInterval?

  private enum CodingKeys: String, CodingKey {
    case receipt
    case suggestedTimeout
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    receipt = try container.decodeIfPresent(String.self, forKey: .receipt)
    // A string-encoded number of seconds.
    suggestedTimeout = try container.decodeIfPresent(String.self, forKey: .suggestedTimeout)
      .flatMap(TimeInterval.init)
  }
}
