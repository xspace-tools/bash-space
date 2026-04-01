#!/usr/bin/env bash
# x-space/update.sh
#
# Pull the latest xspace repo from origin and re-run install.sh so any
# new bin scripts, lib files, or config changes take effect immediately.
#
# Usage:
#   cd x-space && ./update.sh
#   ./update.sh --skip-pull    # re-install only, no git pull

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Renamed bash-space → x-space; XSPACE_ROOT auto-detected;
#             --skip-pull flag added; output uses consistent log helpers.
#   v0.1.0 — Initial update script. git pull + re-symlink.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────

_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="$(cd "$_SELF_DIR/.." && pwd)"

ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠  $*"; }
hr()   { echo ""; echo "  ── $* ──────────────────────────────────────────────────"; }

SKIP_PULL=0
for arg in "$@"; do
    [[ "$arg" == "--skip-pull" ]] && SKIP_PULL=1
done

# ─────────────────────────────────────────────────────────────────────────────
# PULL
# ─────────────────────────────────────────────────────────────────────────────

if (( SKIP_PULL == 0 )); then
    hr "Git pull"
    cd "$XSPACE_ROOT"
    if git pull --ff-only origin main; then
        ok "Up to date"
    else
        warn "git pull failed — check your remote and branch name."
        warn "To skip the pull: ./update.sh --skip-pull"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# RE-INSTALL
# ─────────────────────────────────────────────────────────────────────────────

hr "Re-running install"
exec "$_SELF_DIR/install.sh"