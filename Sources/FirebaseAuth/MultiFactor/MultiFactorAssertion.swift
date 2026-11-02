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

/// Asserts ownership of a second factor, like `AuthCredential` does for a first factor.
public class MultiFactorAssertion: @unchecked Sendable {
  /// The second factor identifier for this opaque object asserting a second factor.
  public let factorID: String

  init(factorID: String) {
    self.factorID = factorID
  }
}
