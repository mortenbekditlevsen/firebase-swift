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

## Concurrency model

See [Docs/Concurrency.md](Docs/Concurrency.md).

## Status

| Module | Build | Tests | Production |
|---|---|---|---|
| FirebaseAuth | ✅ | ✅ partial | email/password verified |
| FirebaseDatabase | ✅ | 🚧 | partial |
