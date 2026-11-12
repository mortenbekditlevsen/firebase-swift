# Realtime Database: performance

How the Swift port of Realtime Database compares with upstream's
(firebase-ios-sdk 13.1.1), and how it got there. The benchmarks are in
[Benchmarks/](../Benchmarks/README.md) and the raw results in
`Benchmarks/results/`.

## How it's measured

The scenarios run against the Database emulator on the same Mac (Apple M5,
18 cores, macOS 27), over loopback. The port and upstream take turns. The
emulator does the server's work for both, so its time is in every number.
Compare the targets with each other, not the absolute times. The numbers are
medians of 10 runs (5 for the earlier phases). Upstream ran with main-queue
and with background-queue callbacks; the table shows the faster of the two.

| ID | Scenario |
|---|---|
| S1 | Load 10k children (about 2.4 MB) on a new connection |
| S2 | 10k child-added events (100 merges of 100) |
| S3 | S1, then decoding into `[String: BenchItem]` |
| S4a | 2k writes, each awaited |
| S4b | 5k writes at once |
| S5 | Read the 10k children from the offline cache, in a new process |
| S6 | 50 concurrent transactions on one counter |

## Where it ended up

`Benchmarks/results/d00c08c7-p8-final.jsonl`:

| Scenario | Port before | **Port now** | Upstream | Now vs upstream | Peak MB: before → now (upstream) |
|---|---:|---:|---:|---:|---:|
| S1 | 596 ms | **49 ms** | 180 ms | 3.7× faster | 367 → **69** (64) |
| S2 | 9815 ms | **174 ms** | 381 ms | 2.2× faster | 260 → **43** (45) |
| S3 | 850 ms | **75 ms** | 281 ms | 3.7× faster | 402 → **74** (68) |
| S3, the decode step alone | ≈ 300 ms | **23 ms** | 100 ms | 4.3× faster | |
| S4a | 453 ms | **269 ms** | 340 ms | 1.3× faster | 18 → 20 (19) |
| S4b | 1255 ms | **598 ms** | 7183 ms | 12× faster | 280 → **80** (64) |
| S5 | 409 ms | **44 ms** | 405 ms | 9.2× faster | 254 → **49** (68) |
| S6 | 5.7 ms | **2.3 ms** | 4.3 ms | 1.9× faster | 18 → 20 (19) |

"Before" is the baseline (`796e15b0-baseline.jsonl`). On the scenarios
measured with it, the port also uses less CPU than upstream: S1 38 ms
against 175, S2 227 against 484, S4a 141 against 245.

Memory is now about level with upstream. S1 and S3 peak at 5 MB more, S4b at
15 MB more, and S2 and S5 lower.

## Since P8: hashes and writes

`Benchmarks/results/5e56f510-hashes-writes-ab-*.jsonl`, measured A/B: the
builds before and after took turns in one emulator session, so both saw the
same machine load (Spotlight indexing made back-to-back runs incomparable).

| Scenario | Before (wall / CPU ms) | After (wall / CPU ms) |
|---|---:|---:|
| S4a | 278 / 143 | 247 / 125 |
| S4b | 646 / 1303 | **288 / 506** |
| S1, S2, S3, S5, S6 | | unchanged |

Micro-benchmarks for 10k items (p50):

| Step | Before | Now |
|---|---:|---:|
| A listen's compound hash of cached data | 853 ms | 28 ms |
| A listen's simple hash (`dataHash`) | 305 ms | 57 ms |
| Write tree: 5k sibling writes, acknowledged oldest first | 463 ms | 120 ms |
| Node from Swift values (writes) | 120 ms | 77 ms |
| Node from Foundation values | 213 ms | 192 ms |

- **Listen hashes.** A listen on cached data sends both hashes (above 1 kB),
  computed on the Database actor, again on every reconnect, so resuming a
  listen on S1's data held the actor for over a second.
  - Each number was formatted with 8 `String(format:)` calls via
    `NSNumber`; now it's formatted from the double's bits.
  - The compound hash asked for its range's length in characters after
    every leaf, which counts the whole string: quadratic. Now it uses UTF-8
    bytes. That only moves where ranges end (upstream counts UTF-16 units),
    which the client chooses.
  - SHA-1 reads the string's bytes in place, and strings needing no
    escaping skip `replacingOccurrences`.
- **Writes of Swift values.** `nodeFrom` cast every value to `NSNumber` and
  other bridged types, whose conformance lookups were S4b's largest cost. It
  now recognizes `String`, `Int`, `Int64`, `Double` and `Bool` by their
  exact type first, and skips validating a priority there isn't.
- **Acknowledging writes.** Removing a write checks every other pending
  write for overlap, as upstream: quadratic in pending writes. Each check
  now reads the record in place, and path containment compares from the
  last piece, where siblings differ.

## Cached data hashes

Children nodes keep their data hash once computed, as a 20-byte SHA-1
digest, in one box with the node's priority (`NodeExtras`). Nodes are
immutable values, so nothing needs clearing: a change makes new nodes on the
path to the root, which start without a hash, and unchanged subtrees keep
theirs. Leaves aren't cached: one SHA-1 of a short string each, and a box
per leaf would cost the most memory.

For the 10k items (micro-benchmarks, p50; memory from the allocator):

| | Before | Now |
|---|---:|---:|
| Hash again, unchanged | 60 ms | 0.2 µs |
| Hash after one item changed | 59 ms | 2.5 ms |
| First hash (parse + hash) | 88 ms | 71 ms |
| Parse | 27 ms | 28 ms |
| Tree, parsed and hashed | 11.6 MB | 12.8 MB (+11%) |
| Tree written from Swift values | 18.5 MB | 11.5 MB |

- The 11% is one 64-byte box per children node (about 20k here); nodes
  stay 40 bytes.
- A parent's hash input is now bytes, with the children's digests appended
  in base 64, so even the first hash is faster.
- Written trees shrank because an empty priority no longer gets a box
  (it equals none): every written leaf had one.
- A listen on large data still computes the compound hash (29 ms here),
  which can't be cached per node: its ranges depend on the whole tree.

An earlier version kept a `String` per hash and a pointer in every node: 48
bytes per node and +23% for the same tree, for the same speed.

## Linux

`Benchmarks/run-linux.sh` (a `swift:6.2` container with 8 cores, the emulator
inside it); `Benchmarks/results/5e56f510-linux.jsonl` before the changes
above, `5e56f510-hashes-writes-linux.jsonl` after:

| Scenario | Before (wall / CPU ms) | After (wall / CPU ms) | Peak MB |
|---|---:|---:|---:|
| S1 | 76 / 49 | 78 / 52 | 115 |
| S2 | 177 / 202 | 198 / 213 | 69 |
| S3 (decode) | 109 / 100 (27) | 119 / 111 (32) | 145 |
| S4a | 532 / 239 | 524 / 225 | 42 |
| S4b | 1083 / 1530 | 725 / 1048 | 130 |
| S5 | 49 / 46 | 48 / 47 | 62 |
| S6 | 2.9 / 2.7 | 2.7 / 2.8 | 41 |

The emulator shares the container's 8 cores, so wall times aren't comparable
with the Mac's. CPU times are roughly the Mac's, except S4b's (about twice),
and peak memory is about twice the Mac's, as glibc's allocator keeps more.

## What made the difference

Port medians by phase, in ms:

| Phase | S1 | S2 | S3 | S4a | S4b | S5 | S6 | S1 peak MB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Baseline | 596 | 9815 | 850 | 453 | 1255 | 409 | 5.7 | 367 |
| P0/P1 quick fixes | 366 | 475 | 622 | | | | | 337 |
| P1 transport | 304 | 468 | 542 | 379 | 1040 | 411 | 2.4 | 341 |
| P2 connection | 290 | 472 | 542 | 385 | 995 | 408 | 2.3 | 271 |
| P3 async API | 295 | 472 | 602 | 384 | 738 | 400 | 2.4 | 270 |
| P4 byte-level JSON | 71 | 176 | 324 | 290 | 654 | 378 | 2.6 | 224 |
| P5 node Codable | 63 | 203 | 95 | 362 | 774 | 407 | 2.6* | 224 |
| P6 persistence on Span | 65 | 224 | 100 | 396 | 738 | 72 | 2.6 | 222 |
| P8 compact children | 47 | 239 | 71 | 463 | 857 | 56 | 3.0 | 66 |
| P8 final | 49 | 174 | 75 | 269 | 598 | 44 | 2.3 | 69 |

\* From the rerun; the first P5 run measured 15.8 ms on a busy emulator.

S2 and S4a also move with the machine's load. Upstream's own S4a varied
between 330 and 400 ms over these runs. So read those columns by their
trend, not by single steps.

By size of effect:

1. **Child updates (P0):**
   - `FTree.updateChild` didn't write a new child back to its parent, so each
     merge walked further. Fixing it took S2 from 9.8 s to 0.47 s.
   - In the same step, log messages became lazy (`@autoclosure`) and child
     lookups use the B-tree instead of a linear search.
2. **Bytes straight to nodes, and back (P4):**
   - A byte-level JSON scanner (`FJSONScanner`, over `Span`) builds nodes
     directly. Before, messages went bytes → `String` → `Data` →
     JSONSerialization → Foundation tree → nodes.
   - Only a message's data part is read as nodes; the envelope around it is
     small Foundation values.
   - `FJSONWriter` writes nodes without `val()`.
   - Keys cache whether they're integers, instead of parsing themselves on
     every comparison (a 3.5× faster sort).
   - S1 went from 295 to 71 ms.
3. **Codable from and to nodes (P5):** `FNodeDecoder` and `FNodeEncoder`
   work on nodes directly, instead of through `val()` and
   `FirebaseDataDecoder` (or `FirebaseDataEncoder` and `nodeFrom`). S3's
   decode went from about 255 to 23 ms.
4. **The cache on Span (P6):**
   - LevelDB lends its keys and values in place.
   - One pass over a path's keys builds the node.
   - Leaves are written from the node.
   - S5 went from 407 to 44 ms.
5. **Compact children (P8):**
   - A node's children were a `SortedDictionary`. In release builds, its
     B-tree nodes reserve room for 16 entries, in three allocations. In debug
     builds they reserve 5, which is why debug measurements didn't show it.
     10k small objects took 162 MB.
   - `FChildren` keeps up to 32 children in a sorted array that fits them,
     as upstream's and Android's array-backed dictionaries do, and larger
     ones in the B-tree.
   - With the unused cached-hash field removed from nodes (64 → 48 bytes),
     the same data takes 10.5 MB. S1's peak went from 222 to 66 MB, and
     loading got faster too.
6. **Sending without a task switch (P8):** NIO channels take writes from any
   thread in order, so the actor writes to the channel directly instead of
   through an outbox task and NIO's async writer. This was the one scenario
   upstream still won. S4a went from 400–470 ms to 380–400 ms, on a loaded
   machine, then to 269 ms in the final run (upstream: 340).
7. **Smaller things (P8):**
   - `FIndexedNode` works out its order once instead of on every access.
   - Children are sorted with a stable sort instead of a sort over
   `enumerated()`.
   - Key comparisons read the bytes in place.
   - Parsing the micro-benchmark's 10k objects went from 49 to 28 ms.

Micro-benchmarks for 10k items, without a network (p50; before → now):

| Step | Before | Now | For reference |
|---|---:|---:|---|
| Parse JSON to a node | 251 ms | 28 ms | JSONSerialization alone: 13 ms, making no node |
| Decode a node to `[String: BenchItem]` | 267 ms | 24 ms | JSONDecoder from the bytes: 28 ms |
| Encode `[String: BenchItem]` to a node | 259 ms | 59 ms | |
| Serialize a node to JSON | 188 ms | 18 ms | |
| Sort 10k keys | 16 ms | 4.5 ms | |

## Lessons

- **S1's apparent P3 regression** came from the benchmark itself. Each
  client's teardown overlapped the next one's load on the shared actor. The
  runner now pauses between iterations, unmeasured.
- **Memory has to be measured in release builds.** swift-collections sizes
  its B-tree nodes differently in debug builds, which hid the biggest memory
  cost for six phases.
- **Unsorted input is the slow path.** Upstream's server sends keys in
  order, so loads skip the sort. The micro-benchmark's `JSONEncoder` fixture
  doesn't, so it overstates sorting.

## Open

- **The compound hash isn't cached.** A listen on more than 1 kB of cached
  data computes it every time: 29 ms for 10k items, on the Database actor.
  Its ranges depend on the whole tree's size, so it can't be kept per node.
- **Pending writes are quadratic.** Acknowledging a write still checks every
  other pending one (upstream's algorithm): 120 ms for 5k at once. An index
  of the writes by path would make it linear.
- **S4b on Linux** uses about twice the Mac's CPU time; not profiled yet.
- **The encoder still makes as many allocations as the old path.** It's 4×
  faster, but its containers are reference boxes.
- **Parsing builds a tree.** It's 2× JSONSerialization alone, which makes
  none. Most of the rest is copying and releasing keys and nodes.
- **The device study** (the background probe, P7) isn't in yet.
