// swift-tools-version: 6.2
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

// An iOS app that measures how the Database's transports cope with
// backgrounding and network changes on a device. Open this folder in Xcode,
// set a team for signing, and run it on a phone. See README.md.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "BackgroundProbe",
    platforms: [.iOS("18.0")],
    products: [
        .iOSApplication(
            name: "BackgroundProbe",
            targets: ["BackgroundProbe"],
            bundleIdentifier: "dev.firebase-swift.BackgroundProbe",
            displayVersion: "1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight]
        ),
    ],
    dependencies: [
        // Without Firestore, so its C++ dependencies aren't fetched.
        .package(name: "firebase-swift", path: "../..", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "BackgroundProbe",
            dependencies: [
                .product(name: "FirebaseCore", package: "firebase-swift"),
                .product(name: "FirebaseDatabase", package: "firebase-swift"),
            ],
            path: "Sources",
            // FirebaseDatabase's leveldb module has C++ headers (see Benchmarks/README.md).
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
