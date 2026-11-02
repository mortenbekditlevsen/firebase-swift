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

/// Creates assertions for phone second factors.
public enum PhoneMultiFactorGenerator {
  /// The assertion that confirms ownership of a phone second factor, for both enrolling it and
  /// signing in with it. Get the credential from `PhoneAuthProvider` (iOS only).
  public static func assertion(with phoneAuthCredential: PhoneAuthCredential)
    -> MultiFactorAssertion {
    PhoneMultiFactorAssertion(authCredential: phoneAuthCredential)
  }
}
