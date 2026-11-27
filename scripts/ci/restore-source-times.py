#!/usr/bin/python3 -I
"""Makes a restored build cache usable after a fresh checkout.

A checkout gives every file a new modification time, and the build system treats a new time as a changed file,
so a cached `.build` would be rebuilt from scratch. This pins the time of every tracked file whose content is
the same as when the cache was written to a fixed past value; files that changed keep the checkout time and are
the only ones rebuilt. The content record (git blob ids) is stored next to the cache and rewritten each run.

usage: restore-source-times.py <record-file>
"""
import json
import os
import subprocess
import sys

FIXED = 1577836800  # 2020-01-01T00:00:00Z

def tracked_blobs():
    """Git blob id of the working-tree content of every tracked regular file (what the build reads)."""
    names = [n.decode("utf-8", "surrogateescape") for n in subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0") if n]
    paths = [n for n in names if os.path.isfile(n) and not os.path.islink(n) and "\n" not in n]
    ids = subprocess.run(["git", "hash-object", "--stdin-paths"], input="\n".join(paths), check=True,
                         capture_output=True, text=True, errors="surrogateescape").stdout.split()
    return dict(zip(paths, ids))

def main(record_path):
    current = tracked_blobs()
    try:
        with open(record_path, encoding="utf-8") as handle:
            previous = json.load(handle)
    except (OSError, ValueError):
        previous = {}
    pinned = 0
    for path, blob in current.items():
        if previous.get(path) == blob and os.path.isfile(path) and not os.path.islink(path):
            os.utime(path, (FIXED, FIXED))
            pinned += 1
    os.makedirs(os.path.dirname(record_path) or ".", exist_ok=True)
    with open(record_path, "w", encoding="utf-8") as handle:
        json.dump(current, handle)
    print(f"build cache: {pinned} of {len(current)} files unchanged since the cache was written")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
