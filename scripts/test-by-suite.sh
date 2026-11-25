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

# Runs a test module's tests a batch of top-level suites (or XCTest classes)
# at a time, with `swift test --skip-build`, so the tests must be built.
#
#   scripts/test-by-suite.sh <module> [<suite pattern>]
#
# The pattern is an extended regex the suite names must match in full
# (default: all of them). With SUITE_RESULTS set, appends "| suites | result |"
# for each batch to that file. With TEST_EVENTS set to a directory, each batch
# writes Swift Testing's events there as they happen (one JSON object per
# line), which shows the tests a hung batch was running.
#
# Why not one `swift test --filter <module>\.`: outside Apple platforms,
# SwiftPM passes the matching XCTest tests to the test process as one
# comma-separated argument, which for a whole module can exceed Windows'
# 32,767-character command-line limit. Why not a suite per run: on Windows
# each `swift test` takes about two minutes before it starts the tests.

set -uo pipefail
cd "$(dirname "$0")/.."

module=$1
pattern=${2:-.*}
# The test IDs a batch's argument may hold, in characters.
limit=24000

# "suite<TAB>characters" for each matching suite.
sizes=$(swift test list --skip-build | tr -d '\r' \
  | grep -E "^$module\.[A-Za-z0-9_]+/" \
  | awk -F/ -v module="$module" -v pattern="^($pattern)$" '{
      suite = substr($1, length(module) + 2)
      if (suite ~ pattern) size[suite] += length($0) + 1
    } END { for (suite in size) print suite "\t" size[suite] }' \
  | sort)
if [ -z "$sizes" ]; then
  echo "No suites in $module match $pattern." >&2
  exit 1
fi

# One line of space-separated suites per batch.
batches=$(echo "$sizes" | awk -F'\t' -v limit=$limit '{
    if (total > 0 && total + $2 > limit) { print batch; batch = ""; total = 0 }
    batch = batch (batch == "" ? "" : " ") $1
    total += $2
  } END { if (batch != "") print batch }')

failed=0
number=0
while read -r batch; do
  echo "Running $module: $batch"
  number=$((number + 1))
  events=()
  if [ -n "${TEST_EVENTS:-}" ]; then
    mkdir -p "$TEST_EVENTS"
    events=(--event-stream-output-path "$TEST_EVENTS/$module-$$-$number.jsonl" --event-stream-version 0)
  fi
  if swift test --skip-build --filter "^$module\.(${batch// /|})/" ${events[@]+"${events[@]}"} < /dev/null; then
    result=success
  else
    result=failure
    failed=1
  fi
  if [ -n "${SUITE_RESULTS:-}" ]; then
    echo "| ${batch// /, } | $result |" >> "$SUITE_RESULTS"
  fi
done <<< "$batches"
exit $failed
