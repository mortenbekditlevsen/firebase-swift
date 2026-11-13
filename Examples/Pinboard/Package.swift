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

// Pinboard: a shared board of notes, built with SwiftCrossUI on firebase-swift's
// Auth, Firestore, Storage, Realtime Database and Functions. See README.md.

import PackageDescription

let package = Package(
    name: "Pinboard",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "firebase-swift", path: "../.."),
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.10.0")),
    ],
    targets: [
        // The model: everything Pinboard does with Firebase, without UI.
        .target(
            name: "PinboardKit",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-swift"),
                .product(name: "FirebaseCore", package: "firebase-swift"),
                .product(name: "FirebaseDatabase", package: "firebase-swift"),
                .product(name: "FirebaseFirestore", package: "firebase-swift"),
                .product(name: "FirebaseFunctions", package: "firebase-swift"),
                .product(name: "FirebaseStorage", package: "firebase-swift"),
            ],
            // FirebaseFirestore wraps upstream's C++ core, so its importers need
            // C++ interoperability (the other modules don't).
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        // The app.
        .executableTarget(
            name: "Pinboard",
            dependencies: [
                "PinboardKit",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        // Pinboard's flow without a window, as a check (README.md).
        .executableTarget(
            name: "pinboard-check",
            dependencies: ["PinboardKit"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
