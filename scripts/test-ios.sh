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

# Runs the iOS-only tests in the iOS Simulator: phone auth against the Auth emulator, and
# reloading the saved user after the device unlocks. Needs firebase-tools and Java 21.
#
#   IOS_DESTINATION   xcodebuild destination (default: the first available iPhone)
#   Extra arguments go to xcodebuild, e.g. -derivedDataPath.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${IOS_DESTINATION:-}" ]]; then
  device=$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' |
    grep -oE '[0-9A-F-]{36}')
  IOS_DESTINATION="platform=iOS Simulator,id=$device"
fi
export IOS_DESTINATION
export XCODEBUILD_ARGS="$*"
export ONLY_TESTING="-only-testing:FirebaseIntegrationTests/PhoneAuthIntegrationTests
  -only-testing:FirebaseAuthTests/ProtectedDataTests"

# On CI, the phone auth tests sometimes waited together for 30 seconds or more before their
# first request reached the emulator, and timed out. So the build, which takes many minutes
# there, happens before the emulator starts, and the Simulator has booted before the tests run.
# ($ONLY_TESTING and $XCODEBUILD_ARGS are split into arguments on purpose.)
# shellcheck disable=SC2086
xcodebuild build-for-testing -scheme firebase-swift-Package -destination "$IOS_DESTINATION" \
  $ONLY_TESTING $XCODEBUILD_ARGS
if [[ -n "${device:-}" ]]; then
  xcrun simctl bootstatus "$device" -b
fi

# xcodebuild passes TEST_RUNNER_-prefixed variables on to the tests, without the prefix.
# The Simulator shares the Mac's network, so the emulator's 127.0.0.1 address works.
# The first request also warms up the emulator, and its time shows whether the emulator was the
# slow part.
firebase emulators:exec --project demo-firebase-swift --only auth '
  start=$(date +%s)
  curl -sS -o /dev/null -X POST -H "Content-Type: application/json" \
    -d "{\"phoneNumber\": \"+15550000000\"}" \
    "http://$FIREBASE_AUTH_EMULATOR_HOST/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=warm-up"
  echo "The emulator answered the first phone verification request in $(( $(date +%s) - start )) s."
  TEST_RUNNER_FIREBASE_AUTH_EMULATOR_HOST="$FIREBASE_AUTH_EMULATOR_HOST" \
  xcodebuild test-without-building -scheme firebase-swift-Package \
    -destination "$IOS_DESTINATION" $ONLY_TESTING $XCODEBUILD_ARGS
'
