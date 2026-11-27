# Firestore: performance

How fast the port reads Firestore documents, compared with upstream
(firebase-ios-sdk 13.2.0, built from source), and where the time goes. The
benchmark is F1 in [Benchmarks](../Benchmarks/README.md#firestore): 10k
documents of `BenchItem` (ten fields: strings, numbers, a bool and an array,
as the Database's S3 decodes), written with the network disabled and read
back from the in-memory cache, so neither a server nor the disk is involved.

## Reading 10k documents

`Benchmarks/results/e7f8fd85-firestore-20261127-104214.jsonl`, medians of
20, port and upstream in turns:

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
- **The port already decodes twice as fast as upstream**, because its
  `[String: Any]` holds Swift values, which the decoder casts more cheaply
  than upstream's bridged `NSDictionary` and `NSNumber`.
- **`data()` is slower than upstream's**: the port converts twice (the core's
  values to the bridge's C++ map, then to Swift), where upstream's
  Objective-C writes Foundation values from the core's values at once.

## Next: decoding from the core's values

The core keeps a document's fields as nanopb structs
(`google_firestore_v1_Value`: a type tag and a union; strings, bytes and map
keys as length-prefixed bytes), already in memory while the snapshot lives. A
decoder can read them in place, as `FNodeDecoder` reads the Database's nodes:
numbers straight from the union, keys compared as bytes, and strings copied
only into the fields that store them. That replaces all three steps after the
query, `F1-bridge` included. The structs have plain C layout, so this needs
no `std::span` or non-escapable types in Swift's C++ interop; the bridge lends
the root value to Swift for the duration of a closure.

F1 measures it as a new step beside `F1-data-as`. If it ends up near the
Database's ratio, reading 10k documents would go from about 160 ms (query and
decode) to about 80 ms. `data()` could take the same route to Foundation
values, skipping the C++ copy.

To find out along the way:

- Server timestamps that aren't set yet, which the core keeps as special maps
  and `serverTimestampBehavior` resolves, and references, which need the
  database ID, as `data()` handles them now.
- Windows, where Swift's C++ interop has had the most trouble.
