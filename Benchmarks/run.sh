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

# Builds the benchmark executables, runs every scenario for the port and for
# upstream (both callback-queue variants) against the Database emulator, and
# prints the comparison. Results go to Benchmarks/results/.
#
#   Benchmarks/run.sh [--iterations N] [--scenarios "S1 S3"] [--targets "port upstream"]
#
# Needs firebase-tools and Java 21 (see Tests/Emulator/README.md).

set -euo pipefail
cd "$(dirname "$0")/.."

iterations=5
scenarios="S1 S2 S3 S4a S4b S5 S6"
targets="port upstream"
while (($#)); do
  case "$1" in
    --iterations) iterations="$2"; shift 2 ;;
    --scenarios) scenarios="$2"; shift 2 ;;
    --targets) targets="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 1 ;;
  esac
done

for target in $targets; do
  swift build -c release --package-path "Benchmarks/$( [ "$target" = port ] && echo Port || echo Upstream )" \
    --product "bench-$target" >/dev/null
done
swift build -c release --package-path Benchmarks/Scenarios --product bench-compare >/dev/null

# BENCHMARK_GIT_REVISION names the revision where this isn't a git checkout.
revision=${BENCHMARK_GIT_REVISION:-$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources/FirebaseDatabase || echo "-dirty")}
output="Benchmarks/results/$revision-$(date +%Y%m%d-%H%M%S).jsonl"
export BENCHMARK_GIT_REVISION="$revision" BENCHMARK_OUTPUT="$output"
export BENCHMARK_ITERATIONS="$iterations" BENCHMARK_SCENARIOS="$scenarios" BENCHMARK_TARGETS="$targets"

firebase emulators:exec --project demo-firebase-swift --only database \
  "Benchmarks/run-scenarios.sh"

Benchmarks/Scenarios/.build/release/bench-compare "$output"
echo "Results: $output"
