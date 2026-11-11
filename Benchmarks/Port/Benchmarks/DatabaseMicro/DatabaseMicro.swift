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

// The value paths without a network, on 10k BenchItems (about 3 MB of JSON):
//
//   swift package --package-path Benchmarks/Port benchmark

import Benchmark
import BenchmarkScenarios
@_spi(Benchmarking) import FirebaseDatabase
import Foundation

let benchmarks: @Sendable () -> Void = {
  let items = Fixtures.items(count: 10_000)
  let json = try! Fixtures.json(items)
  let node = try! DatabaseBenchmarking.parseNode(json)
  let foundationValue = try! JSONSerialization.jsonObject(with: json)

  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
    maxDuration: .seconds(5),
    maxIterations: 50
  )

  // Inbound: what happens to a server payload before the sync tree has it.
  Benchmark("parse: JSON bytes -> node (FJSONScanner)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try DatabaseBenchmarking.parseNode(json))
    }
  }

  Benchmark("parse: JSON bytes -> node (JSONSerialization + nodeFrom)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try DatabaseBenchmarking.parseNodeWithJSONSerialization(json))
    }
  }

  Benchmark("parse: JSONSerialization only") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try JSONSerialization.jsonObject(with: json))
    }
  }

  Benchmark("build: Foundation value -> node (nodeFrom)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(DatabaseBenchmarking.node(from: foundationValue))
    }
  }

  // Reading: what `snapshot.value` and `snapshot.data(as:)` do.
  Benchmark("read: node -> Foundation value (val)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(DatabaseBenchmarking.value(of: node))
    }
  }

  Benchmark("decode: node -> [String: BenchItem] (val + FirebaseDataDecoder)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try DatabaseBenchmarking.decode([String: BenchItem].self, from: node))
    }
  }

  Benchmark("decode reference: JSON bytes -> [String: BenchItem] (JSONDecoder)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try JSONDecoder().decode([String: BenchItem].self, from: json))
    }
  }

  // Outbound: what a write does before the socket.
  Benchmark("serialize: node -> JSON bytes (FJSONWriter)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try DatabaseBenchmarking.serialize(node))
    }
  }

  Benchmark("serialize: node -> JSON bytes (val(forExport:) + JSONSerialization)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try DatabaseBenchmarking.serializeWithJSONSerialization(node))
    }
  }

  // Ordering: sorting children by key, which node building does per level.
  let keys = items.keys.shuffled()
  Benchmark("sort: 10k push-ID-like keys (compareKey)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(DatabaseBenchmarking.sortKeys(keys))
    }
  }
}
