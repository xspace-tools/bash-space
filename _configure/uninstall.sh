#!/usr/bin/env bash
# _configure/uninstall.sh
#
# Removes everything _configure/install.sh put onto the system.
# Safe even if install was only partially completed.
#
# Removes: ~/bin symlinks for all space scripts, PATH lines for all
#          space bin dirs, gitspace completion line, stale RC lines,
#          .xspace/installed marker.
#
# Does NOT touch: the xspace repo, tool directories, fonts, exports,
#                 logs, or backup-space/config/backups.conf.
#
# Usage:
#   cd xspace/_configure && ./uninstall.sh

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.3.0 — Folder renamed x-space/ → _configure/. Path comment and
#             marker path updated. No other changes.
#   v0.2.0 — Loops XSPACE_ALL_BIN_DIRS; _X_DIR fix.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────

_X_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="$(cd "$_X_DIR/.." && pwd)"

CONF="$XSPACE_ROOT/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo "uninstall.sh: xspace.conf not found at $CONF — cannot proceed."
    exit 1
fi
source "$CONF"

USER_BIN="${USER_BIN:-${USER_BIN_DEFAULT}}"
_X_MARKER="$_X_DIR/.xspace"
ABS_GITSPACE_COMPLETION="$XSPACE_ROOT/$GITSPACE_COMPLETION"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠  $*"; }
hr()   { echo ""; echo "  ── $* ──────────────────────────────────────────────────"; }

remove_line_from_rc() {
    local rc="$1" line="$2" label="$3"
    [[ ! -f "$rc" ]] && return 0
    if grep -Fxq "$line" "$rc" 2>/dev/null; then
        local tmp; tmp="$(mktemp)"
        grep -Fxv "$line" "$rc" > "$tmp"
        mv "$tmp" "$rc"
        ok "Removed from RC: $label"
    else
        ok "Not in RC: $label"
    fi
}

remove_pattern_from_rc() {
    local rc="$1" pattern="$2" label="$3"
    [[ ! -f "$rc" ]] && return 0
    if grep -q "$pattern" "$rc" 2>/dev/null; then
        local tmp; tmp="$(mktemp)"
        grep -v "$pattern" "$rc" > "$tmp"
        mv "$tmp" "$rc"
        ok "Removed stale lines: $label"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRM
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace uninstaller v0.3.0"
echo "  root    : $XSPACE_ROOT"
echo "  removes : ~/bin symlinks, PATH lines, RC entries, installed marker"
echo "  keeps   : repo, tool dirs, fonts, exports, logs, backups.conf"
echo ""
read -rp "  Proceed? (y/N): " _confirm
if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
fi

if   [[ -n "${ZSH_VERSION-}"  ]]; then SHELL_RC="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION-}" ]]; then SHELL_RC="$HOME/.bashrc"
else                                    SHELL_RC="$HOME/.profile"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — REMOVE SYMLINKS AND PATH LINES
# ─────────────────────────────────────────────────────────────────────────────
hr "Space bins — symlinks + PATH lines"

for rel_bin in "${XSPACE_ALL_BIN_DIRS[@]}"; do
    abs_bin="$XSPACE_ROOT/$rel_bin"

    PATH_LINE="[[ \":$PATH:\" != *\":${abs_bin}:\"* ]] && PATH=\"${abs_bin}:\$PATH\""
    remove_line_from_rc "$SHELL_RC" "$PATH_LINE" "${rel_bin} on PATH"

    if [[ -d "$abs_bin" ]]; then
        removed=0
        for f in "$abs_bin"/*; do
            [[ -f "$f" ]] || continue
            name="$(basename "$f")"
            target="$USER_BIN/$name"
            if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$f" ]]; then
                rm "$target"
                (( ++removed ))
            fi
        done
        ok "${rel_bin} — removed $removed symlink(s)"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — REMAINING RC LINES
# ─────────────────────────────────────────────────────────────────────────────
hr "Shell RC cleanup"

SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
remove_line_from_rc "$SHELL_RC" "$SAFE_ADD" "~/bin on PATH"

COMP_LINE="[[ -f \"$ABS_GITSPACE_COMPLETION\" ]] && source \"$ABS_GITSPACE_COMPLETION\""
remove_line_from_rc "$SHELL_RC" "$COMP_LINE" "gitspace completion"

remove_pattern_from_rc "$SHELL_RC" "gitspace-completion.sh" "stale gitspace-completion lines"

# Also clean up any old PATH entries that still reference x-space/bin
remove_pattern_from_rc "$SHELL_RC" "x-space/bin" "stale x-space/bin PATH lines"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — MARKER
# ─────────────────────────────────────────────────────────────────────────────
hr "Marker"

if [[ -f "$_X_MARKER/installed" ]]; then
    rm "$_X_MARKER/installed"
    ok "Removed .xspace/installed"
else
    ok "No installed marker found"
fi

echo ""
echo "  ── Uninstall complete ────────────────────────────────────────"
echo ""
echo "  Open a new terminal or: source ~/$( basename "$SHELL_RC" )"
echo "  Re-install: cd $XSPACE_ROOT/_configure && ./install.sh"
echo ""