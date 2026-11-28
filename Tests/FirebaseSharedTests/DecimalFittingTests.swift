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

import FirebaseShared
import Foundation
import Testing

@Suite struct DecimalFittingTests {
  @Test(arguments: [0, 1.5, -2.25, 1e100, -1e-100, Double(Int64.max)])
  func numbersInRangeConvert(_ value: Double) {
    #expect(Decimal(fitting: value) == Decimal(value))
  }

  @Test(arguments: [Double.infinity, -.infinity, 1e300, -1e300, 1e-300, .greatestFiniteMagnitude])
  func numbersOutOfRangeDont(_ value: Double) {
    #expect(Decimal(fitting: value) == nil)
  }

  @Test func nanStaysNaN() {
    #expect(Decimal(fitting: .nan)?.isNaN == true)
  }

  /// The old and new decoders share the check.
  @Test func firebaseDataDecoderThrowsForNumbersThatDontFit() throws {
    #expect(try FirebaseDataDecoder().decode(Decimal.self, from: 1.5) == Decimal(1.5))
    for value in [Double.infinity, 1e300] {
      #expect {
        try FirebaseDataDecoder().decode(Decimal.self, from: value)
      } throws: { error in
        guard case .dataCorrupted = error as? DecodingError else { return false }
        return true
      }
    }
  }
}
