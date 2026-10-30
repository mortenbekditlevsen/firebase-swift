# Emulator integration tests

The `FirebaseIntegrationTests` target (`Tests/FirebaseIntegrationTests`) runs
Auth, Database, Firestore, Functions and Storage against the
[Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite).
Each suite is skipped unless its emulators' environment variables
(`FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_DATABASE_EMULATOR_HOST`,
`FIRESTORE_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`) are set, so a
plain `swift test` stays offline. `emulators:exec` sets no variable for
Functions, so its tests ask the emulator hub (`FIREBASE_EMULATOR_HUB`) where
the Functions emulator runs; `FUNCTIONS_EMULATOR_HOST` overrides that.

## Running them

You need Java 21 or later, Node 20 or later and a recent firebase-tools
(15.34 works; 15.17 and older can drop the Storage emulator's security rules
replies when several arrive at once, which hangs the Storage uploads that
needed them). Then:

```sh
npm install -g firebase-tools
npm ci --prefix Tests/Emulator/functions
swift build --build-tests
firebase emulators:exec --project demo-firebase-swift --only auth,database,firestore,functions,storage \
  "swift test --skip-build --filter IntegrationTests"
```

`emulators:exec` starts the emulators, sets the environment variables, runs the
command and shuts everything down again. The `demo-` project prefix keeps the
emulators from contacting any real Firebase project.

On macOS with Homebrew, `brew install openjdk@21` and put it first on the path:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH
```

On Linux, the `swift:6.2` image needs `openjdk-21-jre-headless` and a Node
install.

## Configuration

- `firebase.json` (repository root): emulator ports. The UI is disabled.
  Ports: auth 9099, firestore 8080, database 9000, storage 9199, functions 5001.
- `functions/`: the callable functions the Functions tests call. `index.js` is
  upstream's `FirebaseFunctions/Backend/index.js` plus `authTest`, which
  returns the caller's uid, and `slowTest`, which answers after 2.5 s for the
  timeout tests.
- `firestore.rules`: everything under `public/` is open; `users/{uid}/**` is
  readable and writable only by that signed-in user, so the tests can check
  which user's token Firestore sends.
- `database.rules.json`, `storage.rules`: the same split for Database and
  Storage. Database also indexes `score` under `public/<scratch>/` for the
  query tests.

Each test creates its own `FirebaseApp` (`EmulatorApp` in
`Support/EmulatorSupport.swift`) and writes under a random `public/<uuid>/`
path, so tests can run in parallel against the same emulators.
