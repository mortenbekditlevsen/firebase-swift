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

// The port's Firestore benchmarks, apart from Benchmarks/Port so that the
// Database benchmarks don't fetch and build Firestore's C++ dependencies.
// See Benchmarks/README.md.

import PackageDescription

let package = Package(
  name: "FirestorePortBenchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../Scenarios"),
    .package(name: "firebase-swift", path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "bench-firestore-port",
      dependencies: [
        .product(name: "BenchmarkScenarios", package: "Scenarios"),
        .product(name: "FirebaseCore", package: "firebase-swift"),
        .product(name: "FirebaseFirestore", package: "firebase-swift"),
      ],
      swiftSettings: [.interoperabilityMode(.Cxx)]
    ),
  ]
)
