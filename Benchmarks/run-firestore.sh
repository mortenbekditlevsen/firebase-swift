#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Builds the Firestore benchmarks (release; upstream from source), runs F1 for
# the port and upstream in turns, so both see the same machine load, and
# prints the comparison. No emulator: F1 reads Firestore's local cache.
#
#   Benchmarks/run-firestore.sh [--documents N] [--rounds N] [--iterations N] [--targets "port upstream"]

set -euo pipefail
cd "$(dirname "$0")/.."

documents=10000
rounds=4
iterations=5
targets="port upstream"
while (($#)); do
  case "$1" in
    --documents) documents="$2"; shift 2 ;;
    --rounds) rounds="$2"; shift 2 ;;
    --iterations) iterations="$2"; shift 2 ;;
    --targets) targets="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 1 ;;
  esac
done

# Upstream links a prebuilt Firestore without this.
export FIREBASE_SOURCE_FIRESTORE=1
for target in $targets; do
  package=$([ "$target" = port ] && echo FirestorePort || echo FirestoreUpstream)
  swift build -c release --package-path "Benchmarks/$package" --product "bench-firestore-$target" >/dev/null
done
swift build -c release --package-path Benchmarks/Scenarios --product bench-compare >/dev/null

revision=${BENCHMARK_GIT_REVISION:-$(git rev-parse --short=8 HEAD)$(git diff --quiet HEAD -- Sources/Firestore || echo "-dirty")}
output="Benchmarks/results/$revision-firestore-$(date +%Y%m%d-%H%M%S).jsonl"
export BENCHMARK_GIT_REVISION="$revision"

for ((round = 1; round <= rounds; round++)); do
  for target in $targets; do
    package=$([ "$target" = port ] && echo FirestorePort || echo FirestoreUpstream)
    echo "== round $round $target" >&2
    "Benchmarks/$package/.build/release/bench-firestore-$target" \
      --documents "$documents" --iterations "$iterations" --output "$output"
  done
done

Benchmarks/Scenarios/.build/release/bench-compare "$output"
echo "Results: $output"
