#!/usr/bin/env python3
"""Fail when a markdown file under skills/, docs/, or agents/ references a
repo path that does not exist.

A reference is a relative markdown link target, or a backticked path that
starts with ./, ../, or one of the repo's directory names. Candidates
containing glob or placeholder characters are skipped. Each candidate is
resolved against the file's own directory, its skill root, and the repo
root, and counts as dangling only when none resolve.
"""
import os
import re
import sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
skills = os.path.join(root, "skills")
link = re.compile(r"\]\(([^)#\s]+)")
tick = re.compile(r"`((?:\.\.?/|playbooks/|references/|scripts/|agents/|skills/|docs/|hooks/|tools/)[^`\s]*)`")


def skill_root(d):
    while d.startswith(skills) and d != skills:
        if os.path.exists(os.path.join(d, "SKILL.md")):
            return d
        d = os.path.dirname(d)
    return None


bad = []
for scan in (skills, os.path.join(root, "docs"), os.path.join(root, "agents")):
    for dp, _, fs in os.walk(scan):
        for fn in fs:
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            sr = skill_root(dp)
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    cands = [
                        m
                        for m in link.findall(line)
                        if not re.match(r"(https?:|mailto:)", m) and ("/" in m or "." in m)
                    ]
                    cands += tick.findall(line)
                    for c in cands:
                        c = c.rstrip("/")
                        if any(ch in c for ch in "<>*~${}|"):
                            continue
                        c = c.split(":")[0]
                        bases = [dp, sr, root, skills] if sr else [dp, root, skills]
                        if not any(os.path.exists(os.path.normpath(os.path.join(b, c))) for b in bases):
                            bad.append(f"{os.path.relpath(p, root)}:{i}: {c}")

for b in sorted(set(bad)):
    print(b)
print(f"{len(set(bad))} dangling reference(s)")
sys.exit(1 if bad else 0)
