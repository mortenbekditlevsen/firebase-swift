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

package extension Decimal {
  /// The `Decimal` nearest `value`, or nil where it has none: for an infinity,
  /// for which `Decimal(_: Double)` traps, and for a number too large or too
  /// small, for which it returns NaN. A NaN stays NaN.
  init?(fitting value: Double) {
    if value.isNaN {
      self = .nan
      return
    }
    guard value.isFinite else { return nil }
    let decimal = Decimal(value)
    guard !decimal.isNaN else { return nil }
    self = decimal
  }
}
