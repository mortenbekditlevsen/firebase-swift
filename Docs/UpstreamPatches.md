# Local patches to vendored upstream code

Code copied verbatim from upstream (the Firestore C++ core, the
`FirebaseDataEncoder` third-party file and AppCheckCore) is changed as little as possible so
upstream updates can be applied as patches. Every local change is marked with a
`firebase-swift:` comment, so `grep -rn "firebase-swift:" Sources` lists them.
Re-apply these after pulling in a new upstream version.

## Firestore C++ core (`Sources/Firestore/core`)

SwiftPM can't exclude files per platform, so Apple-only `.mm` files guard
their own contents, as upstream already does for `filesystem_apple.mm` and
`status_apple.mm`:

| File | Guard |
|---|---|
| `src/util/executor_libdispatch.mm` | `#if HAVE_LIBDISPATCH` (mirrors `executor_std.cc`'s `#if !HAVE_LIBDISPATCH`) |
| `src/util/byte_stream_apple.mm` | `#if __APPLE__` |
| `src/util/error_apple.mm` | `#if __APPLE__` |
| `src/util/exception_apple.mm` | `#if __APPLE__` |

`Package.swift` exclusions that differ from upstream:

- `connectivity_monitor_noop.cc` is compiled on every platform;
  `connectivity_monitor_apple.mm` is excluded.
- `secure_random_openssl.cc` is compiled (it guards itself with
  `HAVE_OPENSSL_RAND_H`, which `config.h` sets only on Linux).

`src/util/filesystem_posix.cc` builds on Android, where upstream has `#error`
placeholders: the data directory is `$XDG_DATA_HOME` (or
`$HOME/.local/share`), as on Linux, and the temporary directory `$TMPDIR` (or
`/data/local/tmp`). Native code can't look up an app's storage without JNI, so
Android apps set `XDG_DATA_HOME` and `TMPDIR` to their files and cache
directories, as FirebaseAuth's file storage also expects.

`src/api/firestore_bridge.cc`, `src/api/firestore_bridge_internal.h`,
`src/api/pipeline_bridge.cc` and `include/{FirestoreBridge,PipelineBridge}.h`
are ours (the Swift bridge), not upstream code. `pipeline_bridge.cc` follows
upstream's `Firestore/Source/API/FIRPipelineBridge.mm`.

`src/util/ordered_code.cc`: `ReadNumDecreasing` inverts the length byte as an
`unsigned char`. Upstream inverts the `char`, which `~` promotes to `int`; where
`char` is unsigned (Linux on arm64, Android) that gives a negative number, so
the length is huge and every decreasing number fails to decode. Found by
`OrderedCodeUint64.EncodeDecode` (`scripts/test-firestore-core.sh` on arm64
Linux). Firestore itself only reads `ReadSignedNumIncreasing`, which already
uses `unsigned char`, so no stored data was affected. Worth reporting upstream.

## C++ core tests

`scripts/test-firestore-core.sh` builds and runs the core's GoogleTest suites
(`Sources/Firestore/core/test/unit`) with upstream's own CMake build: it checks
out upstream's root `CMakeLists.txt` and `cmake/` at the release Firestore is
synced to, puts `Sources/Firestore` in place of upstream's `Firestore`, and
builds the tests with their dependencies. The `firestore-core` CI job runs it
on Linux.

## Firestore Swift layer (`Sources/Firestore/Swift`)

Upstream's Swift API sits on Objective-C classes; here it sits on the Swift
bridge in `Swift/Source/Bridge/`, so a few upstream files differ:

- `Bridge/BridgeTypes.swift` (ours) has the pipeline bridge classes, with
  upstream's `__`-prefixed names (Objective-C++ upstream), on
  `include/PipelineBridge.h`.
- The BSON types (`MinKey`, `Int32Value`, …) are Swift classes in
  `Bridge/BSONTypes.swift` instead of Objective-C ones; upstream's
  `+Codable.swift` files for them are used unchanged, except that
  `Codable/Blob+Codable.swift` imports Foundation (upstream gets `Data` through
  its Objective-C module).
- `Helper/PipelineHelper.swift` reads `FieldValue.methodName` instead of using
  key-value coding (`firebase-swift:` comment).
- `Stages.swift` passes `Int(limit)` and `Int(offset)` where upstream uses
  `NSInteger(…)`.
- `GeoPoint` is a struct in `Bridge/FirestoreTypes.swift` instead of an
  Objective-C class. Its initializer stops the process for coordinates out of
  range, where upstream's throws an exception, and
  `Codable/GeoPoint+Codable.swift` throws a `DecodingError` for them instead.
  Equality uses `==`, so 0 and -0 are equal (upstream compares bits).
- `Codable/DocumentID.swift`: `DocumentID` is `Sendable` when its value is,
  so `Sendable` models can use `@DocumentID` (`firebase-swift:` comment).

Upstream's integration tests (`Swift/Tests/Integration/`) are changed only
where marked `Port note:`: deprecated settings, `NSErrorPointer` transaction
blocks (Linux has none), Combine's `Future` (Apple-only), `Timestamp` being a
struct, bundle error codes, `catch … as NSError` on Linux, and two tests that
expect exceptions. `grep -rn "Port note" Sources/Firestore/Swift/Tests` lists
them; `Swift/Tests/API/BasicCompileTests.swift` has them too.

## FirebaseDataEncoder (`Sources/FirebaseShared/third_party/FirebaseDataEncoder`)

- **Passthrough values are boxed.** Upstream requires passthrough types
  (`Timestamp`, `GeoPoint`, `FieldValue`, `DocumentReference`, …) to be
  `NSObject` subclasses. Here they are Swift types, so they're wrapped in
  `_PassthroughBox` while encoding and unwrapped at the top level. That only
  happens when a passthrough value was actually encoded, so the output for
  Functions and Database is unchanged.
- **Booleans aren't decoded as numbers.** Upstream compares against
  `kCFBooleanTrue`/`kCFBooleanFalse`; that's kept on Darwin, and elsewhere a
  Swift `Bool` is recognized by its dynamic type.

## AppCheckCore (`Sources/FirebaseAppCheck/AppCheckCore`)

Vendored from [google/app-check](https://github.com/google/app-check)
12.1.0 as part of the `FirebaseAppCheck` target (upstream builds it as its
own `AppCheckCore` module). `grep -rn "firebase-swift:"
Sources/FirebaseAppCheck/AppCheckCore` lists the changes:

- **No GoogleUtilities.** The token and App Attest artifact go to an
  `AppCheckKeychain` instead of `GULKeychainStorage`: on Apple platforms
  `AppCheckSystemKeychain` by default, which stores the items as
  `GULKeychainStorage` does, or the app's own, passed to
  `AppCheck.setAppCheckProviderFactory(_:keychain:)` (required elsewhere).
  The storages archive the objects themselves, as `GULKeychainStorage` did,
  so the stored bytes are the same. Processes that can't use the data
  protection keychain (unsigned macOS tools) keep the items in memory, where
  upstream fails every token request.
  `GULUserDefaults` is replaced by `UserDefaults`.
- **Archived class names.** Upstream keeps `GACAppCheckStoredToken` and
  `GACAppAttestStoredArtifact` as the archived names with `@objc(…)`; here
  they're registered with `NSKeyedArchiver.setClassName` and
  `NSKeyedUnarchiver.setClass`, so archives stay readable both ways. (On
  Linux and Android, corelibs ignores `setClassName` when encoding, so
  archives written there carry the Swift name; reading upstream's works.)
- **Linux.** SHA-256 from swift-crypto instead of CommonCrypto;
  FoundationNetworking imports; DeviceCheck and App Attest behind
  `#if canImport(DeviceCheck)`; `NSErrorPointer` and Objective-C block
  request hooks behind `#if canImport(ObjectiveC)`.
- **Delivery queue.** Completion handlers and the token delegate are called
  on a serial queue (`AppCheckCore.deliveryQueue`), not the main queue, which
  never runs in servers and command line tools.
- `NSLock.execute`, which upstream defines in the App Attest provider, is in
  `Port/NSLock+Execute.swift`, since the provider is Apple-only.

The tests in `Tests/FirebaseAppCheckTests/AppCheckCore` are upstream's, with
`Port note` comments where they differ: the keychain storage tests run
against an in-memory `AppCheckKeychain` (upstream needs a host app), and the
main-thread delivery tests are skipped.

FirebaseAppCheck itself is a Swift rewrite of upstream's Objective-C, so it
has no patches. Upstream's unit tests for it are Objective-C with OCMock;
`Tests/FirebaseAppCheckTests/FirebaseAppCheck` ports them to Swift, running
`AppCheck` on a real `AppCheckCore` built from the AppCheckCore fakes.
`AppCheck` is an `NSObject`, as upstream's is: swift-corelibs-foundation's
`NotificationCenter` only matches an observer's `object` by identity for
`NSObject`s, so token-change observers for an instance were never called on
Linux and Android while it wasn't.

## Dependencies

- **abseil-cpp-SwiftPM:** 0.20250512.1, the version firebase-ios-sdk 13.1
  pins. Linux needs one fix on top, which the fork
  `mortenbekditlevsen/abseil-cpp-SwiftPM` carries (branch
  `linux-fixes-0.20250512.1`): `absl/numeric/int128.h` includes
  `int128_*_intrinsic.inc` inside `namespace absl`. On Linux, SwiftPM passes
  abseil's generated umbrella module map to every dependent C++ compile, so
  Clang treats those includes as nested module imports
  (`-Wmodules-import-nested-redundant`, an error by default). The includes
  are wrapped in a `#pragma clang diagnostic`. (The fork's older
  `linux-fixes-0.20240722.2` branch also excluded `.inc` files from the
  target; upstream does that itself since 0.20250512.) For Android, the fork
  also excludes `absl/random/internal/nanobenchmark.cc`, which only abseil's
  own tests and benchmarks use: its static initializer runs a timing benchmark
  (`rdtsc` on x86-64) when the binary loads, which crashes in Android's
  x86-64 emulator. And it links `liblog`, which abseil's Android log sink
  needs.
- **grpc-ios:** 1.83.1, as firebase-ios-sdk 13.1; it builds on Linux
  unchanged.
- **C++ standard:** `Package.swift` sets `cxxLanguageStandard: .gnucxx17`,
  as upstream 13.x does, and abseil and grpc-ios build as C++17 too. They
  must agree: abseil defines its own `absl::string_view` below C++17, so a
  mismatch fails at link time with undefined
  `absl::…(std::basic_string_view…)` symbols.
- **libc++** is linked on Apple platforms only. Linux uses libstdc++.
- **leveldb:** `mortenbekditlevsen/leveldb`, branch `1.22.2-headerfix`
  (includes the `F_FULLFSYNC` fix needed on Linux).
