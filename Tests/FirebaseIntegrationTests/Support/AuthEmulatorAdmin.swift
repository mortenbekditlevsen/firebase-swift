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
import FirebaseAuth
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

/// The Auth emulator's admin API, for changing users in ways the client SDK can't.
enum AuthEmulatorAdmin {
  /// Updates a user's account, as the Admin SDK's `updateUser` does.
  static func update(_ uid: String, with fields: [String: Any]) async throws {
    let address = try #require(Emulators.auth)
    let url = try #require(URL(string: "http://\(address.host):\(address.port)" +
        "/identitytoolkit.googleapis.com/v1/projects/\(Emulators.projectID)/accounts:update"))
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body = fields
    body["localId"] = uid
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode
    #expect(status == 200, "\(String(decoding: data, as: UTF8.self))")
  }

  /// Marks the user's email as verified, as enrolling a second factor requires.
  static func verifyEmail(of user: User) async throws {
    try await update(user.uid, with: ["emailVerified": true])
    _ = try await user.getIDToken(forcingRefresh: true)
  }

  /// Replaces the user's second factors with phone factors for `phoneNumbers`.
  static func enrollPhoneFactors(_ phoneNumbers: [String], for uid: String) async throws {
    let enrollments = phoneNumbers.enumerated().map { index, number in
      ["mfaEnrollmentId": "phone-\(index)", "phoneInfo": number, "displayName": "Phone \(index)"]
    }
    try await update(uid, with: ["mfa": ["enrollments": enrollments]])
  }
}
