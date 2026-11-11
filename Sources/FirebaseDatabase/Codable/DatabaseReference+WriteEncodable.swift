/*
 * Copyright 2020 Google LLC
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

@preconcurrency import Foundation
import FirebaseShared

public extension DatabaseReference {
  /// Encodes `value` and writes it here, as `setValue(_:)` does (queued,
  /// without waiting for the server).
  ///
  /// See `Database.Encoder` for the encoding; the value is encoded straight
  /// to the database's data.
  ///
  /// - Throws: `EncodingError` if the value doesn't encode, or encodes to
  ///   data the database can't store (such as keys with `.#$[]/`, or NaN).
  func setValue<T: Encodable>(from value: T,
                              encoder: Database.Encoder = Database.Encoder()) throws {
    let node = try encodedNode(value, encoder: encoder)
    repo.enqueue { [path] repo in repo.set(path, withNode: node) }
  }

  /// `setValue(from:encoder:)`, returning once the server has acknowledged
  /// the write.
  func setValueAndWait<T: Encodable>(from value: T,
                                     encoder: Database.Encoder = Database.Encoder()) async throws {
    try await write(encodedNode(value, encoder: encoder))
  }

  private func encodedNode<T: Encodable>(_ value: T, encoder: Database.Encoder) throws -> FNode {
    FValidation.validateFrom("setValue:", writablePath: path)
    return try FNodeEncoder(encoder).encode(value)
  }
}
