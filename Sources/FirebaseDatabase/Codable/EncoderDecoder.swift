/*
 * Copyright 2021 Google LLC
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

import FirebaseShared

public extension Database {
  /// The settings of `setValue(from:)` and the typed transactions: the
  /// strategies and `userInfo`. As upstream, it's `FirebaseDataEncoder`, but
  /// those APIs encode straight to the database's data (`FNodeEncoder`), not
  /// through it. Its own `encode(_:)` makes Foundation values, the slower path.
  typealias Encoder = FirebaseDataEncoder
  /// The settings of `data(as:)`, the typed sequences, `get(as:)` and
  /// `firstValue(as:)`: the strategies and `userInfo`. As upstream, it's
  /// `FirebaseDataDecoder`, but those APIs decode straight from the
  /// database's data (`FNodeDecoder`), not through it. Its own
  /// `decode(_:from:)` reads Foundation values, such as `snapshot.value`: the
  /// slower path.
  typealias Decoder = FirebaseDataDecoder
}
