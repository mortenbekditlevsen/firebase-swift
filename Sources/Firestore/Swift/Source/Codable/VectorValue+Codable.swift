/*
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

/** The keys in a VectorValue. */
private enum VectorValueKeys: String, CodingKey {
  case array
}

/** Extends VectorValue to conform to Codable. */
extension VectorValue: Codable {
  public convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: VectorValueKeys.self)
    let data = try container.decode([Double].self, forKey: .array)
    let array = data.map { double in
      NSNumber(value: double)
    }
    self.init(__array: array)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: VectorValueKeys.self)
    try container.encode(self.array, forKey: .array)
  }
}
