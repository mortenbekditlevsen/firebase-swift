#!/bin/bash
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

# Builds and runs the vendored Firestore core's C++ unit tests
# (Sources/Firestore/core/test, GoogleTest) with upstream's CMake build.
#
# The vendored tree only has Firestore's own CMakeLists.txt files; the rules
# they use (firebase_ios_add_test, …) and the build of their dependencies
# (abseil, gRPC, LevelDB, nanopb, protobuf, GoogleTest) are in the root of
# firebase-ios-sdk. So this checks out upstream's root CMake files at the
# release Firestore is synced to, with Sources/Firestore in place of upstream's
# Firestore directory, and builds that.
#
# Usage: scripts/test-firestore-core.sh [ctest arguments, e.g. -R firestore_util_test]
#
# Environment:
#   FIRESTORE_UPSTREAM_TAG  upstream release tag (default: Firestore's synced_to
#                           in scripts/upstream/upstream.py)
#   FIRESTORE_CORE_WORK_DIR where to check out and build (default: .build-firestore-core)
#   FIRESTORE_CORE_LINK_JOBS how many binaries to link at once (default: 2)
#
# Needs CMake, Ninja, Python 3 (with venv), Git and a C++17 compiler. OpenSSL
# and zlib development packages are used when found, which saves building
# BoringSSL and zlib.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "${FIRESTORE_UPSTREAM_TAG:-}" ]; then
  version=$(PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/scripts/upstream" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import upstream
print(next(m.synced_to for m in upstream.MODULES if m.name == "Firestore core (C++)"))
EOF
)
  FIRESTORE_UPSTREAM_TAG="CocoaPods-$version"
fi
WORK=${FIRESTORE_CORE_WORK_DIR:-$ROOT/.build-firestore-core}
SRC=$WORK/src
BUILD=$WORK/build

if [ ! -f "$SRC/.firebase-swift-tag" ] ||
   [ "$(cat "$SRC/.firebase-swift-tag")" != "$FIRESTORE_UPSTREAM_TAG" ]; then
  echo "Checking out upstream's CMake build at $FIRESTORE_UPSTREAM_TAG"
  rm -rf "$SRC" "$BUILD"
  git clone --quiet --depth 1 --branch "$FIRESTORE_UPSTREAM_TAG" --filter=blob:none \
    --sparse https://github.com/firebase/firebase-ios-sdk.git "$SRC"
  # The root CMakeLists.txt also adds these directories.
  git -C "$SRC" sparse-checkout set cmake FirebaseCore FirebaseAppCheck/Interop \
    FirebaseAuth/Interop
  echo "$FIRESTORE_UPSTREAM_TAG" > "$SRC/.firebase-swift-tag"
fi
ln -sfn "$ROOT/Sources/Firestore" "$SRC/Firestore"

# The test binaries are large: linking many at once with GNU ld runs out of
# memory on 16 GB machines (such as GitHub's runners), so links take turns.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_JOB_POOLS="link=${FIRESTORE_CORE_LINK_JOBS:-2}" \
  -DCMAKE_JOB_POOL_LINK=link \
  -DFIRESTORE_INCLUDE_OBJC=OFF \
  -DFIREBASE_IOS_BUILD_BENCHMARKS=OFF
cmake --build "$BUILD"
ctest --test-dir "$BUILD" --output-on-failure -j "$(getconf _NPROCESSORS_ONLN)" "$@"
