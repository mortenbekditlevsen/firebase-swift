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

/// F1: reading documents from Firestore's local cache, step by step, so that
/// the conversions after the core can be told apart from the core's own work.
///
/// The SDK-specific executables (`bench-firestore-port`,
/// `bench-firestore-upstream`) write the documents and say how to read them;
/// this runs and records the steps, each as its own scenario:
///
/// - `F1-query`: a query of the whole collection from the cache, until its
///   snapshot is there.
/// - then each step over every document of the snapshot, e.g. `F1-data`
///   (`data()`) and `F1-data-as` (`data(as: BenchItem.self)`).
///
/// F1-typed does the same with documents of Firestore's own types (a
/// `Timestamp`, a `Date`, a `GeoPoint` and a `DocumentReference`), which
/// each SDK defines as `TypedItem`: `F1-typed-query`, `F1-typed-data`,
/// `F1-typed-data-as`.
public enum FirestoreRead {
  public struct Step<Document> {
    public var scenario: String
    public var run: (Document) throws -> Void

    public init(_ scenario: String, _ run: @escaping (Document) throws -> Void) {
      self.scenario = scenario
      self.run = run
    }
  }

  public struct Options: Sendable {
    public var documents = 10_000
    public var iterations = 10
    public var warmup = 1
    public var output: String?

    /// `--documents N --iterations N --warmup N --output path`
    public static func parse(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws -> Options {
      var options = Options()
      var iterator = arguments.makeIterator()
      while let argument = iterator.next() {
        guard let value = iterator.next() else { throw BenchmarkError("\(argument) needs a value") }
        switch argument {
        case "--documents": options.documents = Int(value) ?? options.documents
        case "--iterations": options.iterations = Int(value) ?? options.iterations
        case "--warmup": options.warmup = Int(value) ?? options.warmup
        case "--output": options.output = value
        default: throw BenchmarkError("unknown argument \(argument)")
        }
      }
      return options
    }
  }

  /// Runs warmup + iterations reads, recording each one after warmup.
  public static func run<Document>(
    target: String,
    options: Options,
    queryScenario: String = "F1-query",
    query: () async throws -> [Document],
    steps: [Step<Document>]
  ) async throws {
    let output = RecordWriter(path: options.output)
    let revision = ProcessInfo.processInfo.environment["BENCHMARK_GIT_REVISION"]
    let clock = ContinuousClock()
    for run in 0 ..< options.warmup + options.iterations {
      let iteration = run - options.warmup
      func record(_ scenario: String, _ wall: Duration, _ cpu: Duration) throws {
        guard iteration >= 0 else { return }
        try output.write(BenchmarkRecord(
          target: target, variant: "default", scenario: scenario, iteration: iteration,
          wallMilliseconds: wall.milliseconds, cpuMilliseconds: cpu.milliseconds,
          peakResidentMegabytes: ProcessMetrics.peakResidentMegabytes(),
          extra: ["documents": Double(options.documents)], gitRevision: revision, date: Date()
        ))
      }

      var cpuStart = ProcessMetrics.cpuTime()
      var start = clock.now
      let documents = try await query()
      try record(queryScenario, clock.now - start, ProcessMetrics.cpuTime() - cpuStart)
      guard documents.count == options.documents else {
        throw BenchmarkError("the query returned \(documents.count) documents, not \(options.documents)")
      }
      for step in steps {
        cpuStart = ProcessMetrics.cpuTime()
        start = clock.now
        for document in documents {
          try step.run(document)
        }
        try record(step.scenario, clock.now - start, ProcessMetrics.cpuTime() - cpuStart)
      }
    }
  }
}
