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

# Runs the port's scenarios on Linux: Benchmarks/run.sh in a swift:6.2
# container (Apple's `container`, or Docker), with the Database emulator in
# the same container. Upstream only builds for Apple platforms.
#
#   Benchmarks/run-linux.sh [run.sh arguments, e.g. --iterations 10]
#
# The container works on a copy of the working tree's tracked files (so its
# builds don't replace the host's), and the results come back to
# Benchmarks/results/ with a "-linux" suffix.

set -euo pipefail

if [ "${1:-}" != "--inside" ]; then
  cd "$(dirname "$0")/.."
  runtime=$(command -v container || command -v docker) ||
    { echo "Needs Apple's container or Docker" >&2; exit 1; }
  # Docker's -c is CPU shares; its CPU count is --cpus.
  cpus=(-c 8)
  [ "$(basename "$runtime")" = docker ] && cpus=(--cpus 8)
  exec "$runtime" run --rm -m 16G "${cpus[@]}" -v "$PWD":/src -w /src swift:6.2 \
    /src/Benchmarks/run-linux.sh --inside "$@"
fi
shift

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq openjdk-21-jre-headless xz-utils curl >/dev/null
# Ubuntu 24.04's Node is 18; firebase-tools needs a newer one.
arch=$(uname -m | sed 's/aarch64/arm64/; s/x86_64/x64/')
curl -fsSL "https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-$arch.tar.xz" | tar -xJ -C /opt
export PATH="/opt/node-v22.11.0-linux-$arch/bin:$PATH"
npm install -g firebase-tools@15.34.2 >/dev/null

git config --global --add safe.directory /src
revision=$(git -C /src stash create)
mkdir -p /work
git -C /src archive "${revision:-HEAD}" | tar -x -C /work
export BENCHMARK_GIT_REVISION=$(git -C /src rev-parse --short HEAD)$(
  git -C /src diff --quiet HEAD -- Sources/FirebaseDatabase || echo "-dirty")

cd /work
export BENCHMARK_DISABLE_JEMALLOC=true
# run.sh hides the build output; build first, so that errors show.
swift build -c release --package-path Benchmarks/Port --product bench-port 2>&1 |
  grep -E "error:|complete!"
# The port only; a later --targets wins.
Benchmarks/run.sh --targets port "$@"

for result in Benchmarks/results/*.jsonl; do
  git -C /src ls-files --error-unmatch "$result" >/dev/null 2>&1 && continue
  cp "$result" "/src/${result%.jsonl}-linux.jsonl"
  echo "Results: ${result%.jsonl}-linux.jsonl"
done
