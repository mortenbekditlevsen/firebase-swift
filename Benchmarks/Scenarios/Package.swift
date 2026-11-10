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

// The benchmark scenarios, shared by the port's and upstream's benchmark
// executables (which can't be one binary: both define FirebaseDatabase).
// No Firebase dependency.

import PackageDescription

let package = Package(
  name: "BenchmarkScenarios",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "BenchmarkScenarios", targets: ["BenchmarkScenarios"]),
    .executable(name: "bench-compare", targets: ["bench-compare"]),
  ],
  targets: [
    .target(name: "BenchmarkScenarios"),
    .executableTarget(name: "bench-compare", dependencies: ["BenchmarkScenarios"]),
  ]
)
