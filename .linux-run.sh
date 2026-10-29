#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq openjdk-21-jre-headless curl xz-utils >/dev/null
ARCH=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')
curl -fsSL https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-$ARCH.tar.xz | tar -xJ -C /opt
export PATH=/opt/node-v22.11.0-linux-$ARCH/bin:$PATH
npm install -g --silent firebase-tools >/dev/null 2>&1
firebase --version
swift build --build-tests --scratch-path .build-linux-clean 2>&1 | grep -E "error:|Build complete" || true
# unit tests passed earlier: swift test --skip-build --scratch-path .build-linux-clean 2>&1 | grep -a -E "Executed [0-9]+ tests, with|Test run with|error:" || true
for i in 1 2 3; do
  firebase emulators:exec --project demo-firebase-swift --only auth,database,firestore,storage \
    "timeout 900 swift test --skip-build --scratch-path .build-linux-clean --filter IntegrationTests" 2>&1 \
    | grep -a -E "Test run with|recorded an issue|failed|✘|error:|Fatal|fatal" | cut -c1-250 || true
done
