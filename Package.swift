// swift-tools-version:6.2
import PackageDescription

// The firebase-ios-sdk release this package corresponds to. Keep in sync with
// FirebaseVersion() in Sources/FirebaseCore/App.swift; see UPSTREAM.md.
let firebaseVersion = "13.1.1"

/// Firestore and the dependencies only it needs (gRPC, abseil, nanopb), which are by far the
/// largest. Apps that don't use Firestore can disable the trait so SwiftPM doesn't fetch them:
/// `.package(url: ..., traits: [])`. Enabled by default, as in firebase-ios-sdk 13.
let firestoreTrait = Trait(
  name: "Firestore",
  description: "Enables Firestore support and its underlying dependencies (gRPC, Abseil)."
)

let package = Package(
    name: "firebase-swift",
    platforms: [
        .iOS(.v18),
        // The OS versions that have Synchronization's Mutex.
        .tvOS(.v18),
        .macOS(.v15),
        .macCatalyst(.v18),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "FirebaseCore", targets: ["FirebaseCore"]),
        .library(name: "FirebaseAppCheck", targets: ["FirebaseAppCheck"]),
        .library(name: "FirebaseAuth", targets: ["FirebaseAuth"]),
        .library(name: "FirebaseDatabase", targets: ["FirebaseDatabase"]),
        .library(name: "FirebaseFunctions", targets: ["FirebaseFunctions"]),
        .library(name: "FirebaseStorage", targets: ["FirebaseStorage"]),
        .library(name: "FirebaseFirestore", targets: ["FirebaseFirestore"]),
    ],
    traits: [
        firestoreTrait,
        .default(enabledTraits: [firestoreTrait.name]),
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
        // The versions firebase-ios-sdk 13.1 pins; abseil with a Linux build fix.
        // See Docs/UpstreamPatches.md.
        .package(
            url: "https://github.com/mortenbekditlevsen/abseil-cpp-SwiftPM.git",
            branch: "linux-fixes-0.20250512.1"
        ),
        .package(url: "https://github.com/grpc/grpc-ios.git", "1.83.1" ..< "1.84.0"),
        .package(
          url: "https://github.com/firebase/nanopb.git",
          "2.30910.0" ..< "2.30911.0"
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
        // FirebaseAppCheck, with a port of Google's AppCheckCore
        // (github.com/google/app-check) in AppCheckCore/, as upstream builds on it.
        .target(
            name: "FirebaseAppCheck",
            dependencies: [
                "FirebaseCore",
                "FirebaseShared",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/FirebaseAppCheck",
            // AppCheckCore is written for Swift 5 mode, as upstream builds it.
            swiftSettings: [.swiftLanguageMode(SwiftLanguageMode.v5)]
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
            .product(name: "Logging", package: "swift-log"),
          ],
          path: "Sources/FirebaseFunctions"
        ),

            .target(
              name: "FirebaseStorage",
              dependencies: [
                "FirebaseCore",
                "FirebaseShared",
                .product(name: "Logging", package: "swift-log"),
              ],
              path: "Sources/FirebaseStorage",
              swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v6),
              ]
            ),

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
          name: "FirebaseFirestoreInternalWrapper",
          dependencies: [
            //"FirebaseAppCheckInterop",
            "FirebaseCore",
            "leveldb",
            .product(name: "Logging", package: "swift-log"),
            .product(name: "nanopb", package: "nanopb",
                     condition: .when(traits: [firestoreTrait.name])),
            .product(name: "abseil", package: "abseil-cpp-SwiftPM",
                     condition: .when(traits: [firestoreTrait.name])),
            .product(name: "gRPC-cpp", package: "grpc-ios",
                     condition: .when(traits: [firestoreTrait.name])),
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
            // connectivity_monitor_noop.cc is used on every platform for now.
            "core/src/remote/connectivity_monitor_apple.mm",
            "core/src/util/filesystem_win.cc",
            // Use log_stdio.cc instead of log_apple.mm to avoid ObjC FirebaseCore dependency
            "core/src/util/log_apple.mm",
            // Exclude ObjC++ files that depend on ObjC FirebaseCore
            "core/src/credentials/firebase_auth_credentials_provider_apple.mm",
            "core/src/credentials/firebase_app_check_credentials_provider_apple.mm",
            "core/src/remote/firebase_metadata_provider_apple.mm",
          ],
          sources: [
            "Source/",
            "Protos/nanopb/",
            "core/include/",
            "core/src",
          ],
          publicHeadersPath: "include",
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
          linkerSettings: [
            .linkedFramework(
              "SystemConfiguration",
              .when(platforms: [.iOS, .macOS, .tvOS, .visionOS])
            ),
            .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS, .visionOS])),
            .linkedLibrary("c++", .when(platforms: [.iOS, .macOS, .tvOS, .visionOS, .macCatalyst, .watchOS])),
            // abseil's Android log sink calls __android_log_write, from liblog.
            // TODO: link it in the abseil-cpp-SwiftPM fork instead.
            .linkedLibrary("log", .when(platforms: [.android])),
          ]
        ),
        .target(
          name: "FirebaseFirestore",
          dependencies: [
            "FirebaseCore",
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
            "include/",
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

        // AppCheckCore's unit tests (github.com/google/app-check), adapted where
        // marked "firebase-swift:", and FirebaseAppCheck's.
        .testTarget(
            name: "FirebaseAppCheckTests",
            dependencies: ["FirebaseAppCheck"],
            path: "Tests/FirebaseAppCheckTests",
            resources: [.process("Fixture")],
            swiftSettings: [.swiftLanguageMode(SwiftLanguageMode.v5)]
        ),
        .testTarget(
            name: "FirebaseCoreTests",
            dependencies: ["FirebaseCore"],
            path: "Tests/FirebaseCoreTests"
        ),
        .testTarget(
            name: "FirebaseAuthTests",
            dependencies: ["FirebaseAuth"],
            path: "Tests/FirebaseAuthTests"
        ),
        .testTarget(
            name: "FirebaseDatabaseTests",
            dependencies: ["FirebaseDatabase"],
            path: "Tests/FirebaseDatabaseTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "FirebaseFirestoreTests",
            dependencies: ["FirebaseFirestore"],
            path: "Sources/Firestore/Swift/Tests",
            sources: ["API", "Codable", "Credentials", "Helpers"],
            swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v5),
                .interoperabilityMode(.Cxx),
            ]
        ),
        // Upstream's Firestore integration tests, against the Firestore emulator;
        // skipped without it. The pipeline and search tests wait for pipelines.
        .testTarget(
            name: "FirebaseFirestoreIntegrationTests",
            dependencies: ["FirebaseFirestore"],
            path: "Sources/Firestore/Swift/Tests",
            exclude: [
                "Integration/PipelineApiTests.swift",
                "Integration/PipelineDmlTests.swift",
                "Integration/PipelineSubqueryTests.swift",
                "Integration/PipelineTests.swift",
                "Integration/QueryToPipelineTests.swift",
                "Integration/SearchIntegrationTests.swift",
            ],
            sources: ["Integration", "IntegrationSupport"],
            swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v5),
                .interoperabilityMode(.Cxx),
            ]
        ),
        // Runs against the Firebase emulators; skipped unless started via
        // `firebase emulators:exec` (see Tests/Emulator/README.md).
        .testTarget(
            name: "FirebaseIntegrationTests",
            dependencies: [
                "FirebaseAuth",
                "FirebaseDatabase",
                "FirebaseFirestore",
                "FirebaseFunctions",
                "FirebaseStorage",
            ],
            path: "Tests/FirebaseIntegrationTests",
            swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v5),
                .interoperabilityMode(.Cxx),
            ]
        ),
        // Upstream's unit tests are being ported one file at a time; `Port`
        // holds tests for this port's own code.
        // Upstream's unit tests, adapted where marked "Port note".
        .testTarget(
            name: "FirebaseFunctionsTests",
            dependencies: ["FirebaseFunctions"],
            path: "Tests/FirebaseFunctionsTests",
            sources: ["Unit", "Support"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FirebaseStorageTests",
            dependencies: ["FirebaseStorage"],
            path: "Tests/FirebaseStorageTests",
            exclude: [
                // Upstream's observer API (per-status handlers on a callback
                // queue); Port/StorageTaskTests covers the port's streams.
                "Unit/StorageObservableTaskTests.swift",
            ],
            sources: ["Unit", "Port", "Support"],
            swiftSettings: [
                .swiftLanguageMode(SwiftLanguageMode.v5),
            ]
        ),
        .testTarget(
            name: "FirebaseSharedTests",
            dependencies: [
                "FirebaseShared",
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Tests/FirebaseSharedTests"
        ),
    ],
    swiftLanguageModes: [.v6],
    // Matches upstream firebase-ios-sdk 13.1 and its abseil/gRPC pins. Abseil
    // builds its own absl::string_view below C++17, so every C++ target must
    // agree on the standard or the link fails.
    cxxLanguageStandard: .gnucxx17
)
