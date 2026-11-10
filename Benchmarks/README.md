# Database benchmarks

Measurements of firebase-swift's Realtime Database against upstream's
(firebase-ios-sdk, at the release the port is synced to), on the same
scenarios and the same emulator.

The port and upstream both define `FirebaseCore` and `FirebaseDatabase`, so
they can't be linked into one binary. There are three packages instead:

| Package | What |
|---|---|
| `Scenarios` | The scenarios, fixtures (seeded, so every run sees the same bytes), REST seeding of the emulator, the JSON-lines result format and `bench-compare`. No Firebase dependency. |
| `Port` | `bench-port`: the scenarios against this repository's Database. `DatabaseMicro`: micro-benchmarks of the value paths, without a network ([benchmark](https://github.com/ordo-one/benchmark)). |
| `Upstream` | `bench-upstream`: the scenarios against upstream's Database (macOS). |

## Running

```sh
Benchmarks/run.sh                       # every scenario, 5 iterations
Benchmarks/run.sh --iterations 10 --scenarios "S1 S3" --targets port
```

`run.sh` builds the executables (release), starts the Database emulator with
`firebase emulators:exec` (Java 21 and firebase-tools, see
`Tests/Emulator/README.md`), runs each scenario for each target in turn, and
prints a Markdown table of medians. Results go to
`Benchmarks/results/<revision>-<date>.jsonl`. Combine files with
`Benchmarks/Scenarios/.build/release/bench-compare results/a.jsonl results/b.jsonl`.

Upstream runs twice: with its default main-queue callbacks and with a
background `callbackQueue`. The port calls back on its Database actor.

Micro-benchmarks:

```sh
swift package --build-system native --package-path Benchmarks/Port \
  --allow-writing-to-package-directory benchmark --target DatabaseMicro
```

(Set `BENCHMARK_DISABLE_JEMALLOC=true` where jemalloc isn't installed; the
malloc counts then aren't available. `--build-system native` is needed with
Xcode 27, whose build system can't build the plugin's malloc interposer.)

Each scenario process fails after 10 minutes (`--timeout <seconds>`), so a
hang shows up as an error instead of stalling the run.

## Scenarios

| ID | Scenario | Measured |
|---|---|---|
| S1 | Initial load: 10k children of 10 fields (about 3 MB of JSON), on a new connection | Connecting and the first value event |
| S2 | 10k child-added events, which the server pushes as 100 merges of 100 (REST `PATCH`) | From the first merge to the last event |
| S3 | S1, then `snapshot.data(as: [String: BenchItem].self)` in the callback | As S1; decode time separately |
| S4a | 2k writes, each awaited | All acknowledgements |
| S4b | 5k writes started together | All acknowledgements |
| S5 | A process caches the 10k children (`S5-prime`); new processes read them offline (`S5-cold`) | From creating the app to the cached value event |
| S6 | 50 concurrent transactions incrementing one counter | All completions |

Each record has wall-clock time, process CPU time, peak resident memory and
scenario-specific numbers. The emulator does the server's work for both
targets, so absolute times include it; compare targets, not absolute numbers.

## Notes

- `FirebaseDatabase`'s leveldb dependency has C++ headers, so its importers
  currently need `.interoperabilityMode(.Cxx)`. The benchmark targets set it.
- `@_spi(Benchmarking) import FirebaseDatabase` exposes the internal steps the
  micro-benchmarks call (`DatabaseBenchmarking`). It isn't API.
