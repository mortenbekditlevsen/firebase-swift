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

"""The modules this repository ports from firebase-ios-sdk, and git helpers
shared by the scripts in this folder."""

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

UPSTREAM_URL = "https://github.com/firebase/firebase-ios-sdk.git"
UPSTREAM_WEB = "https://github.com/firebase/firebase-ios-sdk"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "firebase-swift"


@dataclass
class Module:
    name: str
    port: str  # relative to this repository
    upstream: str  # relative to firebase-ios-sdk
    metric: str  # how baselines.py compares it: exact, lines or strings
    # The upstream release this module has been synced to: everything up to
    # it is ported or deliberately left out. Set by hand from UPSTREAM.md's
    # analysis, and bumped after each sync.
    synced_to: str
    changelog: str  # upstream CHANGELOG.md for the module
    exclude: tuple = ()  # port path prefixes (relative to `port`) to skip


MODULES = [
    Module("Firestore core (C++)", "Sources/Firestore/core", "Firestore/core", "exact",
           "13.1.1", "Firestore/CHANGELOG.md"),
    Module("Firestore protos", "Sources/Firestore/Protos", "Firestore/Protos", "exact",
           "13.1.1", "Firestore/CHANGELOG.md"),
    Module("Firestore Objective-C API", "Sources/Firestore/Source", "Firestore/Source", "exact",
           "13.1.1", "Firestore/CHANGELOG.md"),
    Module("Firestore Swift", "Sources/Firestore/Swift", "Firestore/Swift", "exact",
           "13.1.1", "Firestore/CHANGELOG.md"),
    Module("FirebaseDataEncoder", "Sources/FirebaseShared/third_party/FirebaseDataEncoder",
           "FirebaseSharedSwift/Sources/third_party/FirebaseDataEncoder", "exact",
           "12.19.2", "FirebaseSharedSwift/CHANGELOG.md"),
    Module("FirebaseAuth", "Sources/FirebaseAuth", "FirebaseAuth/Sources/Swift", "lines",
           "11.0.0", "FirebaseAuth/CHANGELOG.md"),
    Module("FirebaseFunctions", "Sources/FirebaseFunctions", "FirebaseFunctions/Sources", "lines",
           "13.1.1", "FirebaseFunctions/CHANGELOG.md"),
    Module("FirebaseStorage", "Sources/FirebaseStorage", "FirebaseStorage/Sources", "lines",
           "13.1.1", "FirebaseStorage/CHANGELOG.md"),
    Module("FirebaseDatabase", "Sources/FirebaseDatabase", "FirebaseDatabase/Sources", "strings",
           "13.1.1", "FirebaseDatabase/CHANGELOG.md", exclude=("third_party/",)),
]

RELEASE_TAG = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def select(name):
    """The modules whose name contains `name` (all of them for None)."""
    selected = [m for m in MODULES if not name or name.lower() in m.name.lower()]
    if not selected:
        sys.exit(f"No module matches {name!r}; modules: {', '.join(m.name for m in MODULES)}")
    return selected


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def git(repo, *args, input=None, env=None):
    result = subprocess.run(["git", "-C", str(repo), *args], input=input, capture_output=True,
                            env=env, check=True)
    return result.stdout


def ensure_clone(cache, offline):
    """A blobless clone of firebase-ios-sdk with all tags, updated unless offline."""
    repo = cache / "firebase-ios-sdk"
    if not (repo / ".git").exists():
        cache.mkdir(parents=True, exist_ok=True)
        print(f"Cloning {UPSTREAM_URL} into {repo} (blobless)…", file=sys.stderr)
        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", "--no-checkout",
                        UPSTREAM_URL, str(repo)], check=True)
    elif not offline:
        git(repo, "fetch", "--quiet", "--tags", "--force", "origin")
    return repo


def release_tags(repo, since=None):
    """Release tags, oldest first, from `since` on."""
    tags = [tag for tag in git(repo, "tag").decode().split() if RELEASE_TAG.match(tag)]
    if since:
        tags = [tag for tag in tags if version_key(tag) >= version_key(since)]
    return sorted(tags, key=version_key)


def label(ref):
    return "main" if ref == "origin/main" else ref
