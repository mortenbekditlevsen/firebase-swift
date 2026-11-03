# firebase-swift

A Swift port of the [Firebase Apple SDK](https://github.com/firebase/firebase-ios-sdk)
(release 13.1.1) that runs on Apple platforms, Linux and Android. There is no
Objective-C: Auth, Database, Functions and Storage are written in Swift, and
Firestore wraps upstream's C++ core through Swift's C++ interoperability.

It **replaces** the official SDK, so an app can't use both in the same target.
Nothing has been released yet, and the API can still change.

## Modules

| Product | What's there |
|---|---|
| `FirebaseCore` | `FirebaseApp` (default and named apps, `delete()`), `FirebaseOptions` from `GoogleService-Info.plist`, `google-services.json` or a web app's config |
| `FirebaseAuth` | Email and password, email links, anonymous, custom tokens, and credentials from Google, Apple, Facebook, GitHub, Twitter, Game Center and other OAuth providers. Also multi-factor auth (phone and TOTP), user management, and listeners. Phone auth and web-based sign-in (`OAuthProvider`) need iOS. |
| `FirebaseDatabase` | Realtime Database: reads, writes, listeners, queries, transactions, `onDisconnect`, offline persistence |
| `FirebaseFirestore` | Upstream's C++ core with the Swift API: documents, queries, listeners, batches, transactions, aggregations, bundles, cache settings, `Codable`, vector and BSON values. Pipelines are not ported yet ([status](Docs/FirestoreStatus.md)). |
| `FirebaseFunctions` | Callable functions, including `Codable` and streaming calls |
| `FirebaseStorage` | Uploads, downloads, listing, metadata |

App Check, Analytics, Messaging, Remote Config and the other SDKs aren't
ported. Until App Check is, you can give the SDKs App Check tokens from your
own provider through `FirebaseApp.appCheck`.

## Platforms

| Platform | Minimum | Checked in CI |
|---|---|---|
| macOS | 15 | build, unit and emulator tests |
| iOS | 18 | build, Simulator tests (phone auth, multi-factor, keychain) |
| tvOS, Mac Catalyst, watchOS | 18, 18, 11 | build |
| Linux | Swift 6.2 | build, unit and emulator tests |
| Android | Swift 6.3 SDK for Android, API 28 | build, unit tests on an emulator |

Windows hasn't been tried. The Apple minimums are the first releases with
the Synchronization module's `Mutex`, which the SDKs use for their state.

## Installation

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/mortenbekditlevsen/firebase-swift.git", branch: "main"),
],
targets: [
  .target(name: "MyApp", dependencies: [
    .product(name: "FirebaseAuth", package: "firebase-swift"),
    .product(name: "FirebaseFirestore", package: "firebase-swift"),
  ]),
]
```

Firestore brings gRPC, Abseil and nanopb, by far the largest dependencies. If
you don't use it, turn off the package's `Firestore` trait and SwiftPM won't
fetch them:

```swift
.package(url: "https://github.com/mortenbekditlevsen/firebase-swift.git", branch: "main",
         traits: []),
```

## Getting started

Configure the default app once, when your program starts:

```swift
import FirebaseCore

FirebaseApp.configure()
```

`configure()` looks for the app's options in this order:

1. The `FIREBASE_OPTIONS` environment variable: either the options as JSON, or
   the path of a file.
2. `GoogleService-Info.plist` in the main bundle, as upstream does.

You can also read a file yourself, or fill in `FirebaseOptions` in code:

```swift
let options = FirebaseOptions(contentsOfFile: "/etc/my-service/firebase.json")!
FirebaseApp.configure(options: options)
```

The options can come from any of the files the Firebase console gives you:

- `GoogleService-Info.plist` from an Apple app.
- `google-services.json` from an Android app.
- The `firebaseConfig` object from a web app, saved as JSON.

The console has no Linux platform, so register a Linux program as a web app.

The API is the upstream SDK's Swift API, with `async` methods only:

```swift
import FirebaseAuth
import FirebaseFirestore

let user = try await Auth.auth().signIn(withEmail: email, password: password).user
let cities = try await Firestore.firestore().collection("cities")
  .whereField("country", isEqualTo: "DK")
  .getDocuments()
```

## Differences from the upstream SDK

- **Async only.** Methods that take a completion handler upstream are
  `async` here. There's no Combine support and no Objective-C API.
- **Concurrency.** The public types are `Sendable`; see
  [Docs/Concurrency.md](Docs/Concurrency.md).
- **Value types.** Some upstream classes are value types here, among them
  `FirebaseOptions`, Database's `MutableData` and Firestore's `GeoPoint`. A
  copy, such as `FirebaseApp.options`, can't change the original.
- **No swizzling.** On iOS, phone auth needs the app to hand Auth its APNs
  token (`setAPNSToken(_:type:)`), remote notifications
  (`canHandleNotification(_:)`) and opened URLs (`canHandle(_:)`).
- **Auth is created on first use.** Upstream creates Auth when the app is
  configured; here the first `Auth.auth()` does. The other SDKs pick up its
  user whenever that happens, so the order doesn't matter.
- **Not ported:** the data collection flag, heartbeats, and limited-use App
  Check tokens.

## Android

Build with the [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
(`swift build --swift-sdk aarch64-unknown-linux-android28`). Native code can't
look up an app's storage directories, so set these before using Firebase:

- `XDG_DATA_HOME` to the app's files directory (`Context.getFilesDir()`). Auth
  keeps the signed-in user there, and Firestore its cache.
- `TMPDIR` to the app's cache directory (`Context.getCacheDir()`).

`google-services.json` is compiled into Android resources and can't be read as
a file at run time. Pass its contents in `FIREBASE_OPTIONS`, or copy it to the
files directory and use `FirebaseOptions(contentsOfFile:)`.

## Tests

- **Unit tests:** `swift test` runs them, with no network.
- **Integration tests:** they run against the Firebase Emulator Suite. See
  [Tests/Emulator/README.md](Tests/Emulator/README.md).
- **Upstream's tests:** upstream's unit and integration tests are ported where
  they apply. Changes to them are marked "Port note".

## Keeping up with upstream

- [UPSTREAM.md](UPSTREAM.md) records which upstream release each module is
  synced to, and how to bring in later upstream changes.
- [Docs/UpstreamPatches.md](Docs/UpstreamPatches.md) lists the changes made to
  the vendored Firestore core.
- [Docs/FirestoreStatus.md](Docs/FirestoreStatus.md) tracks Firestore's
  public API.

## License

Apache 2.0, like the upstream SDK. See [LICENSE](LICENSE).
