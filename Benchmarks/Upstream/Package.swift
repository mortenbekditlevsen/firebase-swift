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

// The shared scenarios against upstream's (Objective-C) Database, at the
// release the port is synced to. macOS only.

import PackageDescription

let package = Package(
  name: "UpstreamBenchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../Scenarios"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "13.1.1"),
  ],
  targets: [
    .executableTarget(
      name: "bench-upstream",
      dependencies: [
        .product(name: "BenchmarkScenarios", package: "Scenarios"),
        .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
        .product(name: "FirebaseDatabase", package: "firebase-ios-sdk"),
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
