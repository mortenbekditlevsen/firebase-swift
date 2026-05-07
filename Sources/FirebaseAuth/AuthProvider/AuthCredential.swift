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

/**
    @brief Public representation of a credential.
 */
public protocol AuthCredential: Sendable {
    var provider: String { get }
    func prepare(_ request: inout VerifyAssertionRequest)
}
extension AuthCredential {
    public func prepare(_ request: inout VerifyAssertionRequest) {
        fatalError("This method must be overridden by a subclass.")
    }
}
//@available(iOS 13, tvOS 13, macOS 15.0, macCatalyst 13, watchOS 7, *)
// open class AuthCredential {
//  public let provider: String
//  init(provider: String) {
//    self.provider = provider
//  }
//
//  // TODO: remove public after FIRUser port
//   public func prepare(_ request: VerifyAssertionRequest) {
//    fatalError("This method must be overridden by a subclass.")
//  }
//}
