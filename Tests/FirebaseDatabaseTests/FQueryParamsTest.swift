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

// Port of upstream's FirebaseDatabase/Tests/Unit/FQueryParamsTest.m (13.1.1).
// Port note: the indexes are cases of the `FIndex` enum.

@testable import FirebaseDatabase
import XCTest

class FQueryParamsTest: XCTestCase {
  private func roundTripped(_ params: FQueryParams) -> FQueryParams {
    FQueryParams.fromQueryObject(params.wireProtocolParams)
  }

  func testQueryParamsEquals() {
    do { // Limit equals
      let params1 = FQueryParams.defaultInstance.limitToLast(10)
      let params2 = FQueryParams.defaultInstance.limitTo(10)
      let params3 = FQueryParams.defaultInstance.limitToFirst(10)
      let params4 = FQueryParams.defaultInstance.limitToLast(11)
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
      XCTAssertNotEqual(params1, params4)
    }

    do { // Index equals
      let params1 = FQueryParams.defaultInstance.orderBy(.priority)
      let params2 = FQueryParams.defaultInstance.orderBy(.priority)
      let params3 = FQueryParams.defaultInstance.orderBy(.key)
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }

    do { // startAt equals
      let params1 = FQueryParams.defaultInstance.startAt(NODE("value"))
      let params2 = FQueryParams.defaultInstance.startAt(NODE("value"), childKey: nil)
      let params3 = FQueryParams.defaultInstance.startAt(NODE("value-2"))
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }

    do { // startAt with childkey equals
      let params1 = FQueryParams.defaultInstance.startAt(.empty, childKey: "key")
      let params2 = FQueryParams.defaultInstance.startAt(.empty, childKey: "key")
      let params3 = FQueryParams.defaultInstance.startAt(.empty, childKey: "other-key")
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }

    do { // endAt equals
      let params1 = FQueryParams.defaultInstance.endAt(NODE("value"))
      let params2 = FQueryParams.defaultInstance.endAt(NODE("value"), childKey: nil)
      let params3 = FQueryParams.defaultInstance.endAt(NODE("value-2"))
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }

    do { // endAt with childkey equals
      let params1 = FQueryParams.defaultInstance.endAt(.empty, childKey: "key")
      let params2 = FQueryParams.defaultInstance.endAt(.empty, childKey: "key")
      let params3 = FQueryParams.defaultInstance.endAt(.empty, childKey: "other-key")
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }

    do { // Limit/startAt equals
      let params1 = FQueryParams.defaultInstance.limitToFirst(10).startAt(NODE("value"))
      let params2 = FQueryParams.defaultInstance.limitTo(10).startAt(NODE("value"))
      let params3 = FQueryParams.defaultInstance.limitTo(10).startAt(NODE("value-2"))
      XCTAssertEqual(params1, params2)
      XCTAssertEqual(params1.hashValue, params2.hashValue)
      XCTAssertNotEqual(params1, params3)
    }
  }

  func testFromDictionaryEquals() {
    let params1 = FQueryParams.defaultInstance.limitToLast(10)
      .startAt(NODE("start-value"), childKey: "child-key-2")
      .endAt(NODE("end-value"), childKey: "child-key-2")
      .orderBy(.key)
    XCTAssertEqual(params1, roundTripped(params1))
    XCTAssertEqual(params1.hashValue, roundTripped(params1).hashValue)
  }

  func testCanCreateAllIndexes() {
    let params1 = FQueryParams.defaultInstance.orderBy(.key)
    let params2 = FQueryParams.defaultInstance.orderBy(.value)
    let params3 = FQueryParams.defaultInstance.orderBy(.priority)
    let params4 = FQueryParams.defaultInstance.orderBy(.path(PATH("subkey")))
    XCTAssertEqual(params1, roundTripped(params1))
    XCTAssertEqual(params2, roundTripped(params2))
    XCTAssertEqual(params3, roundTripped(params3))
    XCTAssertEqual(params4, roundTripped(params4))
    XCTAssertEqual(params1.hashValue, roundTripped(params1).hashValue)
    XCTAssertEqual(params2.hashValue, roundTripped(params2).hashValue)
    XCTAssertEqual(params3.hashValue, roundTripped(params3).hashValue)
    XCTAssertEqual(params4.hashValue, roundTripped(params4).hashValue)
  }

  func testDifferentLimits() {
    let params1 = FQueryParams.defaultInstance.limitToFirst(10)
    let params2 = FQueryParams.defaultInstance.limitToLast(10)
    let params3 = FQueryParams.defaultInstance.limitTo(10)
    XCTAssertEqual(params1, roundTripped(params1))
    XCTAssertEqual(params2, roundTripped(params2))
    XCTAssertEqual(params3, roundTripped(params3))
    // 2 and 3 are equivalent
    XCTAssertEqual(params2, roundTripped(params3))

    XCTAssertEqual(params1.hashValue, roundTripped(params1).hashValue)
    XCTAssertEqual(params2.hashValue, roundTripped(params2).hashValue)
    XCTAssertEqual(params3.hashValue, roundTripped(params3).hashValue)
    // 2 and 3 are equivalent
    XCTAssertEqual(params2.hashValue, roundTripped(params3).hashValue)
  }

  func testStartAtNullIsSerializable() {
    var params = FQueryParams.defaultInstance
    params = params.startAt(.empty, childKey: "key")
    let dict = params.wireProtocolParams
    let parsed = FQueryParams.fromQueryObject(dict)
    XCTAssertEqual(parsed, params)
    XCTAssertTrue(parsed.hasStart)
  }

  func testEndAtNullIsSerializable() {
    var params = FQueryParams.defaultInstance
    params = params.endAt(.empty, childKey: "key")
    let dict = params.wireProtocolParams
    let parsed = FQueryParams.fromQueryObject(dict)
    XCTAssertEqual(parsed, params)
    XCTAssertTrue(parsed.hasEnd)
  }
}
