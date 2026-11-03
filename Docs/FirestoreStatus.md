# Firestore public API status

What the Swift bridge (`Sources/Firestore/Swift/Source/Bridge/`, `include/FirestoreBridge.h`,
`core/src/api/firestore_bridge.cc`) covers, compared with upstream 13.1.1's public API: the
Objective-C headers in `Sources/Firestore/Source/Public/FirebaseFirestore/` as Swift sees them,
plus `Swift/Source/`. Upstream's `Swift/Tests/API/BasicCompileTests.swift` exercises the whole
API; it should become part of `FirebaseFirestoreTests` once settings and bundles are done, with
port notes where the port is deliberately different (below).

Conventions:

- New API is async-only, like the rest of the port. Existing completion-handler forms stay
  until the port decides on Firestore's async story as a whole.
- Snapshot listeners keep their callback form (plus the `AsyncSequence` wrappers).
- Deprecated upstream API isn't ported.
- Invalid arguments stop the process with upstream's message, as upstream does by raising an
  exception. User data is validated by `UserDataParser` in `firestore_bridge.cc`, a port of
  upstream's `FSTUserDataReader`; queries are validated by the core.

Order of work (roadmap M3b): errors → settings → field paths and queries → writes →
aggregations → listeners → bundles → BSON types → pipelines.

## Errors

- [x] `FirestoreErrorDomain`, `FirestoreErrorCode` (`.Code`, `code`, `case FirestoreErrorCode.x:`
      matching), from the core's status codes

## Firestore

- [x] `firestore()`, `firestore(app:)`, `firestore(app:database:)`, `firestore(database:)`, `app`
- [x] `collection(_:)`, `document(_:)`, `collectionGroup(_:)`, `batch()`
- [x] `useEmulator(withHost:port:)`
- [x] `terminate()` (also drops the instance, so `firestore(app:)` returns a new one, as
      upstream; it used to return the terminated one), `clearPersistence()`, `waitForPendingWrites()`, `enableNetwork()`,
      `disableNetwork()` (async)
- [x] `runTransaction(_:)`, `runTransaction(with: TransactionOptions, block:)`, throwing or
      `NSErrorPointer` (Apple only) update blocks, completion and async forms
- [x] `addSnapshotsInSyncListener(_:)`
- [ ] `loadBundle(_:)` (`Data`, `InputStream`), `LoadBundleTask`, `LoadBundleTaskProgress`,
      `LoadBundleTaskState`; today a stub that never calls back (core: `Firestore::LoadBundle`)
- [ ] `getQuery(named:)` (core: `Firestore::GetNamedQuery`)
- [ ] `persistentCacheIndexManager`, `PersistentCacheIndexManager`
- [ ] `Firestore.enableLogging(_:)`
- n/a `setIndexConfiguration` (deprecated)

## Settings

- [x] `host`, `isSSLEnabled`, `==`/`hash`
- [x] `cacheSettings`: `PersistentCacheSettings` (the default; `init(sizeBytes:)` checks the
      1 MB minimum), `MemoryCacheSettings` with `MemoryEagerGCSetting` (upstream's Swift name) or
      `MemoryLRUGCSettings`, `FirestoreCacheSizeUnlimited`
- n/a `isPersistenceEnabled`, `cacheSizeBytes` (deprecated upstream; removed)
- [x] `Firestore.settings` returns a copy and applies an assigned one in one go, only when it
      differs, as upstream; changing settings after first use stops the process (core)
- n/a `dispatchQueue` (callbacks come from the core's executor; decide later)

## References

- [x] `DocumentReference`: `firestore`, `path`, `documentID`, `parent`, `collection(_:)`,
      `setData` (overwrite, `merge:`, `mergeFields:`), `updateData` with `String` or `FieldPath`
      keys, `delete`, `getDocument(source:)`, async forms
- [x] `addSnapshotListener(_:)`, `(includeMetadataChanges:listener:)`, `(options:listener:)`
      with `SnapshotListenOptions` and `ListenSource.cache`. Listeners stay active until
      `remove()`, as upstream (they used to stop when the registration was released).
- [x] `CollectionReference`: `collectionID`, `path`, `parent`, `document()`, `document(_:)`,
      `addDocument`

## Queries

- [x] `whereField` with `String` or `FieldPath` for all operators, `whereFilter(_:)` with
      `Filter` (`andFilter`, `orFilter`)
- [x] `order(by:)` with `String` or `FieldPath`, `limit(to:)`, `limit(toLast:)`
- [x] Cursors from values (`start(at:)`, `start(after:)`, `end(at:)`, `end(before:)`, including
      document IDs) and from snapshots, with upstream's validation
- [x] `getDocuments(source:)`, listeners as for documents, `firestore`, `==`/`hash`

## Snapshots

- [x] `DocumentSnapshot`: `exists`, `reference`, `documentID`, `metadata`, `data()`,
      `data(with:)`, `get(_:)` and `subscript` with `String` or `FieldPath`,
      `get(_:serverTimestampBehavior:)`, `==`/`hash`. A field set to null reads as `NSNull`
      (it read as nil before).
- [x] `QueryDocumentSnapshot` with non-optional `data()`, from `QuerySnapshot.documents` and
      `DocumentChange.document`
- [x] `QuerySnapshot`: `query`, `documents`, `isEmpty`, `count`, `documentChanges`, `metadata`
- [x] `DocumentChange`, `SnapshotMetadata`, `ListenerRegistration`

## Writes

- [x] `WriteBatch` and `Transaction`: `setData` (all three forms), `updateData` with field paths,
      `deleteDocument`; references from another Firestore instance are rejected
- [x] `Transaction.getDocument(_:)` throws `FirestoreErrorCode`
- [x] `FieldValue`: `delete`, `serverTimestamp`, `arrayUnion`, `arrayRemove`, `increment`,
      `minimum`, `maximum`
- [x] `FieldPath(_:)`, `FieldPath.documentID()`, `==`/`hash`, upstream's validation

## Aggregations

- [x] `Query.count`, `aggregate(_:)`, `AggregateQuery` (`query`, `==`/`hash`,
      `getAggregation(source:)`, async only), `AggregateField` (`count()`, `sum(_:)`,
      `average(_:)` with `String` or `FieldPath`), `AggregateQuerySnapshot` (`query`, `count`,
      `get(_:)`; a field that wasn't requested stops the process, as upstream), `AggregateSource`
- n/a `AggregateQuerySnapshot` `==`/`hash` (upstream compares the result values; not ported)

## Values

- [x] Written: `NSNull`/nil, `Bool`, Swift integers and floating point, `NSNumber` (by its
      Objective-C type, as upstream), `String`, `Data`, `Date`, `Timestamp` (truncated to
      microseconds), `GeoPoint`, `VectorValue`, `DocumentReference` (rejected if from another
      database), arrays, maps. Anything else fails with "Unsupported type".
- [x] Read: numbers as `NSNumber`, so `as? Int`, `as? Int64` and `as? Double` all work
- [ ] `GeoPoint` is a struct here, a class upstream (keep; note in the docs)
- [ ] BSON types (13.0): `MinKey`, `MaxKey`, `RegexValue`, `Int32Value`, `BSONObjectId`,
      `BSONTimestamp`, `Decimal128Value`, `Blob`. Documents return them as their maps today, and
      their Codable files are excluded in `Package.swift`.

## Pipelines

- [ ] All of `Swift/Source/SwiftAPI/Pipeline` is wired to stubs in `Bridge/BridgeTypes.swift`
      that return empty results. Last, since the API is still in preview upstream.

## Tests

`Tests/FirebaseIntegrationTests/Firestore/`: `FirestoreIntegrationTests` (CRUD, queries,
batches, transactions, listeners), `FirestoreAuthIntegrationTests` (rules and users),
`FirestoreAPIIntegrationTests` (error codes, field paths, `mergeFields`, composite filters,
value cursors, value types, `minimum`/`maximum`, references, listener lifetime and sources,
snapshots in sync, transaction options, settings, persistent and memory caches across
`terminate()`, aggregations).
