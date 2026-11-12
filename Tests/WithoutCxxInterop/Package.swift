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

// An app that imports every module except FirebaseFirestore, without Swift's
// C++ interoperability, as the README promises. CI builds it; it fails if one
// of the modules makes its importers need C++ (e.g. a C++ module imported
// from Swift, as leveldb was).

import PackageDescription

let package = Package(
    name: "WithoutCxxInterop",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15), .macCatalyst(.v18), .watchOS(.v11)],
    dependencies: [
        // Without the Firestore trait, which is the one module that needs C++.
        .package(name: "firebase-swift", path: "../..", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "WithoutCxxInterop",
            dependencies: [
                .product(name: "FirebaseAppCheck", package: "firebase-swift"),
                .product(name: "FirebaseAuth", package: "firebase-swift"),
                .product(name: "FirebaseCore", package: "firebase-swift"),
                .product(name: "FirebaseDatabase", package: "firebase-swift"),
                .product(name: "FirebaseFunctions", package: "firebase-swift"),
                .product(name: "FirebaseStorage", package: "firebase-swift"),
            ]
        ),
    ]
)
