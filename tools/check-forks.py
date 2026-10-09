#!/usr/bin/env python3
"""Fail when the repo diverges from upstream pstack without a FORKS.md row.

Reads the snapshot SHA from FORKS.md, fetches upstream at that SHA (or uses
--upstream <path> to a local checkout), maps upstream paths to repo paths by
substituting poteto with factory, normalizes file contents the same way, and
then requires: a missing mapped file to match a Dropped row, a differing file
to match a Modified row, a repo file with no upstream counterpart to match an
Added row, and every row to still match something. Table rows list backticked
patterns; a pattern ending in / covers the tree below it, * globs, and a
slashless pattern resolves against the row's first pattern.
"""
import argparse
import fnmatch
import os
import re
import subprocess
import sys
import tempfile

UPSTREAM_URL = "https://github.com/cursor/plugins"
UPSTREAM_DIR = "pstack"


def run(args, **kw):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)


def parse_forks(path):
    text = open(path, encoding="utf-8").read()
    sha = re.search(r"compared snapshot is `([0-9a-f]{40})`", text)
    if not sha:
        sys.exit("FORKS.md: no compared-snapshot SHA in the header")
    tables = {"Dropped": [], "Added": [], "Modified": []}
    section = None
    for line in text.splitlines():
        m = re.match(r"## (\w+)", line)
        if m:
            section = m.group(1) if m.group(1) in tables else None
            continue
        if section and line.startswith("|") and not re.match(r"\|[-\s|]+\|$", line):
            cell = line.split("|")[1]
            pats = re.findall(r"`([^`]+)`", cell)
            pats = [p for p in pats if not re.fullmatch(r"[0-9a-f]{40}", p)]
            if not pats or pats[0] in ("Path",):
                continue
            base = pats[0]
            basedir = base if base.endswith("/") else os.path.dirname(base) + "/"
            resolved = [base] + [p if "/" in p else basedir + p for p in pats[1:]]
            tables[section].extend(resolved)
    return sha.group(1), tables


def matches(path, patterns):
    for p in patterns:
        if p.endswith("/"):
            if path.startswith(p):
                return True
        elif "*" in p:
            if fnmatch.fnmatch(path, p):
                return True
        elif path == p:
            return True
    return False


def files_under(root):
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    return [f for f in out if f]


def normalize(data):
    return data.replace(b"Poteto", b"Factory").replace(b"poteto", b"factory")


def fetch_upstream(sha):
    tmp = tempfile.mkdtemp(prefix="pstack-upstream-")
    run(["git", "init", "--quiet", tmp])
    run(["git", "-C", tmp, "remote", "add", "origin", UPSTREAM_URL])
    run(["git", "-C", tmp, "fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", sha])
    run(["git", "-C", tmp, "sparse-checkout", "set", UPSTREAM_DIR])
    run(["git", "-C", tmp, "checkout", "--quiet", "FETCH_HEAD"])
    return os.path.join(tmp, UPSTREAM_DIR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--upstream", help="local upstream pstack checkout; otherwise fetched by SHA")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    sha, tables = parse_forks(os.path.join(repo, "FORKS.md"))
    upstream = os.path.abspath(args.upstream) if args.upstream else fetch_upstream(sha)

    up_files = []
    for dp, _, fs in os.walk(upstream):
        if ".git" in dp.split(os.sep):
            continue
        for fn in fs:
            up_files.append(os.path.relpath(os.path.join(dp, fn), upstream))

    repo_files = files_under(repo)
    mapped = {}
    problems = []
    dropped, modified, added = [], [], []

    for u in sorted(up_files):
        m = u.replace("poteto", "factory")
        mapped[m] = u
        target = os.path.join(repo, m)
        if not os.path.exists(target):
            dropped.append(u)
            if not matches(u, tables["Dropped"]):
                problems.append(f"undeclared drop: upstream {u} has no {m} and no Dropped row")
            continue
        a = normalize(open(os.path.join(upstream, u), "rb").read())
        b = open(target, "rb").read()
        if a != b:
            modified.append(m)
            if not matches(m, tables["Modified"]):
                problems.append(f"undeclared fork: {m} differs from upstream {u} with no Modified row")

    for r in sorted(repo_files):
        if r not in mapped:
            added.append(r)
            if not matches(r, tables["Added"]):
                problems.append(f"undeclared addition: {r} has no upstream counterpart and no Added row")

    universe = {"Dropped": dropped, "Added": added, "Modified": modified}
    for table, pats in tables.items():
        for p in pats:
            if not any(matches(x, [p]) for x in universe[table]):
                problems.append(f"stale {table} row: `{p}` matches nothing")

    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s) against upstream {sha[:7]}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
