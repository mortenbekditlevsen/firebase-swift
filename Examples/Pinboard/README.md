# Pinboard

A shared board of notes, built with [SwiftCrossUI](https://swiftcrossui.dev)
on firebase-swift. People sign in, pin short notes, attach files, and see who
else is on the board.

| Module | What Pinboard does with it |
|---|---|
| **Auth** | Email and password, or a guest (anonymous) with a name |
| **Firestore** | The notes: a live query, newest first; deleting your own |
| **Functions** | `pinNote` (callable) checks a note and adds it; `describeAttachment` (Storage trigger) records an upload on its note |
| **Storage** | Attachments: uploaded with progress, shown (images), saved |
| **Realtime Database** | Who's here, and who's typing: presence with `.info/connected` and `onDisconnect` |

## Run it on the emulators (no Firebase project needed)

You need Swift 6.2 or later, Java 21 or later, Node 22 and the Firebase CLI
(`npm install -g firebase-tools`). On Linux, also GTK 4 (`libgtk-4-dev`).

The emulators use the first `java` on your `PATH`. If they stop with
"firebase-tools no longer supports Java version before 21", install a newer
JDK (e.g. `brew install openjdk@21`) or point your shell at one you have:

```sh
export JAVA_HOME=$(/usr/libexec/java_home -v 21+)   # macOS
export PATH="$JAVA_HOME/bin:$PATH"
```

```sh
cd Examples/Pinboard
npm install --prefix functions
firebase emulators:exec "PINBOARD_EMULATORS=1 swift run Pinboard"
```

The emulators use the `demo-pinboard` project, which needs no account. To try
presence with more than one person, start the emulators in one terminal and
the app in as many others as you like:

```sh
firebase emulators:start                       # terminal 1; UI at http://127.0.0.1:4000
PINBOARD_EMULATORS=1 swift run Pinboard        # terminals 2, 3, …
```

`PINBOARD_EMULATORS` can also be the emulators' host, e.g. a Mac on your
network or the host of a Linux container. Then start the emulators listening
on every interface (`"host": "0.0.0.0"` in `firebase.json`). The app lets
Storage and Functions send tokens over plain HTTP to that host, which they
otherwise only do to `localhost`.

`pinboard-check` runs the app's flow without a window: it signs in, shows up
as present and typing, pins a note with an attachment, downloads it, deletes
the note and signs out. It exits with 1 if a step fails:

```sh
firebase emulators:exec "PINBOARD_EMULATORS=1 swift run pinboard-check"
```

## Run it on your own Firebase project

1. Create a project in the [Firebase console](https://console.firebase.google.com)
   (Functions and Storage need the Blaze plan).
2. In the console:
   - Turn on **Email/Password** and **Anonymous** sign-in (Authentication).
   - Create a Firestore database, a Realtime Database and a Storage bucket.
3. Deploy the rules and functions from this folder:

   ```sh
   firebase use --add          # pick your project
   firebase deploy
   ```

4. Register a **web app** in the project settings: the console has no
   desktop platforms. Save its `firebaseConfig` object as JSON, e.g.
   `pinboard.json`.
5. Run the app with those options:

   ```sh
   FIREBASE_OPTIONS=pinboard.json swift run Pinboard
   ```

## How it's put together

- `Sources/PinboardKit/Board.swift` is everything Pinboard does with
  Firebase: a `@MainActor @Observable` model that the UI reads. It follows the
  signed-in user, and listens to the notes and to who's here for as long as
  someone is signed in.
- `Sources/PinboardKit/FirebaseSetup.swift` reads the options, or points every
  SDK at the emulators.
- `Sources/Pinboard/` is the SwiftCrossUI app: `SignInView`, and `BoardView`
  with the composer, the notes and who's here.
- `Sources/pinboard-check/` is the check.
- `functions/index.js` is `pinNote` and `describeAttachment`.
- `firestore.rules`, `database.rules.json` and `storage.rules` let signed-in
  people read; only functions write notes, and only you write your presence
  and your attachments.

`FirebaseFirestore` wraps upstream's C++ core, so the targets that import it
(here all of them) need `.interoperabilityMode(.Cxx)`.

## Known issue: gRPC's copy of zlib

grpc-ios compiles its own copy of zlib into `gRPC-Core`, and SwiftCrossUI's
image support links the `zlib` package, so the app fails to link with
duplicate zlib symbols (on macOS and Linux). gRPC doesn't need its copy: it
includes `<zlib.h>` and links the system's `libz`. Until firebase-swift
depends on a grpc-ios without it, point this package at one:

```sh
git clone https://github.com/grpc/grpc-ios.git /tmp/grpc-ios
# In /tmp/grpc-ios/Package.swift, add "third_party/zlib" to gRPC-Core's exclude list,
# and check out the revision in Package.resolved first.
swift package edit grpc-ios --path /tmp/grpc-ios
```

## Known issue: bordered buttons on macOS 26 and later

SwiftCrossUI 0.10's AppKit backend adds a bordered button's bezel after its
label, so on macOS 26 and later the bezel hides the title until the button is
pressed. Pinboard's buttons are borderless instead (`ActionButton`).

## To do

- Windows: SwiftCrossUI has a WinUI backend; the app and firebase-swift
  haven't been built there yet.
- CI: build the app on macOS and Linux, and run `pinboard-check` on the
  emulators.
