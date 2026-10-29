// Copyright 2022 Google LLC
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import FirebaseCore


struct StorageTokenAuthorizer {
    func authorizeRequest(_ request: inout URLRequest) async throws {
        // Set version header on each request
        let versionString = "ios/\(FirebaseVersion())"
        request.setValue(versionString, forHTTPHeaderField: "x-firebase-storage-version")
        
        // Set GMP ID on each request
        request.setValue(googleAppID, forHTTPHeaderField: "x-firebase-gmpid")
        
        // Fetch both tokens concurrently, then set the headers, as upstream does:
        // the Auth token goes in `Authorization`, the App Check token in its own header.
        let auth = auth
        async let authToken: Result<String?, StorageError> = {
            guard let auth else { return .success(nil) }
            do {
                return .success(try await auth.getToken(forcingRefresh: false))
            } catch {
                let error = error as NSError
                var errorDictionary = error.userInfo
                errorDictionary["ResponseErrorDomain"] = error.domain
                errorDictionary["ResponseErrorCode"] = error.code
                return .failure(StorageError.unauthenticated(serverError: errorDictionary))
            }
        }()

        let appCheck = appCheck
        async let appCheckToken: String? = {
            guard let appCheck else { return nil }
            do {
                return try await appCheck.getToken(forcingRefresh: false)
            } catch {
                print("[FirebaseStorage][I-STR000001] Failed to fetch AppCheck token. Error: \(error)")
                return nil
            }
        }()

        if let token = try await authToken.get() {
            request.setValue("Firebase \(token)", forHTTPHeaderField: "Authorization")
        }
        if let token = await appCheckToken {
            request.setValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
  }

  // Note that stopAuthorization, isAuthorizingRequest, and userEmail
  // aren't relevant with the Firebase App/Auth implementation of tokens,
  // and thus aren't implemented. Token refresh is handled transparently
  // for us, and we don't allow the auth request to be stopped.
  // Auth is also not required so the world doesn't stop.
  func stopAuthorization() {}

  func stopAuthorization(for request: URLRequest) {}

  func isAuthorizingRequest(_ request: URLRequest) -> Bool {
    return false
  }

  func isAuthorizedRequest(_ request: URLRequest) -> Bool {
    guard let authHeader = request.allHTTPHeaderFields?["Authorization"] else {
      return false
    }
    return authHeader.hasPrefix("Firebase")
  }

  var userEmail: String?

  private let googleAppID: String
  private let auth: AuthInterop?
  private let appCheck: AppCheckInterop?

  private let serialAuthArgsQueue = DispatchQueue(label: "com.google.firebasestorage.authorizer")

  init(googleAppID: String,
       authProvider: AuthInterop?,
       appCheck: AppCheckInterop?) {
    self.googleAppID = googleAppID
    auth = authProvider
    self.appCheck = appCheck
  }
}
