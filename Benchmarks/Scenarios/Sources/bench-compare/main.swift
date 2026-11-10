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

// Summarizes benchmark JSON-lines files as a Markdown table: medians per
// scenario and target, and the port's ratio to upstream's fastest variant.
//
//   bench-compare results/a.jsonl results/b.jsonl ...

import BenchmarkScenarios
import Foundation

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

var records: [BenchmarkRecord] = []
for path in CommandLine.arguments.dropFirst() {
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write(Data("can't read \(path)\n".utf8))
    exit(1)
  }
  for line in text.split(separator: "\n") where !line.isEmpty {
    records.append(try decoder.decode(BenchmarkRecord.self, from: Data(line.utf8)))
  }
}
guard !records.isEmpty else {
  print("usage: bench-compare <results.jsonl>...")
  exit(1)
}

func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  guard !sorted.isEmpty else { return .nan }
  let middle = sorted.count / 2
  return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

func format(_ value: Double) -> String {
  value.isNaN ? "–" : String(format: value >= 100 ? "%.0f" : "%.1f", value)
}

struct Summary {
  var label: String
  var target: String
  var count: Int
  var wall: Double
  var cpu: Double
  var memory: Double
  var decode: Double
}

print("| Scenario | Target | n | Wall ms | CPU ms | Peak MB | Decode ms | Wall vs upstream |")
print("|---|---|---:|---:|---:|---:|---:|---:|")
for scenario in Set(records.map(\.scenario)).sorted() {
  let groups = Dictionary(grouping: records.filter { $0.scenario == scenario }) {
    "\($0.target) (\($0.variant))"
  }
  let summaries = groups.map { label, runs in
    Summary(label: label, target: runs[0].target, count: runs.count,
            wall: median(runs.map(\.wallMilliseconds)), cpu: median(runs.map(\.cpuMilliseconds)),
            memory: median(runs.map(\.peakResidentMegabytes)),
            decode: median(runs.compactMap { $0.extra["decodeMilliseconds"] }))
  }.sorted { $0.label < $1.label }
  let upstreamBest = summaries.filter { $0.target == "upstream" }.map(\.wall).min()
  for summary in summaries {
    let ratio = upstreamBest.map { summary.target == "upstream" ? "" : String(format: "%.2f×", summary.wall / $0) } ?? ""
    print("| \(scenario) | \(summary.label) | \(summary.count) | \(format(summary.wall)) | " +
      "\(format(summary.cpu)) | \(format(summary.memory)) | \(format(summary.decode)) | \(ratio) |")
  }
}
