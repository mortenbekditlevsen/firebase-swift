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
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// One measured iteration of a scenario, written as a JSON line.
public struct BenchmarkRecord: Codable, Sendable {
  /// "port" or "upstream".
  public var target: String
  /// A variant of the target, e.g. upstream's callback queue.
  public var variant: String
  public var scenario: String
  public var iteration: Int
  /// Wall-clock time of the measured part.
  public var wallMilliseconds: Double
  /// Process CPU time (user + system) during the measured part.
  public var cpuMilliseconds: Double
  /// The process's peak resident set size so far.
  public var peakResidentMegabytes: Double
  /// Scenario-specific numbers (e.g. decode time).
  public var extra: [String: Double]
  public var gitRevision: String?
  public var date: Date
}

/// Process CPU time and peak memory.
public enum ProcessMetrics {
  public static func cpuTime() -> Duration {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func duration(_ time: timeval) -> Duration {
      .seconds(Int64(time.tv_sec)) + .microseconds(Int64(time.tv_usec))
    }
    return duration(usage.ru_utime) + duration(usage.ru_stime)
  }

  public static func peakResidentMegabytes() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    #if canImport(Darwin)
      return Double(usage.ru_maxrss) / 1_048_576 // bytes
    #else
      return Double(usage.ru_maxrss) / 1024 // kilobytes
    #endif
  }
}

extension Duration {
  public var milliseconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) * 1000 + Double(attoseconds) / 1e15
  }
}

/// Appends records to a JSON-lines file (or prints them).
public struct RecordWriter: Sendable {
  public let path: String?

  public init(path: String?) { self.path = path }

  public func write(_ record: BenchmarkRecord) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    var line = try encoder.encode(record)
    line.append(UInt8(ascii: "\n"))
    guard let path else {
      FileHandle.standardOutput.write(line)
      return
    }
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }
}
