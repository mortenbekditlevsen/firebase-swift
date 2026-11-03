# firebase-swift

A pure-Swift, cross-platform port of selected Firebase SDKs.
Targets iOS, macOS, Linux, Windows, and Android.

This is a **complete replacement** for the official Firebase Apple
SDK in the apps that use it; the two cannot be used in the same
target.

## Modules

- `FirebaseCoreSwift` — minimal `FirebaseApp` for cross-platform use.
- `FirebaseAuth` — Firebase Authentication (email/password, anonymous,
  custom token, listeners). Browser-based providers (OAuth, etc.) are
  not yet implemented.
- `FirebaseDatabase` — Realtime Database. Work in progress.

## Android

Build with the [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
(`swift build --swift-sdk aarch64-unknown-linux-android28`). Native code can't
look up an app's storage directories, so before using Firebase, set
`XDG_DATA_HOME` to the app's files directory (`Context.getFilesDir()`), where
Auth keeps the signed-in user and Firestore its cache, and `TMPDIR` to its
cache directory (`Context.getCacheDir()`).

## Concurrency model

See [Docs/Concurrency.md](Docs/Concurrency.md).

## Status

| Module | Build | Tests | Production |
|---|---|---|---|
| FirebaseAuth | ✅ | ✅ partial | email/password verified |
| FirebaseDatabase | ✅ | 🚧 | partial |
