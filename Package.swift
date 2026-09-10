// swift-tools-version:6.2
import PackageDescription

let firebaseVersion = "12.14.0"

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
        .library(name: "FirebaseFirestore", targets: ["FirebaseFirestore"]),
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
            branch: "1.22.2-headerfix"
        ),
        .package(url: "https://github.com/firebase/abseil-cpp-SwiftPM.git", "0.20240722.0" ..< "0.20240723.0"),
        .package(url: "https://github.com/grpc/grpc-ios.git", "1.69.0" ..< "1.70.0"),
        .package(
          url: "https://github.com/firebase/nanopb.git",
          "2.30910.0" ..< "2.30911.0"
        ),
    ],
    targets: [
        .target(
            name: "FirebaseCore",
            path: "Sources/FirebaseCore",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
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
            exclude: [
              "third_party/LevelDB/LICENSE",
              "third_party/SocketRocket/LICENSE",
              "third_party/FImmutableSortedDictionary/LICENSE",
              "third_party/SocketRocket/aa2297808c225710e267afece4439c256f6efdb3",
            ],
            publicHeadersPath: "Public",
            cSettings: [
              .headerSearchPath("../../"),
            ],
            swiftSettings: [
                // leveldb is a C++ module, and exposes public headers with C++
                // The public headers could be changed to only contain C
                // (I did this previously), but we have another target
                // (Firestore) that requires the C++ headers.
                // So the interop mode here is specifically a workaround for
                // being able to consume leveldb public headers.
              .interoperabilityMode(.Cxx),
            ],
        ),
        .target(
          name: "FirebaseFirestoreTarget",
          dependencies: [.target(name: "FirebaseFirestore",
                                 condition: .when(platforms: [
                                   .iOS,
                                   .tvOS,
                                   .macOS,
                                   .visionOS,
                                   .macCatalyst,
                                 ]))],
          path: "Sources/FirebaseFirestoreWrap"
        ),

        .target(
          name: "FirebaseFirestoreInternalWrapper",
          dependencies: [
            //"FirebaseAppCheckInterop",
            "FirebaseCore",
            "leveldb",
            .product(name: "Logging", package: "swift-log"),
            .product(name: "nanopb", package: "nanopb"),
            .product(name: "abseil", package: "abseil-cpp-SwiftPM"),
            .product(name: "gRPC-cpp", package: "grpc-ios"),
          ],
          path: "Sources/Firestore",
          exclude: [ // ObjC removed
            "CHANGELOG.md",
            "CMakeLists.txt",
            "Example/",
            "LICENSE",
            "Protos/CMakeLists.txt",
            "Protos/Podfile",
            "Protos/README.md",
            "Protos/build_protos.py",
            "Protos/cpp/",
            "Protos/lib/",
            "Protos/nanopb_cpp_generator.py",
            "Protos/protos/",
            "README.md",
            "Source/CMakeLists.txt",
            "Source/Resources/",
            "Swift/",
            "core/CMakeLists.txt",
            "core/src/util/config_detected.h.in",
            "core/test/",
            "fuzzing/",
            "test.sh",
            "Source/API",
            "Source/Public",
            // Swift PM doesn't recognize hpp files, so we're relying on search paths
            // to find third_party/nlohmann_json/json.hpp.
            "third_party/",

            // Exclude alternate implementations for other platforms
            "core/src/remote/connectivity_monitor_apple.mm",
            "core/src/remote/connectivity_monitor_noop.cc",
            "core/src/util/filesystem_win.cc",
            "core/src/util/log_stdio.cc",
            "core/src/util/secure_random_openssl.cc",
          ],
          sources: [
            "Source/",
            "Protos/nanopb/",
            "core/include/",
            "core/src",
          ],
//          publicHeadersPath: "Source/Public",
          cSettings: [
            .headerSearchPath("../"),
            .headerSearchPath("Source/Public/FirebaseFirestore"),
            .headerSearchPath("Protos/nanopb"),
            .headerSearchPath("third_party/re2"),
            .define("PB_FIELD_32BIT", to: "1"),
            .define("PB_NO_PACKED_STRUCTS", to: "1"),
            .define("PB_ENABLE_MALLOC", to: "1"),
            .define("FIRFirestore_VERSION", to: firebaseVersion),
          ],
          cxxSettings: [
            .headerSearchPath("../")
          ],
//          swiftSettings: [
//            .interoperabilityMode(.Cxx),
//          ],
          linkerSettings: [
            .linkedFramework(
              "SystemConfiguration",
              .when(platforms: [.iOS, .macOS, .tvOS, .visionOS])
            ),
            .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS, .visionOS])),
            .linkedLibrary("c++"),
          ]
        ),
        .target(
          name: "FirebaseFirestore",
          dependencies: [
            "FirebaseCore",
//            "FirebaseCoreExtension",
            "FirebaseFirestoreInternalWrapper",
            "FirebaseShared",
          ],
          path: "Sources/Firestore",
          exclude: [
            "CHANGELOG.md",
            "CMakeLists.txt",
            "Example/",
            "LICENSE",
            "Protos/",
            "README.md",
            "Source/",
            "Swift/Source/Resources/",
            "core/",
            "fuzzing/",
            "test.sh",
            "Swift/CHANGELOG.md",
            "Swift/Tests/",
            "third_party/nlohmann_json",
          ],
          sources: [
            "Swift/Source/",
          ],
          resources: [.process("Source/Resources/PrivacyInfo.xcprivacy")],
          swiftSettings: [
            .swiftLanguageMode(SwiftLanguageMode.v5),
            .interoperabilityMode(.Cxx),
          ]
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
