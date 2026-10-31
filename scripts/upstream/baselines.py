#!/usr/bin/env python3
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

"""Infers which firebase-ios-sdk release each module was ported from.

Every module is compared with the same paths in each upstream release tag
(and main), and the closest one is reported. How modules are compared:

- exact: vendored code, compared file by file by git blob ID. No file
  contents need to be fetched.
- lines: Swift ported to Swift. Matching files are compared line by line,
  ignoring comments, blank lines and indentation.
- strings: Objective-C ported to Swift. Code doesn't survive the change of
  language, but string literals do (log codes, error messages, wire
  constants), so matching files are compared by their sets of strings.

The upstream repository is a blobless clone in the cache directory; only the
file versions a comparison needs are fetched, in one batch per release.

Usage: scripts/upstream/baselines.py [--write UPSTREAM.md] [--module NAME]
"""

import argparse
import difflib
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from upstream import DEFAULT_CACHE, REPO_ROOT, ensure_clone, git, label, release_tags, select


def candidate_refs(repo, since):
    """Release tags from `since` on, oldest first, then main."""
    return release_tags(repo, since) + ["origin/main"]


def upstream_tree(repo, ref, path):
    """{path relative to `path`: blob ID} at `ref`."""
    out = git(repo, "ls-tree", "-r", "-z", ref, "--", path + "/").decode()
    tree = {}
    for entry in out.split("\0"):
        if not entry:
            continue
        meta, file_path = entry.split("\t", 1)
        _, kind, oid = meta.split()
        if kind == "blob":
            tree[file_path[len(path) + 1:]] = oid
    return tree


def port_files(module):
    root = REPO_ROOT / module.port
    files = {}
    for file in sorted(root.rglob("*")):
        relative = file.relative_to(root).as_posix()
        if file.is_file() and file.name != ".DS_Store" \
                and not any(relative.startswith(prefix) for prefix in module.exclude):
            files[relative] = file
    return files


def hash_objects(paths):
    if not paths:
        return []
    out = subprocess.run(["git", "hash-object", "--stdin-paths", "--no-filters"],
                         input="\n".join(str(p) for p in paths).encode(),
                         capture_output=True, check=True).stdout.decode()
    return out.split()


class BlobStore:
    """Reads upstream blobs, fetching the missing ones in one batch."""

    def __init__(self, repo):
        self.repo = repo
        self.cache = {}

    def prefetch(self, path, refs):
        """Fetches every version of the files under `path` in `refs`.

        A partial clone fetches the blobs a diff needs in one batch, so diffing
        the empty tree against the first ref, then each ref against the next,
        takes one request per ref. Fetching blob IDs directly isn't allowed.
        """
        empty_tree = git(self.repo, "hash-object", "-t", "tree", "--stdin", input=b"").decode().strip()
        for old, new in zip([empty_tree] + refs[:-1], refs):
            git(self.repo, "diff", "--numstat", "--no-renames", old, new, "--", path + "/")

    def read(self, oid):
        if oid not in self.cache:
            self.cache[oid] = git(self.repo, "cat-file", "blob", oid).decode("utf-8", "replace")
        return self.cache[oid]


# MARK: - Normalization

COMMENT_LINE = re.compile(r"^(//|/\*|\*|#pragma mark)")
STRING_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def normalized_lines(text):
    lines = []
    in_block = False
    for raw in text.splitlines():
        line = " ".join(raw.split())
        if in_block:
            in_block = "*/" not in line
            continue
        if line.startswith("/*") and "*/" not in line:
            in_block = True
            continue
        if not line or COMMENT_LINE.match(line):
            continue
        lines.append(re.sub(r"\s*//.*$", "", line))
    return lines


def string_set(text):
    return {s for s in STRING_LITERAL.findall(text) if len(s) >= 4 and "\\(" not in s}


def stem_key(file_name):
    stem = file_name.rsplit(".", 1)[0]
    stem = stem.split("+", 1)[0] if "+" in stem else stem
    if stem.startswith("FIR") and len(stem) > 3 and stem[3].isupper():
        stem = stem[3:]
    return stem


# MARK: - Comparisons

@dataclass
class Result:
    ref: str
    score: float
    detail: str
    differing: list = field(default_factory=list)


def compare_exact(module, repo, refs):
    files = port_files(module)
    port_oids = dict(zip(files, hash_objects(files.values())))
    results = []
    for ref in refs:
        tree = upstream_tree(repo, ref, module.upstream)
        both = [path for path in port_oids if path in tree]
        identical = [path for path in both if tree[path] == port_oids[path]]
        differing = sorted(path for path in both if tree[path] != port_oids[path])
        port_only = len(port_oids) - len(both)
        upstream_only = len(tree) - len(both)
        results.append(Result(
            ref, len(identical) / max(len(port_oids), 1),
            f"{len(identical)}/{len(port_oids)} identical, {len(differing)} differ, "
            f"{port_only} port-only, {upstream_only} upstream-only",
            differing,
        ))
    return results


def compare_ported(module, repo, refs, blobs):
    files = port_files(module)
    trees = {ref: upstream_tree(repo, ref, module.upstream) for ref in refs}

    # Port files and the upstream files they were ported from, by file name.
    wanted_ext = (".swift",) if module.metric == "lines" else (".m", ".h", ".swift")
    port_by_key = {}
    for relative, path in files.items():
        if path.suffix == ".swift":
            port_by_key.setdefault(stem_key(path.name), []).append(path)
    upstream_by_ref = {}
    for ref, tree in trees.items():
        by_key = defaultdict(list)
        for relative, oid in tree.items():
            if relative.endswith(wanted_ext):
                by_key[stem_key(relative.rsplit("/", 1)[-1])].append(oid)
        upstream_by_ref[ref] = by_key

    keys = sorted(key for key in port_by_key if any(key in u for u in upstream_by_ref.values()))
    blobs.prefetch(module.upstream, refs)

    port_text = {key: "\n".join(p.read_text(errors="replace") for p in port_by_key[key])
                 for key in keys}
    weights = {key: max(len(normalized_lines(text)), 1) for key, text in port_text.items()}
    similarity_cache = {}

    def similarity(key, oids):
        cache_key = (key, tuple(sorted(oids)))
        if cache_key not in similarity_cache:
            upstream_text = "\n".join(blobs.read(oid) for oid in sorted(oids))
            if module.metric == "lines":
                ratio = difflib.SequenceMatcher(
                    None, normalized_lines(port_text[key]), normalized_lines(upstream_text),
                    autojunk=False).ratio()
            else:
                ours, theirs = string_set(port_text[key]), string_set(upstream_text)
                ratio = len(ours & theirs) / max(len(ours | theirs), 1)
            similarity_cache[cache_key] = ratio
        return similarity_cache[cache_key]

    results = []
    total_weight = sum(weights.values())
    for ref in refs:
        score = sum(weights[key] * similarity(key, upstream_by_ref[ref][key])
                    for key in keys if upstream_by_ref[ref].get(key)) / max(total_weight, 1)
        present = sum(1 for key in keys if upstream_by_ref[ref].get(key))
        results.append(Result(ref, score, f"{present}/{len(keys)} matched files present"))
    unmatched = sorted(key for key in port_by_key if key not in keys)
    per_file = {key: [Result(ref, similarity(key, upstream_by_ref[ref][key])
                             if upstream_by_ref[ref].get(key) else 0, "") for ref in refs]
                for key in keys}
    return results, len(keys), unmatched, per_file


def closest_by_file(per_file):
    """{file: closest refs}, leaving out files that score the same everywhere."""
    closest = {}
    for key, results in per_file.items():
        best, margin = summarize(None, results)
        if len(best) < len(results):
            closest[key] = (best, margin)
    return closest


def summarize(module, results):
    best_score = max(r.score for r in results)
    best = [r for r in results if abs(r.score - best_score) < 1e-9]
    others = sorted({round(r.score, 6) for r in results if abs(r.score - best_score) >= 1e-9},
                    reverse=True)
    margin = best_score - others[0] if others else best_score
    return best, margin


def ref_range(results):
    labels = [label(r.ref) for r in results]
    return labels[0] if len(labels) == 1 else f"{labels[0]} – {labels[-1]}"


def confidence(metric, best_score, margin):
    if metric == "exact":
        return "exact" if best_score == 1 else ("high" if margin > 0.005 else "medium")
    if margin >= 0.01:
        return "high"
    return "medium" if margin >= 0.002 else "low"


def commit_info(repo, ref):
    sha, date = git(repo, "log", "-1", "--format=%H %cs", ref).decode().split()
    return sha[:12], date


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--since", default="11.0.0", help="oldest release tag to consider")
    parser.add_argument("--module", help="only this module (substring match)")
    parser.add_argument("--offline", action="store_true", help="don't fetch new upstream tags")
    parser.add_argument("--write", type=Path, help="write the summary table to this file")
    parser.add_argument("-v", "--verbose", action="store_true", help="print every ref's score")
    parser.add_argument("--files", action="store_true",
                        help="for ported modules, print the closest release of each file")
    args = parser.parse_args()

    repo = ensure_clone(args.cache, args.offline)
    refs = candidate_refs(repo, args.since)
    blobs = BlobStore(repo)

    rows = []
    for module in select(args.module):
        print(f"\n## {module.name} ({module.metric}: {module.port} ↔ {module.upstream})")
        if module.metric == "exact":
            results = compare_exact(module, repo, refs)
            note = ""
        else:
            results, matched, unmatched, per_file = compare_ported(module, repo, refs, blobs)
            note = f"{matched} files matched by name"
            if unmatched:
                note += f"; no upstream match: {', '.join(unmatched)}"
            closest = closest_by_file(per_file)
            # Files are ported from different releases when a port was
            # updated piecemeal; count where each file is closest.
            starts = defaultdict(int)
            for best, _ in closest.values():
                starts[ref_range(best)] += 1
            spread = ", ".join(f"{n}× {r}" for r, n in sorted(
                starts.items(), key=lambda item: -item[1]))
            print(f"  closest release per file ({len(closest)} of {matched} differ "
                  f"between releases): {spread}")
            if args.files:
                for key, (best, margin) in sorted(closest.items()):
                    print(f"    {key:<45} {ref_range(best):<22} {best[0].score:.3f} "
                          f"(margin {margin:.3f})")
        best, margin = summarize(module, results)
        if args.verbose:
            for r in results:
                print(f"  {label(r.ref):>10}  {r.score:.4f}  {r.detail}")
        sha, date = commit_info(repo, best[-1].ref)
        level = confidence(module.metric, best[0].score, margin)
        if len(best) == len(results):
            level = "unchanged upstream"
        print(f"  best: {ref_range(best)} ({best[0].score:.4f}, margin {margin:.4f}, {level})")
        print(f"  {best[-1].detail}")
        if note:
            print(f"  {note}")
        if module.metric == "exact" and best[-1].differing:
            shown = best[-1].differing[:15]
            print(f"  differs from upstream: {', '.join(shown)}"
                  + (f" … (+{len(best[-1].differing) - len(shown)})" if len(best[-1].differing) > 15 else ""))
        rows.append((module, best, margin, level, sha, date, note or best[-1].detail))

    if args.write:
        table = [
            "| Module | Port | Upstream | Synced to | Closest releases | Commit | Score | Confidence |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for module, best, margin, level, sha, date, _ in rows:
            table.append(f"| {module.name} | `{module.port}` | `{module.upstream}` | "
                         f"**{module.synced_to}** | {ref_range(best)} | `{sha}` ({date}) | "
                         f"{best[0].score:.3f} (±{margin:.3f}) | {level} |")
        write_table(args.write, "\n".join(table))
        print(f"\nWrote {args.write}")


BEGIN, END = "<!-- baselines:begin -->", "<!-- baselines:end -->"


def write_table(path, table):
    """Replaces the generated section of `path`, keeping what's around it."""
    text = path.read_text() if path.exists() else f"{BEGIN}\n{END}\n"
    if BEGIN not in text or END not in text:
        sys.exit(f"{path} has no {BEGIN} … {END} section to replace")
    before, rest = text.split(BEGIN, 1)
    after = rest.split(END, 1)[1]
    generated = (f"{BEGIN}\n<!-- Generated by scripts/upstream/baselines.py --write; "
                 f"don't edit by hand. -->\n{table}\n{END}")
    path.write_text(before + generated + after)


if __name__ == "__main__":
    main()
