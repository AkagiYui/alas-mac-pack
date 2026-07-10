#!/usr/bin/env python3
"""
Strip duplicate LC_RPATH load commands from every Mach-O in a directory tree and
re-sign the ones that change.

macOS 15 (Sequoia) dyld rejects a Mach-O that carries duplicate LC_RPATH entries
(treating e.g. `@loader_path` and `@loader_path/` as the same). Several conda /
anaconda arm64 libraries (libopenblas, libgfortran, libcblas, numpy's
_multiarray_umath.so, ...) ship such duplicates, which makes `import numpy` fail
at runtime with:

    Library not loaded: @rpath/libgfortran.5.dylib ... (duplicate LC_RPATH '@loader_path')

Older macOS tolerated it, which is why it isn't caught on macos-14 CI runners.

Usage: fix-env-rpaths.py <dir>
"""
import os
import subprocess
import sys

MACHO_MAGIC = {
    b"\xcf\xfa\xed\xfe",  # MH_MAGIC_64 (LE)
    b"\xce\xfa\xed\xfe",  # MH_MAGIC (LE)
    b"\xca\xfe\xba\xbe",  # FAT_MAGIC (universal)
    b"\xbe\xba\xfe\xca",  # FAT_CIGAM
}


def is_macho(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(4) in MACHO_MAGIC
    except OSError:
        return False


def rpaths(path):
    """Return the LC_RPATH path strings, in order."""
    out = subprocess.run(
        ["otool", "-l", path], capture_output=True, text=True
    ).stdout
    result, lines = [], out.splitlines()
    for i, line in enumerate(lines):
        if "cmd LC_RPATH" in line:
            # the `path <value> (offset N)` line is 2 lines below
            for j in range(i + 1, min(i + 4, len(lines))):
                s = lines[j].strip()
                if s.startswith("path "):
                    val = s[len("path "):]
                    val = val.rsplit(" (offset", 1)[0]
                    result.append(val)
                    break
    return result


def fix(path):
    """Delete duplicate (normalized) rpaths; return True if changed."""
    changed = False
    while True:
        seen, dup = set(), None
        for p in rpaths(path):
            norm = p.rstrip("/")
            if norm in seen:
                dup = p
                break
            seen.add(norm)
        if dup is None:
            break
        r = subprocess.run(
            ["install_name_tool", "-delete_rpath", dup, path],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            sys.stderr.write(f"  ! failed to fix {path}: {r.stderr.strip()}\n")
            break
        changed = True
    if changed:
        subprocess.run(
            ["codesign", "--force", "--sign", "-", path],
            capture_output=True, text=True,
        )
    return changed


def main():
    root = sys.argv[1]
    fixed = 0
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            p = os.path.join(dirpath, name)
            if os.path.islink(p) or not is_macho(p):
                continue
            if fix(p):
                fixed += 1
                print(f"  fixed rpaths: {os.path.relpath(p, root)}")
    print(f"fix-env-rpaths: de-duplicated LC_RPATH in {fixed} Mach-O file(s)")


if __name__ == "__main__":
    main()
