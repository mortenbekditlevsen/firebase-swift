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

# Runs inside `firebase emulators:exec` (see run.sh). Each scenario runs once
# per target in turn, so the targets see the same conditions.

set -euo pipefail

run_id="r$(date +%s)"
for scenario in $BENCHMARK_SCENARIOS; do
  for target in $BENCHMARK_TARGETS; do
    binary="Benchmarks/$( [ "$target" = port ] && echo Port || echo Upstream )/.build/release/bench-$target"
    variants=default
    [ "$target" = upstream ] && variants="main background"
    for variant in $variants; do
      queue=""
      [ "$variant" = background ] && queue=background
      echo "== $scenario $target $variant" >&2
      if [ "$scenario" = S5 ]; then
        # Prime once, then one cold read per process.
        id="$run_id-$target-$variant"
        BENCH_CALLBACK_QUEUE=$queue "$binary" --scenario S5-prime --run-id "$id"
        for ((i = 0; i < BENCHMARK_ITERATIONS; i++)); do
          BENCH_CALLBACK_QUEUE=$queue "$binary" --scenario S5-cold --run-id "$id" \
            --output "$BENCHMARK_OUTPUT"
        done
      else
        BENCH_CALLBACK_QUEUE=$queue "$binary" --scenario "$scenario" --run-id "$run_id-$variant" \
          --iterations "$BENCHMARK_ITERATIONS" --output "$BENCHMARK_OUTPUT"
      fi
    done
  done
done
