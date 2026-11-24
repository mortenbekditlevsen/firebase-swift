# Ideas

Possible work that hasn't been decided on yet. Each one needs a design (and
for the performance ideas, measurements) before it's built.

## Realtime Database: a collection listener

A listener over a query's child events that keeps the whole result, the way
Firestore's query snapshots do:

- The children, decoded, in the query's order (where the order can be kept:
  `orderByChild`, `orderByKey`, `orderByValue`, limits).
- What changed since the last update: added, changed, moved and removed
  children with their old and new positions, like Firestore's `documents` and
  `documentChanges`.
- Decoded objects cached, so an update decodes only the children that
  changed.

Open questions: whether it's one `AsyncSequence` of snapshots or something
observable; how it reports an order it can't keep; whether the cache should
live in the SDK's node tree rather than beside it.

## Firestore: decode documents without copying their values

Reading a document converts its values three times: from the C++ core's
protobuf values into a `BridgeFieldValue` tree (copying every string and blob),
into `[String: Any]`, and finally, with `Codable`, into the user's type.

A decoder could read the core's values directly instead, as the Database's
`FNodeDecoder` reads its nodes. The values are valid only while the C++
snapshot is borrowed, which is what `Span` and non-escapable types express in
Swift 6.2: strings and blobs could be viewed as `Span<UInt8>` (or `UTF8Span`)
and copied into a `String` or `Data` only where the user's type stores one,
and keys could be matched without allocating.

To find out first: how much of reading a document the conversions cost
(measure, as for the Database), and how far Swift's C++ interop gets with
lifetime-annotated views (`std::span`, `__lifetimebound`) on all platforms,
Windows included.
