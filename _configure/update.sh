#!/usr/bin/env bash
# _configure/update.sh
#
# Pull the latest xspace repo from origin and re-run install.sh.
#
# Usage:
#   _configure/update.sh
#   _configure/update.sh --skip-pull

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.3.0 — Folder renamed x-space/ → _configure/. Path comment updated.
#             No functional changes — BASH_SOURCE[0] resolution is unchanged.
#   v0.2.0 — XSPACE_ROOT auto-detected. --skip-pull flag added.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠  $*"; }
hr()   { echo ""; echo "  ── $* ──────────────────────────────────────────────────"; }

_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="$(cd "$_SELF_DIR/.." && pwd)"

SKIP_PULL=0
for arg in "$@"; do
    [[ "$arg" == "--skip-pull" ]] && SKIP_PULL=1
done

if (( SKIP_PULL == 0 )); then
    hr "Git pull"
    cd "$XSPACE_ROOT"
    if git pull --ff-only origin main; then
        ok "Up to date"
    else
        warn "git pull failed — check remote and branch name."
        warn "To skip the pull: _configure/update.sh --skip-pull"
        exit 1
    fi
fi

hr "Re-running install"
exec "$_SELF_DIR/install.sh"