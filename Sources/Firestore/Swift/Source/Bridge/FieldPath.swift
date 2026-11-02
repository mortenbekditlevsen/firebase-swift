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

import Foundation

/// A path to a field in a document, as a list of field names. Unlike a dotted
/// string, it can address field names that contain dots.
public final class FieldPath: Hashable, Sendable {
  let segments: [String]

  /// Creates a path from field names, e.g. `FieldPath(["address", "city"])`.
  public init(_ fieldNames: [String]) {
    if fieldNames.isEmpty {
      invalidArgument("Invalid field path. Provided names must not be empty.")
    }
    for (index, name) in fieldNames.enumerated() where name.isEmpty {
      invalidArgument("Invalid field name at index \(index). Field names must not be empty.")
    }
    segments = fieldNames
  }

  private init(segments: [String]) {
    self.segments = segments
  }

  /// A special path that refers to the document ID, for queries.
  public static func documentID() -> FieldPath {
    FieldPath(segments: ["__name__"])
  }

  /// Parses a dot-separated path such as `"address.city"`, with the rules of
  /// upstream's `FieldPath::FromDotSeparatedString`.
  convenience init(dotSeparated path: String) {
    if path.contains(where: { "~*/[]".contains($0) }) {
      invalidArgument(
        "Invalid field path (\(path)). Paths must not contain '~', '*', '/', '[', or ']'"
      )
    }
    let segments = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if segments.contains(where: \.isEmpty) {
      invalidArgument(
        "Invalid field path (\(path)). Paths must not be empty, begin with '.', end with '.', " +
          "or contain '..'"
      )
    }
    self.init(segments: segments)
  }

  /// A field given as a `String` (dot-separated) or a `FieldPath`, as upstream
  /// accepts in `mergeFields`, `updateData` keys and `get(_:)`.
  static func from(_ field: Any, invalidMessage: @autoclosure () -> String) -> FieldPath {
    switch field {
    case let path as FieldPath: path
    case let string as String: FieldPath(dotSeparated: string)
    default: invalidArgument(invalidMessage())
    }
  }

  var cppSegments: CppStringVector {
    var vector = CppStringVector()
    for segment in segments {
      vector.push_back(std.string(segment))
    }
    return vector
  }

  public static func == (lhs: FieldPath, rhs: FieldPath) -> Bool {
    lhs.segments == rhs.segments
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(segments)
  }
}
