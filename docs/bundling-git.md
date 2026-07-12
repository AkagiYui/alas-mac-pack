# Bundling a relocatable `git` into a macOS app

How this project ships a working `git` *inside* the packaged `.app`, so the app's
in-app self-update (`git fetch` + `git reset --hard origin/master`) works on an
end user's Mac **without** requiring them to install anything (no Xcode Command
Line Tools, no Homebrew, no system git).

Both build profiles use the shared helper [`scripts/bundle-git.sh`](../scripts/bundle-git.sh),
which produces `payload/git/`. `deploy.yaml` then points `GitExecutable` at
`../git/git`.

This document exists because getting a *relocatable* git on macOS has several
non-obvious traps; the notes below should save the next person (or the next
app) the same investigation.

## The requirement

A "bundled" tool must be **relocatable** and **self-contained**:

- **Relocatable** — it must work no matter where the user drags the `.app`. It
  cannot depend on any absolute path that was valid on the *build* machine.
- **Self-contained** — it must not depend on libraries or helper binaries that
  only exist on the build machine (Homebrew dylibs, a system git, …).

A tool that passes on the build machine but fails on a clean Mac is the failure
mode to watch for — the build machine has Homebrew, Xcode, a system git, etc.,
so it hides every dependency.

## Why this is tricky for git specifically

Two macOS/git facts drive the whole design:

1. **git is not built with `RUNTIME_PREFIX`.** git shells out to helper binaries
   (`git-remote-https`, …) that live in its *exec-path* (`libexec/git-core`). On
   most builds that path — and the CA-bundle path — is **compiled in as an
   absolute path**. Move the install and git can no longer find `git-remote-https`:

   ```
   git: 'remote-https' is not a git command.
   fatal: remote helper 'https' aborted session
   ```

2. **HTTPS needs a TLS stack + a CA trust store.** How git gets these decides how
   heavy the bundle is:
   - Link an OpenSSL-based libcurl → you must also ship OpenSSL **and** a CA
     bundle (`cacert.pem`), and point git at it. Heavy, and the baked CA path is
     another absolute-path relocation trap.
   - Link the **system** `/usr/lib/libcurl` → TLS goes through macOS **Secure
     Transport**, which trusts the **system keychain** roots. Nothing to ship.

## The approach we chose: bundle Apple's git

The git that ships with **Xcode / the Command Line Tools** is **purely
system-linked**. Verify with `otool -L` on the transport helper — every entry is
under `/usr/lib` or `/System`:

```
$ otool -L "$(xcrun --find git | xargs dirname)/../libexec/git-core/git-remote-http"
    /System/Library/Frameworks/CoreServices.framework/... CoreServices
    /usr/lib/libcurl.4.dylib          # system libcurl -> Secure Transport
    /usr/lib/libexpat.1.dylib
    /usr/lib/libz.1.dylib
    /usr/lib/libiconv.2.dylib
    /usr/lib/libSystem.B.dylib
```

So there is **nothing to relocate and nothing to ship** except the git binaries
themselves. `bundle-git.sh` copies only:

```
payload/git/
├── git                              # self-locating wrapper (see below)
├── libexec/git-core/
│   ├── git                          # the dispatcher binary
│   ├── git-remote-http              # smart-HTTPS transport helper
│   └── git-remote-https -> git-remote-http
└── share/git-core/templates/        # so `git init` doesn't warn
```

~6 MB total. TLS via Secure Transport + system keychain → **no OpenSSL, no CA
bundle, no ICU, no perl**.

### The wrapper solves trap #1

Because git isn't `RUNTIME_PREFIX`, we don't run the binary directly. We run a
tiny wrapper that re-points the exec-path (and template dir) at the bundle,
relative to its own location:

```sh
#!/bin/sh
here="$(cd "$(dirname "$0")" && pwd)"
export GIT_EXEC_PATH="$here/libexec/git-core"
export GIT_TEMPLATE_DIR="$here/share/git-core/templates"
exec "$here/libexec/git-core/git" "$@"
```

`deploy.yaml`'s `GitExecutable: ../git/git` points at this wrapper. (`../git/git`
is relative to the repo root `payload/app`; the deploy module's
`config.py:filepath()` resolves it to `payload/git/git`.)

### The guard prevents shipping a fragile git

`bundle-git.sh` runs `otool -L` on `git-remote-http` and **aborts the build** if
it finds any non-`/usr/lib`, non-`/System` dependency. This is what stops us from
accidentally bundling **Homebrew's** git, which links
`/opt/homebrew/.../libpcre2-8.0.dylib` and `libintl.8.dylib` — see below.

## Dead ends (why the obvious options are wrong)

- **`GitExecutable: git` (bare name).** `filepath()` treats it as relative and
  resolves it to `payload/app/git`, which doesn't exist → a noisy
  `GitExecutable: … does not exist, use 'git' instead` warning at every startup
  before falling back to PATH git (which the user may not have). This was the
  original bug that started this whole investigation.

- **Copy the Homebrew `git` binary alone** (what the old Platypus package did:
  a lone 3.4 MB `Resources/git/bin/git`). It only ran because the *build machine*
  had Homebrew: the binary hard-links `/opt/homebrew/.../libpcre2` + `libintl`
  (dyld can't even load it without them) and borrows Homebrew's
  `git-remote-https` via a compiled-in `/opt/homebrew/opt/git/libexec/git-core`
  exec-path. On a clean Mac it fails to launch. **Passing on your machine ≠
  working for users.**

- **conda-forge git via micromamba.** Genuinely self-contained, but ~78 MB: its
  libcurl links OpenSSL **and** `libpsl` → **ICU** (`libicudata` alone is 32 MB;
  drop it and `git-remote-https` aborts with signal 6). It also bakes absolute
  exec-path + CA paths, so it needs the same wrapper *plus* `GIT_SSL_CAINFO`
  fixups. Works, but an order of magnitude larger for no benefit over Apple git.

- **conda env git** (the old alas approach, `../miniforge3/envs/alas/bin/git`).
  Same absolute-path relocation problem as conda-forge git, used *without* a
  wrapper, so self-update silently broke once the `.app` was dragged elsewhere.

## How to verify a bundled tool is actually relocatable

Prove it the way the build machine can't fake — with an **empty environment**,
from a **copied-elsewhere** location, ideally with any build-machine copy removed
from its original path:

```sh
# copy the bundle somewhere unrelated, then run with a scrubbed environment
cp -R payload/git /tmp/reloc
env -i HOME=/tmp PATH=/usr/bin:/bin sh -c '
  cd "$(mktemp -d)"
  /tmp/reloc/git init -q
  /tmp/reloc/git remote add origin https://github.com/octocat/Hello-World.git
  /tmp/reloc/git fetch --depth 1 origin master
  /tmp/reloc/git reset --hard origin/master
'
```

`env -i` strips inherited `GIT_*`/`DYLD_*`/PATH that would otherwise mask a
missing dependency. Also assert **zero** non-system dylib references:

```sh
find payload/git -type f -perm +111 -exec sh -c \
  'otool -L "$1" 2>/dev/null | awk "NR>1{print \$1}" | grep -vE "^/usr/lib|^/System" | grep -q . && echo "LEAK: $1"' _ {} \;
# (no output = clean)
```

## Reusing this for other bundled tools

The general recipe for shipping any macOS CLI tool inside a relocatable app:

1. **Prefer the system-linked build.** Run `otool -L` on the binary *and every
   helper it execs*. If everything is under `/usr/lib` + `/System`, you can copy
   it as-is — done. (Xcode/CLT tools are usually system-linked; Homebrew tools
   usually are not.)
2. **If it must link non-system dylibs**, copy those dylibs into the bundle,
   rewrite install-names to `@rpath/...` (`install_name_tool -id` / `-change`),
   add an `@loader_path`-relative `LC_RPATH`, then `codesign --force --sign -`
   every modified Mach-O (arm64 requires a valid — even ad-hoc — signature).
   Loop `otool -L` until no non-system references remain (catch transitive deps).
3. **If the tool bakes absolute helper/data paths** (not `RUNTIME_PREFIX`), add a
   self-locating `sh` wrapper that exports the relevant `*_PATH` env vars relative
   to `$(dirname "$0")`, and point your config at the wrapper.
4. **For TLS**, prefer a build that links the system libcurl (Secure Transport +
   system keychain) so you don't have to ship OpenSSL + a CA bundle.
5. **macOS 15 note:** dyld rejects duplicate `LC_RPATH` load commands (conda
   arm64 libs ship them). If you bundle such libs, de-dup and re-sign — see
   [`scripts/fix-env-rpaths.py`](../scripts/fix-env-rpaths.py).
6. **Verify** with the empty-env + copied-elsewhere + zero-leaks checks above.
