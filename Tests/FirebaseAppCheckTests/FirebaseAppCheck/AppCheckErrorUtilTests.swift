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

// Port note: a port of upstream's FIRAppCheckErrorUtilTests.m.

@testable import FirebaseAppCheck
import XCTest

private let kTestErrorDomain = "com.google.test.error-domain"
private let kTestErrorCode = 42
private let kAppCheckCoreErrorDomain = "com.google.app_check_core"

final class AppCheckErrorUtilTests: XCTestCase {
  private var underlyingError: NSError!
  private var userInfo: [String: Any]!

  override func setUp() {
    super.setUp()
    underlyingError = NSError(domain: kTestErrorDomain, code: kTestErrorCode, userInfo: nil)
    userInfo = [
      NSUnderlyingErrorKey: underlyingError!,
      NSLocalizedFailureReasonErrorKey: "Sample Failure Reason",
    ]
  }

  func testPublicDomainErrorForPublicError() {
    let expectedError = NSError(domain: AppCheckErrorDomain,
                                code: AppCheckErrorCode.serverUnreachable.rawValue,
                                userInfo: userInfo)

    let publicError = AppCheckErrorUtil.publicDomainError(with: expectedError)

    XCTAssertEqual(expectedError, publicError)
  }

  func testPublicDomainErrorForGACErrorUnknown() {
    assertPublicDomainError(forCoreCode: .unknown, isPublicCode: .unknown)
  }

  func testPublicDomainErrorForGACErrorServerUnreachable() {
    assertPublicDomainError(forCoreCode: .serverUnreachable, isPublicCode: .serverUnreachable)
  }

  func testPublicDomainErrorForGACErrorInvalidConfiguration() {
    assertPublicDomainError(forCoreCode: .invalidConfiguration,
                            isPublicCode: .invalidConfiguration)
  }

  func testPublicDomainErrorForGACErrorKeychain() {
    assertPublicDomainError(forCoreCode: .keychain, isPublicCode: .keychain)
  }

  func testPublicDomainErrorForGACErrorUnsupported() {
    assertPublicDomainError(forCoreCode: .unsupported, isPublicCode: .unsupported)
  }

  func testPublicDomainErrorForGACErrorUnrecognizedCode() {
    let unrecognizedErrorCode = -1000 // Not part of the AppCheckCoreErrorCode enum
    let unknownError = NSError(domain: kAppCheckCoreErrorDomain, code: unrecognizedErrorCode,
                               userInfo: userInfo)

    let publicUnknownError = AppCheckErrorUtil.publicDomainError(with: unknownError)

    XCTAssertEqual(publicUnknownError.domain, AppCheckErrorDomain)
    XCTAssertEqual(publicUnknownError.code, AppCheckErrorCode.unknown.rawValue)
    XCTAssertEqual(publicUnknownError.localizedFailureReason, unknownError.localizedFailureReason)

    // Verify that the unrecognized error is wrapped as an underlying error.
    let underlyingError = publicUnknownError.userInfo[NSUnderlyingErrorKey] as? NSError
    XCTAssertEqual(underlyingError, unknownError)
  }

  func testPublicDomainErrorForUnrecognizedDomainError() {
    // Error from an unrecognized domain (i.e., not AppCheckErrorDomain or
    // "com.google.app_check_core").
    let unrecognizedError = NSError(domain: kTestErrorDomain, code: kTestErrorCode,
                                    userInfo: userInfo)

    let publicUnknownError = AppCheckErrorUtil.publicDomainError(with: unrecognizedError)

    XCTAssertEqual(publicUnknownError.domain, AppCheckErrorDomain)
    XCTAssertEqual(publicUnknownError.code, AppCheckErrorCode.unknown.rawValue)
    XCTAssertEqual(publicUnknownError.localizedFailureReason,
                   unrecognizedError.localizedFailureReason)

    // Verify that the unrecognized error is wrapped as an underlying error.
    let underlyingError = publicUnknownError.userInfo[NSUnderlyingErrorKey] as? NSError
    XCTAssertEqual(underlyingError, unrecognizedError)
  }

  // MARK: - Helpers

  private func assertPublicDomainError(forCoreCode coreCode: AppCheckCoreErrorCode,
                                       isPublicCode publicCode: AppCheckErrorCode,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
    let coreError = NSError(domain: kAppCheckCoreErrorDomain, code: coreCode.rawValue,
                            userInfo: userInfo)

    let publicError = AppCheckErrorUtil.publicDomainError(with: coreError)

    XCTAssertEqual(publicError.domain, AppCheckErrorDomain, file: file, line: line)
    XCTAssertEqual(publicError.code, publicCode.rawValue, file: file, line: line)
    XCTAssertEqual(coreError.userInfo as NSDictionary, userInfo as NSDictionary,
                   file: file, line: line)
    XCTAssertEqual(publicError.userInfo as NSDictionary, coreError.userInfo as NSDictionary,
                   file: file, line: line)
  }
}
