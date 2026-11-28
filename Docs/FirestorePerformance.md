# Firestore: performance

How fast the port reads Firestore documents, compared with upstream
(firebase-ios-sdk 13.2.0, built from source), and where the time goes. The
benchmark is F1 in [Benchmarks](../Benchmarks/README.md#firestore): 10k
documents of `BenchItem` (ten fields: strings, numbers, a bool and an array,
as the Database's S3 decodes), written with the network disabled and read
back from the in-memory cache, so neither a server nor the disk is involved.

## Where the time went

Before the decoder below, `Benchmarks/results/e7f8fd85-firestore-20261127-104214.jsonl`,
medians of 20, port and upstream in turns:

| Step | Port | Upstream | Port vs upstream |
|---|---:|---:|---:|
| Query from the cache (`F1-query`) | 59 ms | 61 ms | same |
| `data()` (`F1-data`) | 18 ms | 13 ms | 1.4× slower |
| `data(as: BenchItem.self)` (`F1-data-as`) | **100 ms** | 176 ms | 1.8× faster |

The query is the C++ core's work, which the two share: running the query on
the cache and building the snapshot. Everything after it is per document, so
it's the steps in between that differ:

| Per 10k documents | Port | Upstream |
|---|---:|---:|
| The core's values to a C++ `BridgeFieldValue` map (`F1-bridge`) | 7 ms | – |
| … to `[String: Any]` | 11 ms | 13 ms (to `NSDictionary`, in Objective-C) |
| `Firestore.Decoder` from there to `BenchItem` | **82 ms** | 163 ms |

- **Decoding costs more than the query itself.** Reading the documents
  into a type takes 100 ms, of which the core's work is none: 7 ms copying
  values out of the core, 11 ms making Foundation values of them, and 82 ms
  decoding those, which is `FirebaseDataDecoder` boxing and casting each
  value. That's the Database's picture before `FNodeDecoder` (P5), which
  decodes from its nodes directly and is about 4× faster than decoding
  Foundation values.
- **The port already decoded twice as fast as upstream**, because its
  `[String: Any]` holds Swift values, which the decoder casts more cheaply
  than upstream's bridged `NSDictionary` and `NSNumber`.
- **`data()` was slower than upstream's**: the port converted twice (the
  core's values to the bridge's C++ map, then to Swift), where upstream's
  Objective-C writes Foundation values from the core's values at once. It
  no longer does (below).

## Decoding from the core's values

The core keeps a document's fields as nanopb structs
(`google_firestore_v1_Value`: a type tag and a union; strings, bytes and map
keys as length-prefixed bytes), in memory while the snapshot lives.
`data(as:)` now reads them in place (`FirestoreValueDecoder`), as the
Database's `FNodeDecoder` reads its nodes: numbers straight from the union,
keys compared as bytes, strings copied only into the fields that store them.
The bridge hands Swift the document's fields as opaque references, with
accessors for each kind (`include/FirestoreBridge.h`); the structs have plain
C layout, so this needs no `std::span` or non-escapable types.

It reads nulls, booleans, numbers, strings, maps and arrays in place. Every
other value (timestamps, references, geo points, blobs, vectors, the BSON
types, server timestamps not set yet), and every combination whose result
could depend on how `FirebaseDataDecoder` treats Foundation values (an
integer as a `Bool`, a double as an `Int`, a `Date`, `Data`, `URL`, `Decimal`,
`Float`), goes through `FirebaseDataDecoder` as before, one value at a time.
So it decodes as before on every platform, errors included:
`FirestoreValueDecoderTests` decodes every kind of value against 45 types,
with each server timestamp behavior and the decoder's strategies, both ways,
and expects the same values and errors.

`Benchmarks/results/55afe079-dirty-firestore-20261127-110647.jsonl`, 10k
documents, medians of 20:

| | Port before | **Port now** | Upstream |
|---|---:|---:|---:|
| `data(as: BenchItem.self)` | 99.5 ms | **17.4 ms** | 179 ms |
| Query and `data(as:)` | 159 ms | **77 ms** | 240 ms |

## Firestore's own types

Timestamps, geo points and references are read in place too, both by
`data()` and when decoded as `Timestamp`, `GeoPoint` and `DocumentReference`.
A `Date` with a custom strategy, which the default `.timestamp` is, decodes
with that strategy, in place: `.timestamp` decodes a `Timestamp` and returns
its date. Other date strategies, and blobs, vectors, the BSON types and server
timestamps not set yet, still go through `FirebaseDataDecoder` one value at a
time. `FirestoreValueDecoderTests` compares both ways with a custom date
strategy too.

F1-typed: 10k documents of a name and four of Firestore's types (a
`Timestamp`, a `Date` stored as one, a `GeoPoint`, a `DocumentReference`),
medians of 20. Before:
`Benchmarks/results/64088775-firestore-20261128-102438.jsonl`; after:
`Benchmarks/results/64088775-dirty-firestore-20261128-103242.jsonl`, on a
machine about 15% slower overall (the query took 68 ms instead of 59, for
both SDKs), so the ratios to upstream compare best:

| | Before | **Now** | Upstream (before / now) |
|---|---:|---:|---:|
| `data(as: TypedItem.self)` | 27.6 ms (0.45×) | **16.2 ms (0.23×)** | 61.9 / 70.6 ms |
| `data()` | 5.6 ms (0.60×) | **6.0 ms (0.56×)** | 9.3 / 10.8 ms |

## `data()` from the core's values

`data()` makes its `[String: Any]` the same way (`DocumentFields`): nulls,
booleans, numbers, strings, maps and arrays from the core's values in place,
and every other value converted as before, one at a time, instead of copying
the whole document into the bridge's C++ map first. `DocumentFieldsTests`
compares the result with the old conversion's, value for value and type for
type (an `NSNumber` of an integer isn't one of a double), for every kind of
value, nested ones and server timestamps included.

`Benchmarks/results/a681a605-dirty-firestore-20261128-102205.jsonl`, 10k
documents, medians of 20:

| | Port before | **Port now** | Upstream |
|---|---:|---:|---:|
| `data()` | 18 ms | **5.7 ms** | 12.7 ms |

## Open

- **Decoding a non-finite number as `Decimal` stops the process**, on both
  paths (and probably upstream, whose `FirebaseDataDecoder` has the same
  code): it makes a `Decimal` of the `Double`, and Foundation traps on
  infinity and NaN. It should throw `dataCorrupted`.
- **Writing** (`setData(from:)`) still encodes to `[String: Any]` first.
