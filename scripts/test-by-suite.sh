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

# Runs a test module's tests one top-level suite (or XCTest class) at a time,
# with `swift test --skip-build`, so the tests must be built.
#
#   scripts/test-by-suite.sh <module> [<suite pattern>]
#
# The pattern is an extended regex the suite names must match in full
# (default: all of them). With SUITE_RESULTS set, appends "| suite | result |"
# for each suite to that file.
#
# Why not one `swift test --filter <module>\.`: outside Apple platforms,
# SwiftPM passes the matching XCTest tests to the test process as one
# comma-separated argument, which for a whole module can exceed Windows'
# 32,767-character command-line limit. And a crash then takes only its own
# suite down, which also names it.

set -uo pipefail
cd "$(dirname "$0")/.."

module=$1
pattern=${2:-.*}

suites=$(swift test list --skip-build | tr -d '\r' \
  | grep -oE "^$module\.[A-Za-z0-9_]+/" | sed -E "s/^$module\.//; s|/$||" \
  | grep -xE "$pattern" | sort -u)
if [ -z "$suites" ]; then
  echo "No suites in $module match $pattern." >&2
  exit 1
fi

failed=0
for suite in $suites; do
  echo "Running $module.$suite"
  if swift test --skip-build --filter "^$module\.$suite/"; then
    result=success
  else
    result=failure
    failed=1
  fi
  if [ -n "${SUITE_RESULTS:-}" ]; then
    echo "| $suite | $result |" >> "$SUITE_RESULTS"
  fi
done
exit $failed
