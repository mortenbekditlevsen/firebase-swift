// swift-tools-version:6.2
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

// The port's benchmarks: `bench-port` runs the shared scenarios against the
// Database emulator; `DatabaseMicro` (package-benchmark) measures the value
// paths without a network. See Benchmarks/README.md.

import PackageDescription

let package = Package(
  name: "PortBenchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../Scenarios"),
    // Without Firestore, so its C++ dependencies aren't fetched.
    .package(name: "firebase-swift", path: "../..", traits: []),
    .package(url: "https://github.com/ordo-one/benchmark.git", from: "1.27.0"),
  ],
  targets: [
    .executableTarget(
      name: "bench-port",
      dependencies: [
        .product(name: "BenchmarkScenarios", package: "Scenarios"),
        .product(name: "FirebaseCore", package: "firebase-swift"),
        .product(name: "FirebaseDatabase", package: "firebase-swift"),
      ],
      // FirebaseDatabase's leveldb module has C++ headers (see Benchmarks/README.md).
      swiftSettings: [.interoperabilityMode(.Cxx)]
    ),
    .executableTarget(
      name: "DatabaseMicro",
      dependencies: [
        .product(name: "BenchmarkScenarios", package: "Scenarios"),
        .product(name: "FirebaseDatabase", package: "firebase-swift"),
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "Benchmarks/DatabaseMicro",
      swiftSettings: [.interoperabilityMode(.Cxx)],
      plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
    ),
  ]
)
