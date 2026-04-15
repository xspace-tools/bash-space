#!/usr/bin/env bash
# _configure/lib/update.sh
#
# Pull the latest xspace repo from origin and re-run install.sh.
#
# Usage:
#   _configure/lib/update.sh
#   _configure/lib/update.sh --skip-pull
#   updatex                               # after first install
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.4.0 — Moved to _configure/lib/ alongside install.sh. Bootstrap updated:
#             _LIB_DIR / _X_DIR / XSPACE_ROOT resolved correctly from lib/.
#             install.sh called with --no-pause so the window doesn't wait
#             twice; update.sh pauses once at the very end instead.
#   v0.3.0 — Folder renamed x-space/ -> _configure/. Path comment updated.
#             No functional changes — BASH_SOURCE[0] resolution is unchanged.
#   v0.2.0 — XSPACE_ROOT auto-detected. --skip-pull flag added.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ok()   { echo "  + $*"; }
warn() { echo "  ! $*"; }
hr()   { echo ""; echo "  -- $* ---------------------------------------------------"; }

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP  (same portable resolver as install.sh)
# ─────────────────────────────────────────────────────────────────────────────

_readlink_f() {
    local target="$1"
    if readlink -f "$target" &>/dev/null 2>&1; then
        readlink -f "$target"; return
    fi
    if command -v greadlink &>/dev/null; then
        greadlink -f "$target"; return
    fi
    local dir; dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)"
    echo "${dir}/$(basename "$target")"
}

_LIB_DIR="$(cd "$(dirname "$(_readlink_f "${BASH_SOURCE[0]}")")" && pwd)"
_X_DIR="$(cd "$_LIB_DIR/.." && pwd)"
XSPACE_ROOT="$(cd "$_X_DIR/.." && pwd)"

SKIP_PULL=0
for arg in "$@"; do
    [[ "$arg" == "--skip-pull" ]] && SKIP_PULL=1
done

# ─────────────────────────────────────────────────────────────────────────────
# GIT PULL
# ─────────────────────────────────────────────────────────────────────────────

if (( SKIP_PULL == 0 )); then
    hr "Git pull"
    cd "$XSPACE_ROOT"
    if git pull --ff-only origin main; then
        ok "Up to date"
    else
        warn "git pull failed — check remote and branch name."
        warn "To skip the pull: update.sh --skip-pull"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# RE-RUN INSTALL
# ─────────────────────────────────────────────────────────────────────────────

hr "Re-running installer"

# --no-pause: install.sh should not wait for Enter because we pause here.
"$_LIB_DIR/install.sh" --no-pause

# ─────────────────────────────────────────────────────────────────────────────
# PAUSE  (single pause point for the whole update flow)
# ─────────────────────────────────────────────────────────────────────────────

echo "  Press Enter to close..."
read -r _
echo ""