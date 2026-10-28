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

`src/api/firestore_bridge.cc` and `include/FirestoreBridge.h` are ours (the
Swift bridge), not upstream code.

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

- **abseil-cpp-SwiftPM:** use the `mortenbekditlevsen/abseil-cpp-SwiftPM`
  branch `linux-fixes-0.20240722.2`, which is upstream tag `0.20240722.2`
  (the version firebase-ios-sdk 12.19 pins) plus two Linux fixes:
  1. The `.inc` fragments, `flag_benchmark.lds` and `abseil.podspec.gen.py`
     are excluded from the target. SwiftPM on Linux tries to compile every
     file it doesn't recognize. Upstream abseil-cpp-SwiftPM `0.20250512.1` and
     later already exclude these.
  2. `absl/numeric/int128.h` includes `int128_*_intrinsic.inc` inside
     `namespace absl`. On Linux, SwiftPM passes abseil's generated umbrella
     module map to every dependent C++ compile, so Clang treats those includes
     as nested module imports (`-Wmodules-import-nested-redundant`, an error
     by default). The includes are wrapped in a `#pragma clang diagnostic`.
- **C++ standard:** `Package.swift` sets `cxxLanguageStandard: .gnucxx14`,
  as upstream 12.19 does. Abseil defines its own `absl::string_view` below
  C++17, so if Firestore and abseil disagree on the standard, Linux fails at
  link time with undefined `absl::…(std::basic_string_view…)` symbols. When
  moving to abseil `0.20250512` (C++17), raise this together with gRPC.
- **libc++** is linked on Apple platforms only. Linux uses libstdc++.
- **leveldb:** `mortenbekditlevsen/leveldb`, branch `1.22.2-headerfix`
  (includes the `F_FULLFSYNC` fix needed on Linux).
