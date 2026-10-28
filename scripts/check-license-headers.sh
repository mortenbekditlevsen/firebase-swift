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

# Fails if any Swift file under Sources/ or Tests/ lacks the Google
# Apache-2.0 copyright header. Vendored third_party code keeps its own
# license and is skipped.

set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
while IFS= read -r -d '' file; do
  if ! head -n 20 "$file" | grep -Eq "Copyright [0-9]{4}(-[0-9]{4})? Google( LLC)?"; then
    missing+=("$file")
  fi
done < <(find Sources Tests -name '*.swift' \
  -not -path '*/third_party/*' \
  -not -path 'Sources/old/*' \
  -print0)

if ((${#missing[@]})); then
  echo "Missing Google copyright header in ${#missing[@]} file(s):"
  printf '  %s\n' "${missing[@]}"
  exit 1
fi
echo "All Swift files have a copyright header."
