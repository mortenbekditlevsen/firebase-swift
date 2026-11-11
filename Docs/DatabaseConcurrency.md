# Realtime Database: concurrency

How the Swift port of Realtime Database runs. Upstream (firebase-ios-sdk)
runs everything on one serial dispatch queue and calls back through blocks.
Here, the core is the same synchronous code on one actor, and the edges are
async: the transport below and the public API above.

## The actor and the operation queue

Each database's state lives on the global `DatabaseActor`:
- the repo;
- the sync tree, views and write tree;
- the connection's state machine;
- the persistence manager.

That code is a port of the queue-confined original. It stays synchronous on
purpose: an `await` inside it would let other work run in the middle of an
update, which the original never allowed.

Public calls arrive from any isolation, so each repo has an **operation
queue**: an `AsyncStream` of closures, consumed in order by one task on the
actor (`FRepo.enqueue`). Separate `Task`s would also reach the actor, but in
no particular order. With the queue, calls take effect in the order they're
made, as on upstream's serial queue:
- **Plain writes** (`setValue(_:)`, `updateChildValues(_:)`, …) enqueue and
  return. Their local events are raised when the queue runs them, before
  anything enqueued later.
- **`…AndWait` writes** enqueue the same operation, then wait for the
  server's acknowledgement (`FRepo.run`, a checked continuation resumed
  exactly once).
- **Reads:**
  - `firstValue()` is a listen that ends after the first event.
  - `getData()` first waits for the queue to drain, so it sees the writes
    made before it.

The types callers see are `Sendable`:
- `Database`, `DatabaseReference` and `DatabaseQuery` are immutable handles.
- `DataSnapshot`, `MutableData` and `FNode` are value types.

## Listening

`values()` and `childEvents(_:)` return a `DatabaseEvents` sequence:
- **Starting:** making its iterator enqueues the event registration, so a
  write made after the loop starts is seen.
- **Delivery:** the registration yields each event to an
  `AsyncThrowingStream` synchronously, on the actor. There's no task per
  event, and the stream's buffering policy decides what a slow reader skips.
- **Stopping:** ending the iteration, or cancelling its task, terminates the
  stream, and its termination handler enqueues the unlisten.
- **Errors:** a revoked listen finishes the stream with the error.

A listener's lifetime is therefore the lifetime of its loop. There are no
handles to remove.

## Decoding

Nodes are immutable values, so decoding needs no actor:
- **Typed sequences:** `values(as:)` and `childEvents(as:)` decode each
  element in a `@concurrent` step after the event, on the cooperative pool,
  in order. That's neither the Database actor nor the caller's actor, so a
  `for try await` loop on the main actor doesn't decode on the main thread.
- **`firstValue(as:)` and `get(as:)`** are `@concurrent` too.
- **`data(as:)`** decodes where it's called.

## The connection

`FPersistentConnection.run()` is one long-lived **supervisor** task per repo.
For each connection attempt it:
1. waits while the connection is interrupted (`goOffline`);
2. waits out the backoff, cut short by a network change or a return to the
   foreground;
3. gets the auth and App Check tokens;
4. runs a **session**.

A session is a throwing discarding task group in which everything runs as a
child task:
- the handshake timeout;
- the transport's `withConnection`, which runs its own group of:
  - the message reader (`for try await frame in connection.inbound`, which
    handles each message synchronously on the actor);
  - the keepalive ("0" after 45 s without traffic);
  - the liveness check: after a network change, a stats request that must
    be answered within 10 s;
  - the outbox writer, for transports that can't send immediately.

The first child to end, whether by the server closing, a timeout or a
failure, ends the session and cancels the others. The session's error says
what comes next:
- a reset reconnects at once, to the new host;
- a shutdown from the server stops reconnecting;
- anything else backs off.

The group's own body runs nothing important, because a group's body isn't
cancelled when a child fails.

Requests and their responses are matched in a `pending` dictionary of what
each response is for (`PendingResponse`), not in callbacks. When a session
ends:
- puts and onDisconnect writes are kept and sent again on the next
  connection;
- gets are sent again too, unless the client stays offline for the gets'
  connect timeout (3 s), when they fail and fall back to the cache;
- every completion runs exactly once.

Time comes from an injectable `DatabaseClock`, so the tests run all of this
on a manual clock (`PersistentConnectionTests`).

### Sending

The actor sends a message by:
1. encoding it with `FJSONWriter`;
2. splitting it into frames, which end at UTF-8 character boundaries;
3. handing each frame to the connection.

How the frames reach the socket depends on the transport:
- **NIO connections**, on POSIX or Network.framework, take writes from any
  thread in order (`DatabaseTransportImmediateSending`). The actor writes to
  the channel directly, so a message leaves without a task switch.
- **Other transports** get the frames through an `AsyncStream` outbox, which
  a child task drains with `send`.

Only one of the two paths is used for a connection, so order is kept.

### Transports

`DatabaseTransport.withConnection(to:isolation:_:)` is scoped, like NIO's
`executeThenClose`: the connection exists for the body's duration.
`inbound` is an `AsyncSequence` that finishes on a close and throws on a
failure, and cancelling the task closes the socket. The conformance suite
(`TransportConformanceTests`) checks those rules for each transport.

## Memory safety

- **Reading JSON:** messages and LevelDB values are read through `Span`
  (`FJSONScanner` is `~Escapable`), so nothing can keep a pointer into the
  bytes after they're gone.
- **`unsafe` code:** it's limited to these places:
  - the LevelDB C API;
  - turning a span into a `String`;
  - `memchr` and `strcspn` for long strings.
- **LevelDB memory:** values and error strings are freed with `leveldb_free`,
  and the LevelDB tests run clean under `leaks`.

## Decided against, for now

- **A per-repo actor instead of the global one:** with several databases in
  one app, each would get its own serial executor. The benchmarks use one
  database, and on them the actor isn't the bottleneck. CPU time is below
  upstream's in every scenario, and it spends its time on parsing and
  applying, not on waiting for the actor. That makes the change worth trying
  only with a multi-database workload to measure it on.
- **Parsing messages off the actor:** today the reader parses a message on
  the actor. That's about 30 ms for S1's 2.4 MB, during which the database's
  other calls wait. Parsing in the reader's own task would free the actor
  meanwhile, but it wouldn't make a load faster, since the message must be
  parsed before it can be applied. It would also need the envelope as
  `Sendable` typed messages instead of Foundation values. That's worth doing
  if apps show the actor's latency during big loads.
