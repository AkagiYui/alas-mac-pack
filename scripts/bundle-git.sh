#!/bin/bash
# Bundle a self-contained, relocatable macOS git into <payload>/git, for the
# packaged app's in-app self-update (git fetch / reset --hard origin/master).
# Shared by both build profiles (alas + src). See docs/bundling-git.md for the
# full rationale.
#
# Why Apple's git: the git shipped with Xcode / the Command Line Tools is PURELY
# system-linked — its HTTPS transport goes through macOS Secure Transport + the
# system keychain — so there is NO OpenSSL, CA bundle, ICU, or perl to ship. We
# copy only the git binary, the smart-HTTPS transport helper, and the init
# templates (~6MB total). git is not built with RUNTIME_PREFIX, so a tiny wrapper
# points GIT_EXEC_PATH/GIT_TEMPLATE_DIR back at the bundle at runtime. Point
# deploy.yaml's GitExecutable at `../git/git` (relative to the repo root, which
# is payload/app), which config.py filepath() resolves to payload/git/git.
#
# Usage: bundle-git.sh <payload_dir>
set -euo pipefail
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

PAYLOAD="${1:?usage: bundle-git.sh <payload_dir>}"
[ -d "$PAYLOAD" ] || die "payload dir not found: $PAYLOAD"

log "Embedding Apple git (Xcode/CLT, system-linked) -> $PAYLOAD/git"
CLT_GIT="$(xcrun --find git 2>/dev/null || command -v git || true)"
test -x "$CLT_GIT" || die "no git found to bundle (need Xcode Command Line Tools)"
CLT_CORE="$(cd "$(dirname "$CLT_GIT")/../libexec/git-core" 2>/dev/null && pwd || true)"
test -x "$CLT_CORE/git-remote-http" || die "git-remote-http not found next to $CLT_GIT"
CLT_TPL="$(cd "$(dirname "$CLT_GIT")/../share/git-core/templates" 2>/dev/null && pwd || true)"

# Refuse a non-system-linked git (e.g. Homebrew's): it drags in dylibs we don't
# bundle (libpcre2/libintl) and would break on a Mac without Homebrew. The old
# Platypus package shipped exactly such a git and only worked where Homebrew was
# installed — that bug is what this guard prevents.
leaks="$(otool -L "$CLT_CORE/git-remote-http" | awk 'NR>1{print $1}' \
  | grep -vE '^/usr/lib|^/System' || true)"
[ -z "$leaks" ] || die "git-remote-http links non-system libs ($leaks); need the system/Xcode git, not $CLT_GIT"

GITROOT="$PAYLOAD/git"
rm -rf "$GITROOT"
mkdir -p "$GITROOT/libexec/git-core" "$GITROOT/share/git-core"
cp "$CLT_GIT" "$GITROOT/libexec/git-core/git"
cp "$CLT_CORE/git-remote-http" "$GITROOT/libexec/git-core/git-remote-http"
ln -sf git-remote-http "$GITROOT/libexec/git-core/git-remote-https"
[ -n "$CLT_TPL" ] && cp -R "$CLT_TPL" "$GITROOT/share/git-core/templates"

cat > "$GITROOT/git" <<'WRAP'
#!/bin/sh
# Self-locating launcher for the bundled Apple git. git isn't built with
# RUNTIME_PREFIX, so point it at the bundle's helpers and templates. TLS uses
# macOS Secure Transport + the system keychain — no CA bundle is shipped.
here="$(cd "$(dirname "$0")" && pwd)"
export GIT_EXEC_PATH="$here/libexec/git-core"
export GIT_TEMPLATE_DIR="$here/share/git-core/templates"
exec "$here/libexec/git-core/git" "$@"
WRAP
chmod +x "$GITROOT/git"

"$GITROOT/git" --version >/dev/null 2>&1 || die "bundled git is not runnable"
log "Bundled git: $("$GITROOT/git" --version 2>&1) ($(du -sh "$GITROOT" 2>/dev/null | cut -f1))"
