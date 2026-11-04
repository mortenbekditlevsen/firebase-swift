// Copyright 2024 Google LLC
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

// Port note: a port of upstream's FIRAppCheckValidatorTests.m; `FIRAppCheckValidator` is the
// `tokenExchangeMissingFields(in:)` function here.

@testable import FirebaseAppCheck
import FirebaseCore
import XCTest

final class AppCheckValidatorTests: XCTestCase {
  func test_tokenExchangeMissingFieldsInOptions_noMissingFields() {
    var options = FirebaseOptions(googleAppID: "TEST_GoogleAppID", gcmSenderID: "TEST_GCMSenderID")
    options.apiKey = "TEST_APIKey"
    options.projectID = "TEST_ProjectID"

    let missingFields = tokenExchangeMissingFields(in: options)

    XCTAssertEqual(missingFields.count, 0)
  }

  func test_tokenExchangeMissingFieldsInOptions_singleMissingField() {
    // Google App ID is empty:
    var options = FirebaseOptions(googleAppID: "", gcmSenderID: "TEST_GCMSenderID")
    options.apiKey = "TEST_APIKey"
    options.projectID = "TEST_ProjectID"

    let missingFields = tokenExchangeMissingFields(in: options)

    XCTAssertEqual(missingFields, ["googleAppID"])
  }

  func test_tokenExchangeMissingFieldsInOptions_multipleMissingFields() {
    // Google App ID is empty, and API Key and Project ID are not set:
    let options = FirebaseOptions(googleAppID: "", gcmSenderID: "TEST_GCMSenderID")

    let missingFields = tokenExchangeMissingFields(in: options)

    XCTAssertEqual(missingFields, ["APIKey", "projectID", "googleAppID"])
  }
}
