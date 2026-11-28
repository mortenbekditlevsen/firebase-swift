# Local patches to vendored upstream code

Code copied verbatim from upstream (the Firestore C++ core, the
`FirebaseDataEncoder` third-party file and AppCheckCore) is changed as little as possible so
upstream updates can be applied as patches. Every local change is marked with a
`firebase-swift:` comment, so `grep -rn "firebase-swift:" Sources` lists them.
Re-apply these after pulling in a new upstream version.

## Firestore C++ core (`Sources/Firestore/core`)

SwiftPM can't exclude files per platform, so platform-specific files guard
their own contents, as upstream already does for `filesystem_apple.mm` and
`status_apple.mm`:

| File | Guard |
|---|---|
| `src/util/executor_libdispatch.mm` | `#if HAVE_LIBDISPATCH` (mirrors `executor_std.cc`'s `#if !HAVE_LIBDISPATCH`) |
| `src/util/byte_stream_apple.mm` | `#if __APPLE__` |
| `src/util/error_apple.mm` | `#if __APPLE__` |
| `src/util/exception_apple.mm` | `#if __APPLE__` |
| `src/util/filesystem_posix.cc` | `#if !_WIN32` (upstream guards only parts; `filesystem_win.cc` is used on Windows) |

`Package.swift` exclusions that differ from upstream:

- `connectivity_monitor_noop.cc` is compiled on every platform;
  `connectivity_monitor_apple.mm` is excluded.
- `secure_random_openssl.cc` is compiled (it guards itself with
  `HAVE_OPENSSL_RAND_H`, which `config.h` sets on Linux and Windows).
- `filesystem_win.cc` is compiled (it guards itself with `_WIN32`).

`src/util/config.h` also sets `HAVE_OPENSSL_RAND_H` for Windows under SwiftPM;
upstream only knows Apple and Linux there, and builds Windows with CMake.

`src/util/quadruple_builder.cc`: the 64-bit hex constants in
`POS_POWERS_OF_2` and `NEG_POWERS_OF_2` end in `ULL` rather than `LL`. Clang on
Windows follows MSVC and types a hex literal that doesn't fit `long long` as a
negative `long long` rather than `unsigned long long`, so brace-initializing
`uint64_t` with it is a narrowing error. The values are the same everywhere.

`src/util/quadruple.cc`: converting to `double` uses `std::scalbn` rather than
POSIX's obsolete `scalb`, which Windows doesn't have. The exponent is an
integer, so the result is the same.

`src/util/log_stdio.cc` (the log outside Apple platforms) flushes stdout after
each message. Piped stdout is fully buffered, so an assertion's message was
lost when the process aborted right after logging it, as Windows CI showed.

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
- `data(as:)` decodes the core's values in place
  (`Codable/FirestoreValueDecoder.swift`, ours, through accessors in
  `include/FirestoreBridge.h`), instead of decoding the `[String: Any]` of
  `data(with:)`: `Codable/DocumentSnapshot+ReadDecodable.swift` and
  `Codable/EncoderDecoder.swift` call it (`firebase-swift:` comments). It
  decodes as before, errors included; values whose result could depend on
  how `FirebaseDataDecoder` treats Foundation values go through it as before.
  `Firestore.Decoder.decode(_:from:)` is unchanged.

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
- **A `Decimal` must fit.** Upstream makes a `Decimal` of the number's
  `Double`, which stops the process for an infinity and gives NaN for a
  number beyond `Decimal`'s range (above about 1e160, below about 1e-110).
  Both throw `dataCorrupted` here, as an integer that doesn't fit does; a NaN
  still decodes as `Decimal.nan`. The Database's `FNodeDecoder` does the
  same (`Decimal(fitting:)` in FirebaseShared).

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

Five dependencies come from forks under `mortenbekditlevsen`, on branches
with Linux and Windows build fixes. The root package's URL takes the place of
the one a dependency asks for, so grpc-ios also gets the forked abseil and
BoringSSL. Move back to upstream as the fixes are released there.

On Windows, SwiftPM ignores source and exclude paths that end in "/", so
leveldb, abseil and grpc-ios compiled nothing, or compiled what they meant to
exclude. Their forks name those directories without the "/".

- **leveldb:** `mortenbekditlevsen/leveldb`, branch `1.22.2-windows`. On top
  of `1.22.2-headerfix` (the `F_FULLFSYNC` fix needed on Linux): source paths
  without "/", and `util/env_posix.cc` and `util/env_windows.cc` each guard
  themselves with `_WIN32`, as SwiftPM can't exclude a file per platform.
- **abseil-cpp-SwiftPM:** 0.20250512.1, the version firebase-ios-sdk 13.1
  pins, from `mortenbekditlevsen/abseil-cpp-SwiftPM`, branch
  `windows-fixes-0.20250512.1`. On top of `linux-fixes-0.20250512.1`, which
  has:
  - `absl/numeric/int128.h` includes `int128_*_intrinsic.inc` inside
    `namespace absl`. On Linux, SwiftPM passes abseil's generated umbrella
    module map to every dependent C++ compile, so Clang treats those includes
    as nested module imports (`-Wmodules-import-nested-redundant`, an error
    by default). The includes are wrapped in a `#pragma clang diagnostic`.
    (The fork's older `linux-fixes-0.20240722.2` branch also excluded `.inc`
    files from the target; upstream does that itself since 0.20250512.)
  - For Android, it excludes `absl/random/internal/nanobenchmark.cc`, which
    only abseil's own tests and benchmarks use: its static initializer runs a
    timing benchmark (`rdtsc` on x86-64) when the binary loads, which crashes
    in Android's x86-64 emulator. And it links `liblog`, which abseil's
    Android log sink needs.

  The Windows branch adds the `"absl"` path without "/", and the defines
  abseil's own build uses on Windows (`absl/copts`): `NOMINMAX` (windows.h's
  `max()` macro breaks `numeric_limits<>::max()`), `WIN32_LEAN_AND_MEAN` and
  others.
  It also links CoreFoundation only on Apple platforms, as grpc-ios below.
- **grpc-ios:** 1.83.1, as firebase-ios-sdk 13.1, from
  `mortenbekditlevsen/grpc-ios`, branch `windows-1.83.1`: paths without "/",
  `NOMINMAX` on Windows (as gRPC's CMake build: windows.h's macros break
  re2), and on Windows the bundled zlib's headers instead of a system `libz`,
  which Windows doesn't have. (It builds on Linux unchanged.) Offered
  upstream as grpc/grpc-ios#397; the fork has since replaced the zlib part
  (below). More changes:
  - Not the bundled zlib at all: on Windows, the-swift-collective/zlib,
    and elsewhere the system `libz`, as upstream links. Upstream also
    compiles the bundled copy, which clashed with other copies in an app
    (Pinboard, through SwiftCrossUI's image support). Prefixing it
    (`Z_PREFIX`), as offered in grpc/grpc-ios#398 (since closed), isn't enough:
    libjpeg-turbo's package, which SwiftCrossUI 0.11 brings in, compiles
    zlib with `Z_PREFIX` too, and the same `z_` symbols clashed. The zlib
    package is shared instead: libpng uses it too, and SwiftPM builds a
    package once. Upstream may well not accept a dependency on another
    package, so this one may stay in the fork.
  - It depends on the abseil and BoringSSL forks below. firebase-swift lists
    them too, but that only overrides grpc-ios's URLs when firebase-swift is
    the root package: SwiftPM keeps the first URL it meets for a package, so
    Pinboard got upstream BoringSSL. This one is for the fork only.
  - On ARM64 Windows, upb's `encode_longvarint` leaves out the alignment
    directive in its inline assembly, which crashes LLVM while it writes the
    unwind info (llvm/llvm-project#47432). upb already leaves it out under
    `__SEH__`, but clang defines that only for MinGW, not for the MSVC target.
    upb is protocolbuffers/protobuf's, which grpc-ios copies.
  - CoreFoundation is linked only on Apple platforms (tools version 5.9, to
    name visionOS). PackageDescription documents `linkedFramework` as ignored
    elsewhere, but swift-build, Swift 6.4's default build system, passes it
    to the Linux linker, which fails. So that's a swift-build bug, and the
    condition works around it.
- **boringssl-SwiftPM** (gRPC's BoringSSL): 0.41.0, from
  `mortenbekditlevsen/boringSSL-SwiftPM`, branch `windows-0.41.0`.
  firebase-swift lists it only to replace grpc-ios's. On Windows it defines
  `_WINSOCKAPI_`, `NOMINMAX` and `NOCRYPT`, as swift-nio-ssl's copy does, and
  renames the thread-exit callback with a define, which otherwise clashes
  with the one in swift-crypto's BoringSSL. Everywhere, it compiles its error
  tables from `gen/crypto/err_data.cc` rather than `err_data.c`:
  `crypto/err/err.cc` declares them in C++ without `extern "C"`, which on
  Windows names them differently from C. Offered upstream as
  firebase/boringSSL-SwiftPM#36.
- **swift-nio:** 2.105.2 from `mortenbekditlevsen/swift-nio`, branch
  `windows-2.105.2`, with three Windows fixes:
  - casts in `CNIOWindows.h`, whose wrappers pass `void *` where WinSock
    takes `char *`. C++ doesn't allow that, so modules with C++ interop (as
    FirebaseDatabase's dependents) couldn't import NIO
    (apple/swift-nio#3801);
  - apple/swift-nio#3708 (for issue #3702), which reports `WSAEWOULDBLOCK`
    as would-block instead of an error. Without it, a socket whose buffer
    fills fails its channel, so the tests' NIO servers cut responses short;
  - the same for `Windows.recv`, which stream sockets read with and which
    #3708 leaves out. NIO reads again after a read that fills its buffer, so
    when the data ends exactly at the buffer's end, the next read failed the
    channel: large messages failed intermittently (`carriesLargeMessages`
    with the WinHTTP transport). Offered upstream as apple/swift-nio#3800.
- **C++ standard:** `Package.swift` sets `cxxLanguageStandard: .gnucxx17`,
  as upstream 13.x does, and abseil and grpc-ios build as C++17 too. They
  must agree: abseil defines its own `absl::string_view` below C++17, so a
  mismatch fails at link time with undefined
  `absl::…(std::basic_string_view…)` symbols.
- **libc++** is linked on Apple platforms only. Linux uses libstdc++.
