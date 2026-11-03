# Local patches to vendored upstream code

Code copied verbatim from upstream (the Firestore C++ core and the
`FirebaseDataEncoder` third-party file) is changed as little as possible so
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

`src/api/firestore_bridge.cc` and `include/FirestoreBridge.h` are ours (the
Swift bridge), not upstream code.

## Firestore Swift layer (`Sources/Firestore/Swift`)

Upstream's Swift API sits on Objective-C classes; here it sits on the Swift
bridge in `Swift/Source/Bridge/`, so a few upstream files differ:

- `Bridge/BridgeTypes.swift` (ours) has stubs for the pipeline bridge
  classes, with upstream's `__`-prefixed names. Pipelines don't execute yet.
- The BSON types (`MinKey`, `Int32Value`, …) are Swift classes in
  `Bridge/BSONTypes.swift` instead of Objective-C ones; upstream's
  `+Codable.swift` files for them are used unchanged, except that
  `Codable/Blob+Codable.swift` imports Foundation (upstream gets `Data` through
  its Objective-C module).
- `Helper/PipelineHelper.swift` reads `FieldValue.methodName` instead of using
  key-value coding (`firebase-swift:` comment).
- `Stages.swift` passes `Int(limit)` and `Int(offset)` where upstream uses
  `NSInteger(…)`.

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
  target; upstream does that itself since 0.20250512.)
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
