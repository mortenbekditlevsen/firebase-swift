# Firestore public API status

What the Swift bridge (`Sources/Firestore/Swift/Source/Bridge/`, `include/FirestoreBridge.h`,
`core/src/api/firestore_bridge.cc`) covers, compared with upstream 13.1.1's public API: the
Objective-C headers in `Sources/Firestore/Source/Public/FirebaseFirestore/` as Swift sees them,
plus `Swift/Source/`. Upstream's `Swift/Tests/API/BasicCompileTests.swift`, which uses the
whole API, compiles as part of `FirebaseFirestoreTests`; port notes in it mark where the port is
deliberately different (the deprecated settings; Firestore's network, persistence,
pending-writes and terminate operations, which are async only; and the `NSErrorPointer`
transaction blocks, which only exist on Apple platforms).

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
- [x] `loadBundle(_:)` with `Data` or `InputStream`, returning a `LoadBundleTask`
      (`addObserver(_:)`, `removeObserverWith(handle:)`, `removeAllObservers()`) or, async, the
      final `LoadBundleTaskProgress`; `LoadBundleTaskState`. The stream is read on the core's
      worker through a port of `ByteStreamApple` (`SwiftByteStream` in `firestore_bridge.cc`).
      The completion-handler forms are internal (upstream's async file uses them). Differences:
      the async form's observer is registered before loading starts (upstream could miss a
      fast bundle's final state), and errors carry the core's code: upstream reports every
      failure as `.unknown`, because its error check in `FIRFirestore.mm` is inverted.
- [x] `getQuery(named:)`, async only
- [x] `persistentCacheIndexManager` (nil without a persistent cache), `PersistentCacheIndexManager`
      (`enableIndexAutoCreation()`, `disableIndexAutoCreation()`, `deleteAllIndexes()`)
- [x] `Firestore.enableLogging(_:)`: debug or notice level of the core's log, which the port
      builds from `log_stdio.cc` on every platform
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
- [x] `GeoPoint` is a struct here, a class upstream; it checks the coordinate ranges as upstream
      does (decoding throws), see Docs/UpstreamPatches.md
- [x] BSON types (13.0): `MinKey`, `MaxKey`, `RegexValue`, `Int32Value`, `BSONObjectId`,
      `BSONTimestamp`, `Decimal128Value` (equal when they're the same number, as upstream),
      `Blob` (subtype 0 is plain bytes and reads back as `Data`, as upstream), written and read
      as upstream's `FSTUserDataReader`/`Writer` do, with upstream's Codable files and pass-through
      list. They need an Enterprise-edition database: the emulator, like a Standard one, refuses
      each by name, so the tests check that and round-trip them through the local cache. (A
      binary with a subtype used to be read as garbage.)

## Pipelines

- [x] `Firestore.pipeline()` and all of `Swift/Source/SwiftAPI/Pipeline` (upstream's Swift API,
      unchanged): every source and stage, expressions, aggregates, subqueries, the DML stages,
      `create(from: Query)`, and atomic execution. `Bridge/BridgeTypes.swift` has upstream's
      `__…Bridge` classes, which build the core's expressions and stages through
      `include/PipelineBridge.h` (`core/src/api/pipeline_bridge.cc`, a port of upstream's
      `FIRPipelineBridge.mm`) when a pipeline runs. A `Field` keeps its path's segments, where
      upstream re-parses the canonical string and so splits a segment that contains a dot.
- [x] Realtime pipelines (`realtimePipeline()`, internal upstream too): listeners, changes,
      metadata and listen options.
- They need an Enterprise-edition database. The emulator's Enterprise edition runs everything
  except search (`document_matches`, `geo_distance`), which it doesn't have.

## Platform notes

- On Linux, `catch let error as NSError` doesn't match the port's errors (corelibs Foundation
  only bridges Swift errors to `NSError` by coercion): use `catch FirestoreErrorCode.notFound`,
  `error as? FirestoreErrorCode`, or `let nsError = error as NSError`.
- Linux has no `NSErrorPointer`, so transactions there use the throwing update block.

## Tests

Upstream's Swift integration tests (`Swift/Tests/Integration/`) run as
`FirebaseFirestoreIntegrationTests` against the Firestore emulator, on
`Swift/Tests/IntegrationSupport/FSTIntegrationTestCase.swift`, a Swift port of upstream's
Objective-C `FSTIntegrationTestCase` and `FSTEventAccumulator`. Port notes in the test files mark
the changes: removed deprecated settings, throwing transaction blocks, a continuation instead of
Combine's `Future`, error codes the port reports differently, and two tests skipped because they
expect an exception (the port stops the process instead). Enterprise-only tests skip themselves,
as upstream's do; the BSON binary tests need firebase-tools 15.34 or later.

The pipeline tests (`Pipeline*Tests`, `QueryToPipelineTests`, `SearchIntegrationTests`) run
against the emulator's Enterprise edition (`BACKEND_EDITION=enterprise`, see
`Tests/Emulator/README.md`): 313 tests, 20 skipped. Port notes: the subquery tests, which
upstream only runs against its nightly backend, also run against the emulator, accepting its
wording of two errors; two tests that expect an exception and two that expect the backend to
refuse an unknown forced index (the emulator accepts any) are skipped; one result order the
emulator leaves open isn't checked there; and `QueryToPipelineTests` compares results in a
normalized form, as the port's arrays and dictionaries aren't hashable. The search tests stay
skipped, as upstream's. `Swift/Tests/Port/RealtimePipelineTests.swift` covers realtime
pipelines, which upstream has no Swift tests for.

They found: constants that are `Substring`s were refused (upstream gets them as `NSString`s).

They found: reading an empty `Data` field crashed (nanopb stores empty bytes as null), and
`VectorValue` and `PersistentCacheIndexManager` weren't `Equatable` as upstream's are.

Our own tests:

`Tests/FirebaseIntegrationTests/Firestore/`: `FirestoreIntegrationTests` (CRUD, queries,
batches, transactions, listeners), `FirestoreAuthIntegrationTests` (rules and users),
`FirestoreAPIIntegrationTests` (error codes, field paths, `mergeFields`, composite filters,
value cursors, value types, `minimum`/`maximum`, references, listener lifetime and sources,
snapshots in sync, transaction options, settings, persistent and memory caches across
`terminate()`, aggregations, bundles and named queries, the index manager, BSON values).
