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

/// The scenarios. Each runs in its own process (`--scenario`), so peak memory
/// is per scenario.
public enum Scenario: String, CaseIterable, Sendable {
  /// Initial load of 10k children (about 3 MB of JSON) on a new connection.
  case initialLoad = "S1-initial-load"
  /// 10k child-added events, pushed by the server in 100 merges of 100.
  case childUpdates = "S2-child-updates"
  /// S1, then decoding the snapshot into `[String: BenchItem]`.
  case decode = "S3-decode"
  /// 2k writes, each awaited before the next.
  case writesSequential = "S4a-writes-sequential"
  /// 5k writes started together.
  case writesPipelined = "S4b-writes-pipelined"
  /// Prime the persistence cache with 10k children (no measurement).
  case persistencePrime = "S5-prime"
  /// Read the 10k children from the persistence cache, offline, in a new
  /// process after `S5-prime`. One measurement per process.
  case persistenceCold = "S5-cold"
  /// 50 concurrent transactions on one counter.
  case transactions = "S6-transactions"
}

public struct BenchmarkRunner {
  public struct Options: Sendable {
    public var scenario: Scenario
    public var iterations = 5
    public var warmup = 1
    public var output: String?
    /// Separates the data of concurrent or repeated runs.
    public var runID = "run"
    /// The process fails after this long, so a hang doesn't stall a run.
    public var timeout = Duration.seconds(600)
  }

  /// Parses the command line and runs one scenario with `driver`.
  public static func main(driver: some BenchmarkDriver) async {
    do {
      let options = try parse(Array(CommandLine.arguments.dropFirst()))
      Task.detached {
        try await Task.sleep(for: options.timeout)
        FileHandle.standardError.write(Data("error: \(options.scenario.rawValue) timed out after \(options.timeout)\n".utf8))
        exit(2)
      }
      try await run(options, driver: driver)
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }

  static func parse(_ arguments: [String]) throws -> Options {
    var scenario: Scenario?
    var options = Options(scenario: .initialLoad)
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
      func value() throws -> String {
        guard let value = iterator.next() else { throw BenchmarkError("\(argument) needs a value") }
        return value
      }
      switch argument {
      case "--scenario":
        let name = try value()
        guard let match = Scenario.allCases.first(where: { $0.rawValue == name || $0.rawValue.hasPrefix(name + "-") })
        else {
          throw BenchmarkError("unknown scenario \(name); one of " +
            Scenario.allCases.map(\.rawValue).joined(separator: ", "))
        }
        scenario = match
      case "--iterations": options.iterations = Int(try value()) ?? options.iterations
      case "--warmup": options.warmup = Int(try value()) ?? options.warmup
      case "--output": options.output = try value()
      case "--run-id": options.runID = try value()
      case "--timeout": options.timeout = .seconds(Int(try value()) ?? 600)
      default: throw BenchmarkError("unknown argument \(argument)")
      }
    }
    guard let scenario else { throw BenchmarkError("--scenario is required") }
    options.scenario = scenario
    return options
  }

  static func run(_ options: Options, driver: some BenchmarkDriver) async throws {
    let emulator = try EmulatorDatabase()
    let records = RecordWriter(path: options.output)
    let base = "public/bench-\(driver.target)-\(options.runID)"
    let revision = ProcessInfo.processInfo.environment["BENCHMARK_GIT_REVISION"]

    func client(_ name: String, persistence: Bool = false) async throws -> any BenchmarkClient {
      try await driver.makeClient(name: name, persistence: persistence, emulator: emulator)
    }

    /// Runs `body` warmup + iterations times, measuring each run after warmup.
    func measure(_ body: (Int) async throws -> [String: Double]) async throws {
      for iteration in 0 ..< options.warmup + options.iterations {
        let cpuBefore = ProcessMetrics.cpuTime()
        let start = ContinuousClock.now
        let extra = try await body(iteration)
        let wall = ContinuousClock.now - start
        let cpu = ProcessMetrics.cpuTime() - cpuBefore
        guard iteration >= options.warmup else { continue }
        try records.write(BenchmarkRecord(
          target: driver.target, variant: driver.variant, scenario: options.scenario.rawValue,
          iteration: iteration - options.warmup, wallMilliseconds: wall.milliseconds,
          cpuMilliseconds: cpu.milliseconds,
          peakResidentMegabytes: ProcessMetrics.peakResidentMegabytes(), extra: extra,
          gitRevision: revision, date: Date()
        ))
      }
    }

    let items = Fixtures.items(count: 10_000)

    switch options.scenario {
    case .initialLoad, .decode:
      let path = "\(base)/load"
      try await emulator.put(path, json: Fixtures.json(items))
      // Measured: the client's connection and its first value event. Creating
      // and closing the client isn't.
      for iteration in 0 ..< options.warmup + options.iterations {
        let reader = try await client("bench-\(UUID().uuidString)")
        let cpuBefore = ProcessMetrics.cpuTime()
        let start = ContinuousClock.now
        var extra: [String: Double] = [:]
        if options.scenario == .decode {
          let (count, decode) = try await reader.firstValueDecoded(at: path)
          extra = ["children": Double(count), "decodeMilliseconds": decode.milliseconds]
        } else {
          extra = ["children": Double(try await reader.firstValue(at: path))]
        }
        let wall = ContinuousClock.now - start
        let cpu = ProcessMetrics.cpuTime() - cpuBefore
        await reader.close()
        // Let the client's teardown (freeing its data) finish, so it doesn't
        // overlap the next iteration's load.
        try await Task.sleep(for: .milliseconds(200))
        guard iteration >= options.warmup else { continue }
        guard extra["children"] == Double(items.count) else {
          throw BenchmarkError("expected \(items.count) children, got \(extra["children"] ?? 0)")
        }
        try records.write(BenchmarkRecord(
          target: driver.target, variant: driver.variant, scenario: options.scenario.rawValue,
          iteration: iteration - options.warmup, wallMilliseconds: wall.milliseconds,
          cpuMilliseconds: cpu.milliseconds,
          peakResidentMegabytes: ProcessMetrics.peakResidentMegabytes(), extra: extra,
          gitRevision: revision, date: Date()
        ))
      }

    case .childUpdates:
      let reader = try await client("bench-\(UUID().uuidString)")
      let sorted = items.sorted { $0.key < $1.key }
      try await measure { iteration in
        let path = "\(base)/updates-\(iteration)"
        try await reader.childAdded(at: path, count: items.count) {
          for start in stride(from: 0, to: sorted.count, by: 100) {
            let batch = Dictionary(uniqueKeysWithValues: sorted[start ..< min(start + 100, sorted.count)]
              .map { ($0.key, $0.value) })
            try await emulator.patch(path, json: Fixtures.json(batch))
          }
        }
        return [:]
      }
      await reader.close()

    case .writesSequential, .writesPipelined:
      let sdk = try await client("bench-\(UUID().uuidString)")
      let count = options.scenario == .writesSequential ? 2000 : 5000
      let batch = Array(items.values.prefix(count))
      try await measure { iteration in
        let path = "\(base)/writes-\(iteration)"
        if options.scenario == .writesSequential {
          try await sdk.writeSequentially(at: path, items: batch)
        } else {
          try await sdk.writePipelined(at: path, items: batch)
        }
        return ["writes": Double(count)]
      }
      await sdk.close()

    case .persistencePrime:
      let path = "\(base)/persisted"
      try await emulator.put(path, json: Fixtures.json(items))
      let primer = try await client("bench-persistence", persistence: true)
      await primer.keepSynced(at: path)
      let count = try await primer.firstValue(at: path)
      // Give the cache time to write everything before the process exits.
      try await Task.sleep(for: .seconds(3))
      await primer.close()
      FileHandle.standardError.write(Data("primed \(count) children at \(path)\n".utf8))

    case .persistenceCold:
      let path = "\(base)/persisted"
      let cpuBefore = ProcessMetrics.cpuTime()
      let start = ContinuousClock.now
      let reader = try await client("bench-persistence", persistence: true)
      await reader.goOffline()
      let count = try await reader.firstValue(at: path)
      let wall = ContinuousClock.now - start
      let cpu = ProcessMetrics.cpuTime() - cpuBefore
      guard count == items.count else {
        throw BenchmarkError("expected \(items.count) cached children, got \(count); run S5-prime first")
      }
      try records.write(BenchmarkRecord(
        target: driver.target, variant: driver.variant, scenario: options.scenario.rawValue,
        iteration: 0, wallMilliseconds: wall.milliseconds, cpuMilliseconds: cpu.milliseconds,
        peakResidentMegabytes: ProcessMetrics.peakResidentMegabytes(),
        extra: ["children": Double(count)], gitRevision: revision, date: Date()
      ))

    case .transactions:
      let sdk = try await client("bench-\(UUID().uuidString)")
      try await measure { iteration in
        let path = "\(base)/counter-\(iteration)"
        let final = try await sdk.concurrentIncrements(at: path, count: 50)
        guard final == 50 else { throw BenchmarkError("counter ended at \(final), not 50") }
        return ["transactions": 50]
      }
      await sdk.close()
    }
  }
}
