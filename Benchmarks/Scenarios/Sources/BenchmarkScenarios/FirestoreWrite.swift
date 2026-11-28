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

/// F2: writing documents, step by step, up to the core's mutation: the SDK's
/// own work before anything is sent or stored.
///
/// The SDK-specific executables say what each step does with the document at
/// an index; this runs each over every document and records it as its own
/// scenario:
///
/// - `F2-encode`: `Firestore.Encoder` to `[String: Any]`.
/// - `F2-bridge` (port only): that copied into the bridge's C++ map.
/// - `F2-set`: `WriteBatch.setData(_:forDocument:)` with the encoded data,
///   which the core parses and validates into a mutation.
/// - `F2-set-from`: `WriteBatch.setData(from:forDocument:)`, all of it.
///
/// F2-typed does the same with `TypedItem` (F1-typed's documents).
///
/// Batches are never committed: committing waits for a server, and storing
/// the write in the cache is the core's work, not the SDK's.
public enum FirestoreWrite {
  /// Runs warmup + iterations, recording each one after warmup. `reset` runs
  /// before each step, e.g. to start a new batch.
  public static func run(
    target: String,
    options: FirestoreRead.Options,
    reset: () -> Void,
    steps: [FirestoreRead.Step<Int>]
  ) throws {
    let output = RecordWriter(path: options.output)
    let revision = ProcessInfo.processInfo.environment["BENCHMARK_GIT_REVISION"]
    let clock = ContinuousClock()
    for run in 0 ..< options.warmup + options.iterations {
      let iteration = run - options.warmup
      for step in steps {
        reset()
        let cpuStart = ProcessMetrics.cpuTime()
        let start = clock.now
        for index in 0 ..< options.documents {
          try step.run(index)
        }
        let wall = clock.now - start
        let cpu = ProcessMetrics.cpuTime() - cpuStart
        guard iteration >= 0 else { continue }
        try output.write(BenchmarkRecord(
          target: target, variant: "default", scenario: step.scenario, iteration: iteration,
          wallMilliseconds: wall.milliseconds, cpuMilliseconds: cpu.milliseconds,
          peakResidentMegabytes: ProcessMetrics.peakResidentMegabytes(),
          extra: ["documents": Double(options.documents)], gitRevision: revision, date: Date()
        ))
      }
    }
  }
}
