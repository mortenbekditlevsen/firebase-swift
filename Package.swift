// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "firebase-swift",
    platforms: [
        .iOS(.v18),
        .tvOS(.v13),
        .macOS(.v15),
        .macCatalyst(.v13),
        .watchOS(.v7),
    ],
    products: [
        .library(name: "FirebaseCore", targets: ["FirebaseCore"]),
        .library(name: "FirebaseAuth", targets: ["FirebaseAuth"]),
        .library(name: "FirebaseDatabase", targets: ["FirebaseDatabase"]),
        .library(name: "FirebaseFunctions", targets: ["FirebaseFunctions"]),
        .library(name: "FirebaseStorage", targets: ["FirebaseStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.3.0",
            traits: ["UnstableSortedCollections"]
        ),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
        .package(
            url: "https://github.com/mortenbekditlevsen/leveldb.git",
            branch: "1.22.2-mine"
        ),
    ],
    targets: [
        .target(
            name: "FirebaseCore",
            path: "Sources/FirebaseCore"
        ),
        .target(
            name: "FirebaseShared",
            path: "Sources/FirebaseShared",
            exclude: [
                "third_party/FirebaseDataEncoder/LICENSE",
                "third_party/FirebaseDataEncoder/METADATA",
            ]
        ),
        .target(
            name: "FirebaseAuth",
            dependencies: [
                "FirebaseCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/FirebaseAuth"
        ),
        .target(
          name: "FirebaseFunctions",
          dependencies: [
            "FirebaseCore",
            "FirebaseShared",
          ],
          path: "Sources/FirebaseFunctions"
        ),
//        .testTarget(
//          name: "FirebaseFunctionsUnit",
//          dependencies: ["FirebaseFunctions",
//                         "FirebaseAppCheckInterop",
//                         "FirebaseAuthInterop",
//                         "FirebaseMessagingInterop",
//                         "SharedTestUtilities"],
//          path: "FirebaseFunctions/Tests/Unit",
//          cSettings: [
//            .headerSearchPath("../../../"),
//          ],
//          swiftSettings: [
//            .swiftLanguageMode(SwiftLanguageMode.v5),
//          ]
//        ),
//        .testTarget(
//          name: "FirebaseFunctionsIntegration",
//          dependencies: ["FirebaseFunctions",
//                         "SharedTestUtilities"],
//          path: "FirebaseFunctions/Tests/Integration"
//        ),
//        .testTarget(
//          name: "FirebaseFunctionsObjCIntegration",
//          dependencies: ["FirebaseFunctions",
//                         "SharedTestUtilities"],
//          path: "FirebaseFunctions/Tests/ObjCIntegration",
//          // See https://forums.swift.org/t/importing-swift-libraries-from-objective-c/56730
//          exclude: [
//            "ObjCPPAPITests.mm",
//          ],
//          cSettings: [
//            .headerSearchPath("../../.."),
//          ]
//        ),

            .target(
              name: "FirebaseStorage",
              dependencies: [
                "FirebaseCore",
              ],
              path: "Sources/FirebaseStorage",
              swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v6),
              ]
            ),
//            .testTarget(
//              name: "FirebaseStorageUnit",
//              dependencies: ["FirebaseStorage",
//                             "SharedTestUtilities"],
//              path: "FirebaseStorage/Tests/Unit",
//              cSettings: [
//                .headerSearchPath("../../../"),
//              ],
//              swiftSettings: [
//                .swiftLanguageMode(SwiftLanguageMode.v5),
//              ]
//            ),
//            .testTarget(
//              name: "StorageObjCIntegration",
//              dependencies: ["FirebaseStorage"],
//              path: "FirebaseStorage/Tests/ObjCIntegration",
//              exclude: [
//                // See https://forums.swift.org/t/importing-swift-libraries-from-objective-c/56730
//                "FIRStorageIntegrationTests.m",
//                "ObjCPPAPITests.mm",
//                "Credentials.h",
//              ],
//              cSettings: [
//                .headerSearchPath("../../.."),
//              ]
//            ),

        .target(
            name: "FirebaseDatabase",
            dependencies: [
                "FirebaseCore",
                "FirebaseShared",
                "leveldb",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "SortedCollections", package: "swift-collections"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux, .windows, .android])
                ),
            ],
            path: "Sources/FirebaseDatabase",
            exclude: ["third_party/LevelDB/LICENSE"]
        ),
        .testTarget(
            name: "FirebaseAuthTests",
            dependencies: ["FirebaseAuth"],
            path: "Tests/FirebaseAuthTests"
        ),
        .testTarget(
            name: "FirebaseDatabaseTests",
            dependencies: ["FirebaseDatabase"],
            path: "Tests/FirebaseDatabaseTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
