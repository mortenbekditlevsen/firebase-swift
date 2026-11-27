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

// Upstream's Firestore benchmarks. Upstream links a prebuilt Firestore unless
// FIREBASE_SOURCE_FIRESTORE is set, so this package needs it set, and builds
// Firestore, gRPC and abseil from source like the port. It's apart from
// Benchmarks/Upstream, whose dependencies the variable would change.
// See Benchmarks/README.md.

import Foundation
import PackageDescription

guard Context.environment["FIREBASE_SOURCE_FIRESTORE"] != nil else {
  fatalError("Set FIREBASE_SOURCE_FIRESTORE=1, so that upstream builds Firestore from source.")
}

let package = Package(
  name: "FirestoreUpstreamBenchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../Scenarios"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "13.2.0"),
  ],
  targets: [
    .executableTarget(
      name: "bench-firestore-upstream",
      dependencies: [
        .product(name: "BenchmarkScenarios", package: "Scenarios"),
        .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
        .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
