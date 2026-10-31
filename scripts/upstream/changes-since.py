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

"""Lists the upstream changes a module hasn't been synced with yet.

For the modules matching MODULE, prints a Markdown triage checklist of what
changed upstream between their `synced_to` release (scripts/upstream/upstream.py)
and the target release:

- the module's CHANGELOG entries for the releases in between;
- every upstream commit that touched the module's sources, with a guess at
  whether it's a fix, a feature or maintenance.

For vendored modules (Firestore), --patch also writes the upstream diff with
paths rewritten to this repository, for `git apply --reject`.

Usage: scripts/upstream/changes-since.py MODULE [--to RELEASE|main]
           [--output FILE] [--patch FILE]
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

from upstream import (DEFAULT_CACHE, UPSTREAM_WEB, ensure_clone, git, label, release_tags,
                      select, version_key)

FIX = re.compile(r"\bfix(es|ed|ing)?\b|\bcrash|\bbug\b|\bleak|\brace\b|\bregression", re.I)
FEATURE = re.compile(r"^feat|\badd(s|ed)? (support|api)|\bnew api\b|\bsupport for\b|\bintroduce", re.I)
MAINTENANCE = re.compile(
    r"^(chore|style|refactor|docs?|ci|build|test|lint|format)\b|\bbump\b|\bversion\b|"
    r"\bformat(ting)?\b|\btypo|\bcleanup|\bclean up|\bcopyright|\bdeprecat|\bwarning", re.I)
PR = re.compile(r"\(#(\d+)\)")


def guess(subject):
    if FIX.search(subject):
        return "fix?"
    if FEATURE.search(subject):
        return "feature?"
    if MAINTENANCE.search(subject):
        return "maintenance?"
    return "?"


def link_prs(text):
    return PR.sub(lambda m: f"([#{m[1]}]({UPSTREAM_WEB}/pull/{m[1]}))", text)


def changelog_sections(repo, path, since, to):
    """[(heading, entries)] for the releases after `since`, up to `to`."""
    try:
        text = git(repo, "show", f"{to}:{path}").decode()
    except Exception:
        return []
    sections, current = [], None
    for line in text.splitlines():
        if line.startswith("# "):
            heading = line[2:].strip()
            current = None
            if heading.lower() == "unreleased":
                if to == "origin/main":
                    current = (heading, [])
            elif re.fullmatch(r"\d+\.\d+\.\d+", heading):
                if version_key(heading) > version_key(since) and \
                        (to == "origin/main" or version_key(heading) <= version_key(to)):
                    current = (heading, [])
            if current:
                sections.append(current)
        elif current is not None and line.strip():
            if line.startswith("- "):
                current[1].append(line[2:].strip())
            elif current[1]:
                current[1][-1] += " " + line.strip()
    return [section for section in sections if section[1]]


def commits(repo, since, to, paths):
    """[(hash, date, subject, files)] touching `paths`, oldest first."""
    out = git(repo, "log", "--reverse", "--no-merges", "--name-only",
              "--format=%x01%H%x00%as%x00%s", f"{since}..{to}", "--", *paths).decode()
    result = []
    for chunk in out.split("\x01")[1:]:
        header, _, names = chunk.partition("\n")
        sha, day, subject = header.split("\x00")
        result.append((sha, day, subject, [n for n in names.splitlines() if n]))
    return result


def short_files(files, modules):
    """Files relative to their module, at most five of them."""
    shown = []
    for name in files:
        for module in modules:
            if name.startswith(module.upstream + "/"):
                name = name[len(module.upstream) + 1:]
                break
        shown.append(name)
    extra = f" (+{len(shown) - 5})" if len(shown) > 5 else ""
    return ", ".join(f"`{name}`" for name in shown[:5]) + extra


def write_patch(repo, modules, since, to, path):
    parts = []
    for module in modules:
        parts.append(git(repo, "diff", "--binary", "--no-renames",
                         f"--relative={module.upstream}/",
                         f"--src-prefix=a/{module.port}/", f"--dst-prefix=b/{module.port}/",
                         since, to, "--", module.upstream + "/").decode())
    Path(path).write_text("".join(parts))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("module", help="module name, or part of it (e.g. Firestore, Auth)")
    parser.add_argument("--to", help="target release, or main (default: the latest release)")
    parser.add_argument("--output", type=Path, help="write the checklist here, not to stdout")
    parser.add_argument("--force", action="store_true",
                        help="overwrite --output even if items in it are ticked off")
    parser.add_argument("--patch", type=Path, help="write the upstream diff here (exact modules)")
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--offline", action="store_true", help="don't fetch new upstream tags")
    args = parser.parse_args()

    modules = select(args.module)
    repo = ensure_clone(args.cache, args.offline)
    to = "origin/main" if args.to == "main" else (args.to or release_tags(repo)[-1])
    since = min((m.synced_to for m in modules), key=version_key)
    if len({m.synced_to for m in modules}) > 1:
        print(f"note: the modules are synced to different releases; listing from {since}",
              file=sys.stderr)
    paths = [m.upstream + "/" for m in modules]

    names = ", ".join(m.name for m in modules)
    lines = [f"# {names}: upstream changes {since} → {label(to)}", "",
             f"Generated by `scripts/upstream/changes-since.py {args.module}"
             f"{' --to ' + args.to if args.to else ''}` on {date.today()}. "
             "Tick off each item once it's ported, or note why it doesn't apply.", ""]

    for changelog in dict.fromkeys(m.changelog for m in modules):
        sections = changelog_sections(repo, changelog, since, to)
        lines += [f"## CHANGELOG (`{changelog}`)", ""]
        if not sections:
            lines += ["No entries.", ""]
        for heading, entries in sections:
            lines.append(f"### {heading}")
            lines += [f"- [ ] {link_prs(entry)}" for entry in entries]
            lines.append("")

    found = commits(repo, since, to, paths)
    lines += [f"## Commits ({len(found)})", "",
              "Commits that touched the module's upstream sources, oldest first. The "
              "category is a guess from the subject.", ""]
    for sha, day, subject, files in found:
        lines.append(f"- [ ] [`{sha[:9]}`]({UPSTREAM_WEB}/commit/{sha}) {day} "
                     f"**{guess(subject)}** {link_prs(subject)}  \n"
                     f"  {short_files(files, modules)}")
    output = "\n".join(lines).rstrip() + "\n"

    if args.output:
        # A checklist with ticked items holds triage decisions; don't lose them.
        if args.output.exists() and "- [x]" in args.output.read_text() and not args.force:
            sys.exit(f"{args.output} has ticked-off items; pass --force to overwrite it")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
        print(f"Wrote {args.output}: {len(found)} commits", file=sys.stderr)
    else:
        sys.stdout.write(output)

    if args.patch:
        if any(m.metric != "exact" for m in modules):
            sys.exit("--patch only makes sense for vendored (exact) modules")
        write_patch(repo, modules, since, to, args.patch)
        print(f"Wrote {args.patch}; apply with: git apply --reject {args.patch}", file=sys.stderr)


if __name__ == "__main__":
    main()
