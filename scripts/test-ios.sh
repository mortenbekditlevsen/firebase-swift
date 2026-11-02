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

# xcodebuild passes TEST_RUNNER_-prefixed variables on to the tests, without the prefix.
# The Simulator shares the Mac's network, so the emulator's 127.0.0.1 address works.
firebase emulators:exec --project demo-firebase-swift --only auth '
  TEST_RUNNER_FIREBASE_AUTH_EMULATOR_HOST="$FIREBASE_AUTH_EMULATOR_HOST" \
  xcodebuild test -scheme firebase-swift-Package -destination "$IOS_DESTINATION" \
    -only-testing:FirebaseIntegrationTests/PhoneAuthIntegrationTests \
    -only-testing:FirebaseAuthTests/ProtectedDataTests $XCODEBUILD_ARGS
'
