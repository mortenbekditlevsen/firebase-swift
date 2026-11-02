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

/// A sign-in response that, for a user with a second factor, has no ID token but a pending
/// credential and the user's enrolled factors.
protocol AuthMFAResponse {
  /// Empty while a second factor is needed.
  var idToken: String { get }
  var mfaPendingCredential: String? { get }
  var mfaInfo: [AuthProtoMFAEnrollment]? { get }
}

extension VerifyPasswordResponse: AuthMFAResponse {}

extension EmailLinkSignInResponse: AuthMFAResponse {
  var mfaPendingCredential: String? { MFAPendingCredential }
  var mfaInfo: [AuthProtoMFAEnrollment]? { MFAInfo }
}

extension VerifyAssertionResponse: AuthMFAResponse {
  var mfaPendingCredential: String? { MFAPendingCredential }
  var mfaInfo: [AuthProtoMFAEnrollment]? { MFAInfo }
}
