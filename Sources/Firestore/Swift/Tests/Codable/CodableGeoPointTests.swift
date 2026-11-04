/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import FirebaseFirestore
import Foundation
import XCTest

class CodableGeoPointTests: XCTestCase {
  func testGeoPointEncodes() {
    let geoPoint = GeoPoint(latitude: 37.77493, longitude: -122.41942)

    let jsonData = try! JSONEncoder().encode(geoPoint)
    let json = String(data: jsonData, encoding: .utf8)!

    // The ordering of attributes in the JSON output is not guaranteed, nor is the rounding of
    // the values so just verify that each required property is present and that the value
    // starts as expected.
    XCTAssert(json.contains("\"latitude\":37."))
    XCTAssert(json.contains("\"longitude\":-122."))
  }

  func testGeoPointDecodes() {
    let json = """
    {
      "latitude": 37.77493,
      "longitude": -122.41942
    }
    """
    let jsonData: Data = json.data(using: .utf8)!

    let geoPoint = try! JSONDecoder().decode(GeoPoint.self, from: jsonData)
    XCTAssertEqual(37.77493, geoPoint.latitude, accuracy: 0.0001)
    XCTAssertEqual(-122.41942, geoPoint.longitude, accuracy: 0.0001)
  }

  // Port note: upstream's GeoPoint throws an Objective-C exception for coordinates out of range;
  // decoding throws a DecodingError here.
  func testGeoPointOutOfRangeDoesNotDecode() {
    for (latitude, longitude) in [(90.5, 0.0), (-91.0, 0.0), (0.0, 180.5), (0.0, -181.0)] {
      let json = "{\"latitude\": \(latitude), \"longitude\": \(longitude)}"
      XCTAssertThrowsError(try JSONDecoder().decode(GeoPoint.self, from: Data(json.utf8))) {
        guard case DecodingError.dataCorrupted = $0 else {
          return XCTFail("Expected dataCorrupted, got \($0)")
        }
      }
    }
  }

  func testGeoPointRangeIncludesItsBounds() throws {
    for (latitude, longitude) in [(90.0, 180.0), (-90.0, -180.0)] {
      let json = "{\"latitude\": \(latitude), \"longitude\": \(longitude)}"
      let geoPoint = try JSONDecoder().decode(GeoPoint.self, from: Data(json.utf8))
      XCTAssertEqual(geoPoint, GeoPoint(latitude: latitude, longitude: longitude))
    }
  }

  func testGeoPointIsHashable() {
    let geoPoint = GeoPoint(latitude: 37.77493, longitude: -122.41942)
    let geoPoint2 = GeoPoint(latitude: 37.77493, longitude: -122.41942)
    let dictionary: [GeoPoint: String] = [geoPoint: "foo"]
    XCTAssertEqual("foo", dictionary[geoPoint2])
  }
}
