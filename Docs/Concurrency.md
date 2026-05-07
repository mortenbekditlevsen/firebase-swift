# FirebaseAuth Concurrency Model (Swift port)

This document describes the concurrency model used by the Swift port of
FirebaseAuth. The original ObjC library was structured around a serial
`dispatch_queue` (`kAuthGlobalWorkQueue`) that protected mutable state on the
`FIRAuth` object. The original `threading.md` file in this directory captures
that model. This document describes what replaces it.

## Goal

Make `Auth` thread-safe and `Sendable`, without requiring callers (or call
sites inside the SDK) to be `@MainActor`. This unblocks Android, Linux, and
Windows targets where `@MainActor` is awkward and where `DispatchQueue.main`
is not always the right callback context.

## Summary

* `Auth` is a `final class` declared `@unchecked Sendable`.
* All mutable state lives in a single `Mutex<State>` (from `Synchronization`,
  Swift 6.0 / iOS 18+).
* Public scalar properties (`currentUser`, `languageCode`, `tenantID`, …) are
  computed: each access takes the lock for one quick read or write.
* Compound mutations (sign-in, sign-out, access-group switching, token-refresh
  bookkeeping) call private helpers shaped like
  `_foo(..., state: inout State)`. Their callers wrap the work in a single
  `_state.withLock { state in … }` block.
* Async I/O (network, keychain) does **not** hold the lock. The pattern is:

    1. Snapshot the state you need under the lock.
    2. Do the I/O.
    3. Re-acquire the lock and commit the result.

* The `Mutex` is non-reentrant. Code inside `withLock` must not call back into
  any method that would re-enter `withLock` on the same instance. Helpers that
  need state should accept `inout State` instead.

## Listener invocations

* Listener callbacks (`addStateDidChangeListener`,
  `addIDTokenDidChangeListener`) are typed as
  `@escaping @Sendable (Auth, User?) -> Void`. They have **no actor isolation**.
* Callbacks are invoked **outside** the lock. Internally we post to
  `NotificationCenter.default` via `DispatchQueue.main.async`, but listeners
  must not assume they run on the main actor. Callers that need to update UI
  should hop themselves:

    ```swift
    auth.addStateDidChangeListener { auth, user in
        Task { @MainActor in
            // update UI
        }
    }
    ```

## Helpers and statics

* `AuthDispatcher`, `AuthBackend`, and `AuthBackendRPCImplementation` are
  plain `Sendable` types — no `@MainActor`. Mutable static state
  (`AuthBackend.gBackendImplementation`, `Auth.gKeychainServiceNameForAppName`,
  `AuthDispatcher.dispatchAfterImplementation`) is wrapped in `Mutex`.
* `AuthSerialTaskQueue` continues to be an `actor`. It serializes ordered
  async work (e.g. user-profile updates) and is unrelated to the state lock.

## What this replaces

The historical `kAuthGlobalWorkQueue.sync { ... }` blocks have been removed
from the Swift port. Their job — serializing access to `Auth` state — is now
done by `Mutex`. The async global queue dispatch in the original ObjC code
served two purposes (state protection AND callback scheduling); we keep state
protection here, and let async/await + listener `Sendable` typing handle the
scheduling part.

## Open items

* iOS phone-auth observers (UIApplicationDidBecomeActive,
  UIApplicationProtectedDataDidBecomeAvailable) are not yet re-ported. Tracked
  for phase 6 of the migration.
* `User` still has many `@MainActor` annotations. They don't break `Auth`
  thread-safety but should be revisited; `User`'s own state is already behind
  `Mutex<UserData>`.
