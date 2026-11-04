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

/** The keys in a GeoPoint. Must match the properties of GeoPoint. */
private enum GeoPointKeys: String, CodingKey {
  case latitude
  case longitude
}

/** Extends GeoPoint to conform to Codable. */
extension GeoPoint: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: GeoPointKeys.self)
    let latitude = try container.decode(Double.self, forKey: .latitude)
    let longitude = try container.decode(Double.self, forKey: .longitude)
    // firebase-swift: upstream throws an Objective-C exception for coordinates out of range;
    // decoding throws instead of stopping the process.
    guard GeoPoint.isValidLatitude(latitude) else {
      throw DecodingError.dataCorruptedError(
        forKey: .latitude, in: container,
        debugDescription: "GeoPoint requires a latitude value in the range of [-90, 90], " +
          "but was \(latitude)"
      )
    }
    guard GeoPoint.isValidLongitude(longitude) else {
      throw DecodingError.dataCorruptedError(
        forKey: .longitude, in: container,
        debugDescription: "GeoPoint requires a longitude value in the range of [-180, 180], " +
          "but was \(longitude)"
      )
    }
    self.init(latitude: latitude, longitude: longitude)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: GeoPointKeys.self)
    try container.encode(latitude, forKey: .latitude)
    try container.encode(longitude, forKey: .longitude)
  }
}
