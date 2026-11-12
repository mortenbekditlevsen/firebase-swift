# firebase-swift

A Swift port of the [Firebase Apple SDK](https://github.com/firebase/firebase-ios-sdk)
(release 13.1.1) that runs on Apple platforms, Linux and Android. There is no
Objective-C: Auth, Database, Functions, Storage and App Check are written in
Swift, and Firestore wraps upstream's C++ core through Swift's C++
interoperability.

It **replaces** the official SDK, so an app can't use both in the same target.
Nothing has been released yet, and the API can still change.

## Modules

| Product | What's there |
|---|---|
| `FirebaseAppCheck` | `AppCheck` with the debug provider everywhere, and DeviceCheck and App Attest on Apple platforms; tokens for the other SDKs ([setup](#app-check)) |
| `FirebaseCore` | `FirebaseApp` (default and named apps, `delete()`), `FirebaseOptions` from `GoogleService-Info.plist`, `google-services.json` or a web app's config |
| `FirebaseAuth` | Email and password, email links, anonymous, custom tokens, and credentials from Google, Apple, Facebook, GitHub, Twitter, Game Center and other OAuth providers. Also multi-factor auth (phone and TOTP), user management, and listeners. Phone auth and web-based sign-in (`OAuthProvider`) need iOS. |
| `FirebaseDatabase` | Realtime Database: reads, writes, listeners, queries, transactions, `onDisconnect`, offline persistence |
| `FirebaseFirestore` | Upstream's C++ core with the Swift API: documents, queries, listeners, batches, transactions, aggregations, bundles, cache settings, `Codable`, vector and BSON values, pipelines (including realtime pipelines and window functions) ([status](Docs/FirestoreStatus.md)). |
| `FirebaseFunctions` | Callable functions, including `Codable` and streaming calls |
| `FirebaseStorage` | Uploads, downloads, listing, metadata |

Analytics, Messaging, Remote Config and the other SDKs aren't ported.

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
  ], swiftSettings: [
    // Only for FirebaseFirestore, which wraps upstream's C++ core.
    .interoperabilityMode(.Cxx),
  ]),
]
```

Targets that import `FirebaseFirestore` need Swift's C++ interoperability.
The other modules don't.

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

## App Check

Set a provider factory before configuring the app, as upstream requires. The
other SDKs then send App Check tokens with their requests.

```swift
import FirebaseAppCheck

AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
FirebaseApp.configure()
```

App Check keeps its token (and App Attest's key artifact) between launches.
On Apple platforms it uses the keychain, as upstream does
(`AppCheckSystemKeychain`): the items are upstream's, so tokens survive a
switch from the official SDK. Processes that can't use the data protection
keychain, such as unsigned command line tools on macOS, keep them in memory
instead (upstream fails to get tokens there).

Elsewhere, or to store them somewhere else, pass your own `AppCheckKeychain`,
three async methods that get, set and remove `Data` by service, key and
access group, backed by libsecret or a protected file on Linux, or memory if
you don't need tokens to outlive the process:

```swift
AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory(), keychain: MyKeychain())
```

Upstream also sets a default factory when the module loads; here App Check
is off until you call `setAppCheckProviderFactory`.

## Realtime Database

Reading is iterating: `values()` gives the data now and after each change,
`childEvents()` the changes to the children, and `firstValue()` the current
data (from the cache if there is some). Listening starts when the iteration
does and stops when it ends, so a task's lifetime is the listener's:

```swift
let ref = Database.database().reference().child("rooms/lobby")

for try await snapshot in ref.child("topic").values() {
  print(snapshot.value as? String ?? "")
}

for try await event in ref.child("messages").queryLimitedToLast(50).childEvents([.added, .removed]) {
  print(event.kind, event.snapshot.key ?? "")
}
```

A sequence throws if the client loses permission to read. For a UI that only
needs the latest data, `values(bufferingPolicy: .bufferingNewest(1))` skips the
ones it doesn't get to.

Each write has two forms. The plain one applies the write locally (its events
are raised at once) and queues it for the server; the `…AndWait` form also
returns once the server acknowledged it, and throws if it was rejected, so it
waits while offline. Either way, calls take effect in the order they're made.

```swift
ref.child("topic").setValue("Swift")                    // fire and forget
try await ref.child("topic").setValueAndWait("Swift")   // until the server has it
ref.child("presence/me").onDisconnect.setValue(false)

let (committed, snapshot) = try await ref.child("likes").runTransaction { data in
  data.value = ((data.value as? Int) ?? 0) + 1
  return .success(withValue: data)
}
```

### Codable

The `as:` forms decode the data as a `Decodable` type, and `setValue(from:)`
encodes an `Encodable` one, with `Database.Decoder` and `Database.Encoder`
and their strategies. They work on the database's own data, without making
the Foundation values `snapshot.value` has, and the sequences decode neither
on the database's actor nor on yours:

```swift
struct Message: Codable, Sendable {
  var text: String
  var sender: String
}

let messages = ref.child("messages")
for try await event in messages.queryLimitedToLast(50).childEvents(as: Message.self, [.added]) {
  print(event.key, event.value.text)
}
try messages.childByAutoId().setValue(from: Message(text: "Hi", sender: "me"))

let likes = try await ref.child("likes").runTransaction(as: Int.self) { likes in
  likes = (likes ?? 0) + 1
}
```

`Database.Encoder` and `Database.Decoder` are upstream's `FirebaseDataEncoder`
and `FirebaseDataDecoder`, and here they only supply the settings. Decoding
`snapshot.value` with one yourself goes through Foundation values again.

A sequence throws if the data doesn't decode; a typed transaction is aborted,
and rethrows, if its closure throws. Data the database can't store, such as
keys with `.#$[]/` or NaN, makes `setValue(from:)` throw (upstream stops the
program). Unlike upstream, data whose keys are small integers ("0", "1", …)
decodes as a dictionary or struct too, not only as an array.

### Migrating from the upstream API

There are no callbacks or observer handles:

| Upstream | Here |
|---|---|
| `observe(.value) { … }`, `removeObserver(withHandle:)` | `for try await snapshot in ref.values() { … }`; end the loop or cancel its task |
| `observe(.childAdded/.childChanged/.childRemoved/.childMoved)` | `childEvents(_:)` with `ChildEvent { kind, snapshot, previousSiblingKey }` |
| `withCancel:` | the sequence throws |
| `observeSingleEvent(of: .value)` | `firstValue()` (`getData()` asks the server first) |
| `removeAllObservers()` | end the iterations |
| `setValue(_:)`, `updateChildValues(_:)`, `removeValue()`, `setPriority(_:)` | unchanged: queued, without waiting |
| `try await setValue(_:)` and the other completion-block forms | `try await setValueAndWait(_:)`, `updateChildValuesAndWait(_:)`, `removeValueAndWait()`, `setPriorityAndWait(_:)` |
| `onDisconnectSetValue(_:)`, `onDisconnectUpdateChildValues(_:)`, `onDisconnectRemoveValue()`, `cancelDisconnectOperations()` | `onDisconnect.setValue(_:)`, `.updateChildValues(_:)`, `.removeValue()`, `.cancel()`, each also as `…AndWait` |
| `runTransactionBlock(_:)`, `runTransactionBlock(_:andCompletionBlock:withLocalEvents:)` | `try await runTransaction(applyLocally:_:)` → `(committed, snapshot)` |
| `setValue(from:)` async | `setValueAndWait(from:)` |
| `observe(.value)` + `snapshot.data(as:)` | `values(as:)`, `childEvents(as:)` |
| `runTransactionBlock` on a Codable value | `runTransaction(as:)` with `inout T?` |

> **Watch out:** `try await ref.setValue(x)` still compiles, as a call to the
> plain form, with only "no async operations occur within 'await'" and "no
> calls to throwing functions occur within 'try'" warnings. It no longer
> waits for the server or throws. Use `setValueAndWait(x)`.

### Connections

Realtime Database talks to its server over a WebSocket, opened by a
`DatabaseTransport`. There are three:

- `NIODatabaseTransport`: SwiftNIO on POSIX sockets, with swift-nio-ssl. The
  default, except on watchOS.
- `NIOTSDatabaseTransport` (Apple platforms): SwiftNIO on Network.framework,
  with the system's TLS. When the system finds a better network path (Wi-Fi
  after cellular), it reconnects on it.
- `URLSessionDatabaseTransport` (Apple platforms): the default on watchOS.

Whichever it is, the client reconnects with a backoff when a connection
fails, at once when the network changes or the app returns to the
foreground, and checks a connection that may have died meanwhile. Set
another transport before using the database:

```swift
let database = Database.database()
database.transport = URLSessionDatabaseTransport()
```

To bring your own WebSocket client, conform to `DatabaseTransport`: connect
in `withConnection(to:isolation:_:)`, hand the body a connection with the
server's text messages (`inbound`) and a `send` method, and close it when the
body returns. Connecting must throw on failure, `inbound` must end when the
connection does, and cancellation must close the connection.

## Differences from the upstream SDK

- **Async only.** Methods that take a completion handler upstream are
  `async` here (for Realtime Database, see [its section](#realtime-database)). There's no Combine support and no Objective-C API.
- **Concurrency.** The public types are `Sendable`; see
  [Docs/Concurrency.md](Docs/Concurrency.md) (Auth) and
  [Docs/DatabaseConcurrency.md](Docs/DatabaseConcurrency.md) (Realtime Database).
- **Performance.** Realtime Database loads, decodes and reads its cache several
  times faster than upstream, with about the same memory; see
  [Docs/DatabasePerformance.md](Docs/DatabasePerformance.md).
- **Value types.** Some upstream classes are value types here, among them
  `FirebaseOptions`, Database's `MutableData` and Firestore's `GeoPoint`. A
  copy, such as `FirebaseApp.options`, can't change the original.
- **No swizzling.** On iOS, phone auth needs the app to hand Auth its APNs
  token (`setAPNSToken(_:type:)`), remote notifications
  (`canHandleNotification(_:)`) and opened URLs (`canHandle(_:)`).
- **Auth is created on first use.** Upstream creates Auth when the app is
  configured; here the first `Auth.auth()` does. The other SDKs pick up its
  user whenever that happens, so the order doesn't matter.
- **Not ported:** the data collection flag and heartbeats.

## Android

Build with the [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
(`swift build --swift-sdk aarch64-unknown-linux-android28`). Native code can't
look up an app's storage directories, so set these before using Firebase:

- `XDG_DATA_HOME` to the app's files directory (`Context.getFilesDir()`). Auth
  keeps the signed-in user there, and Firestore and Realtime Database their
  caches.
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
