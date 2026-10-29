# Emulator integration tests

The `FirebaseIntegrationTests` target (`Tests/FirebaseIntegrationTests`) runs
Auth, Database, Firestore and Storage against the
[Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite).
Each suite is skipped unless its emulators' environment variables
(`FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_DATABASE_EMULATOR_HOST`,
`FIRESTORE_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`) are set, so a
plain `swift test` stays offline. Functions isn't covered yet: its emulator
needs deployed callable functions.

## Running them

You need Java 21 or later and Node 20 or later, then:

```sh
npm install -g firebase-tools
swift build --build-tests
firebase emulators:exec --project demo-firebase-swift --only auth,database,firestore,storage \
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
  Ports: auth 9099, firestore 8080, database 9000, storage 9199.
- `firestore.rules`: everything under `public/` is open; `users/{uid}/**` is
  readable and writable only by that signed-in user, so the tests can check
  which user's token Firestore sends.
- `database.rules.json`, `storage.rules`: the same split for Database and
  Storage. Database also indexes `score` under `public/<scratch>/` for the
  query tests.

Each test creates its own `FirebaseApp` (`EmulatorApp` in
`Support/EmulatorSupport.swift`) and writes under a random `public/<uuid>/`
path, so tests can run in parallel against the same emulators.
