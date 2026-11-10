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

/// The model the decode scenarios decode into: ten fields of the usual kinds.
public struct BenchItem: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var score: Int
  public var rating: Double
  public var active: Bool
  public var tags: [String]
  public var createdAt: Int
  public var latitude: Double
  public var longitude: Double
  public var note: String
}

/// Deterministic test data, so every run and both SDKs see the same bytes.
public enum Fixtures {
  /// A small, fast, seeded generator (SplitMix64).
  public struct Generator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  private static let words = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
    "juliett", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
  ]

  /// Child keys that sort like push IDs (`c00000`, `c00001`, …).
  public static func key(_ index: Int) -> String {
    "c" + String(repeating: "0", count: max(0, 5 - String(index).count)) + String(index)
  }

  public static func item(_ index: Int, using generator: inout Generator) -> BenchItem {
    func word() -> String { words[Int(generator.next() % UInt64(words.count))] }
    return BenchItem(
      id: key(index),
      name: "\(word()) \(word())",
      score: Int(generator.next() % 100_000),
      rating: Double(generator.next() % 10_000) / 100,
      active: generator.next() % 2 == 0,
      tags: [word(), word()],
      createdAt: 1_700_000_000_000 + Int(generator.next() % 100_000_000),
      latitude: Double(generator.next() % 180_000) / 1000 - 90,
      longitude: Double(generator.next() % 360_000) / 1000 - 180,
      note: (0 ..< 6).map { _ in word() }.joined(separator: " ")
    )
  }

  /// `count` items keyed by `key(_:)`.
  public static func items(count: Int, seed: UInt64 = 42) -> [String: BenchItem] {
    var generator = Generator(seed: seed)
    var result: [String: BenchItem] = [:]
    result.reserveCapacity(count)
    for index in 0 ..< count {
      result[key(index)] = item(index, using: &generator)
    }
    return result
  }

  /// The items as JSON, as the REST API takes them.
  public static func json(_ items: [String: BenchItem]) throws -> Data {
    try JSONEncoder().encode(items)
  }
}
