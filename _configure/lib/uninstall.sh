#!/usr/bin/env bash
# _configure/lib/uninstall.sh
#
# Removes everything _configure/lib/install.sh put onto the system.
# Safe even if install was only partially completed.
#
# Removes: ~/bin symlinks for all space scripts, PATH lines for all
#          space bin dirs, gitspace completion RC line (both v0.5.0
#          absolute-path style and v0.6.0 symlink style), the stable
#          symlink at ~/.local/share/xspace/, stale RC lines,
#          .xspace/installed marker.
#
# Does NOT touch: the xspace repo, tool directories, fonts, exports,
#                 logs, or backup-space/config/backups.conf.
#
# Usage:
#   _configure/lib/uninstall.sh
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.5.0 — Moved to _configure/lib/. Bootstrap updated: _LIB_DIR / _X_DIR /
#             XSPACE_ROOT now resolved correctly from the lib/ subdirectory.
#             Portable _readlink_f added (matches install.sh / update.sh).
#   v0.4.0 — Completion removal updated for v0.6.0 symlink pattern.
#             Removes the new _xsp=... RC line, the ~/.local/share/xspace/
#             symlink, and any old absolute-path lines from v0.5.0 (backward
#             compat). All three patterns cleaned in one pass.
#   v0.3.0 — Folder renamed x-space/ -> _configure/. Path comment and
#             marker path updated. No other changes.
#   v0.2.0 — Loops XSPACE_ALL_BIN_DIRS; _X_DIR fix.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
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

CONF="$XSPACE_ROOT/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo "uninstall.sh: xspace.conf not found at $CONF — cannot proceed."
    exit 1
fi
source "$CONF"

USER_BIN="${USER_BIN:-${USER_BIN_DEFAULT}}"
_X_MARKER="$_X_DIR/.xspace"
ABS_GITSPACE_COMPLETION="$XSPACE_ROOT/$GITSPACE_COMPLETION"

# Stable share directory used by v0.6.0 symlink pattern
XSPACE_SHARE="$HOME/.local/share/xspace"
COMP_SYMLINK="$XSPACE_SHARE/gitspace-completion.sh"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

ok()   { echo "  + $*"; }
warn() { echo "  ! $*"; }
hr()   { echo ""; echo "  -- $* ---------------------------------------------------"; }

remove_line_from_rc() {
    local rc="$1" line="$2" label="$3"
    [[ ! -f "$rc" ]] && return 0
    if grep -Fxq "$line" "$rc" 2>/dev/null; then
        local tmp; tmp="$(mktemp)"
        grep -Fxv "$line" "$rc" > "$tmp"
        mv "$tmp" "$rc"
        ok "Removed from RC: $label"
    else
        ok "Not in RC (already clean): $label"
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
    else
        ok "Not found (already clean): $label"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRM
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace uninstaller v0.5.0"
echo "  root    : $XSPACE_ROOT"
echo "  removes : ~/bin symlinks, PATH lines, RC entries, completion"
echo "            symlink (~/.local/share/xspace/), installed marker"
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
                (( ++removed )) || true
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

# v0.6.0 completion line — the stable $HOME-relative pattern
COMP_LINE_V6='_xsp="$HOME/.local/share/xspace/gitspace-completion.sh"; [[ -f "$_xsp" ]] && source "$_xsp"; unset _xsp'
remove_line_from_rc "$SHELL_RC" "$COMP_LINE_V6" "gitspace completion (v0.6.0 symlink line)"

# v0.5.0 and earlier — absolute path style (path varies by machine)
remove_pattern_from_rc "$SHELL_RC" "gitspace-completion.sh" \
    "gitspace completion (old absolute-path style)"

# Pre-rename cleanup — stale x-space/bin PATH lines
remove_pattern_from_rc "$SHELL_RC" "x-space/bin" "stale x-space/bin PATH lines"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — COMPLETION SYMLINK
# ─────────────────────────────────────────────────────────────────────────────
hr "Completion symlink (~/.local/share/xspace/)"

if [[ -L "$COMP_SYMLINK" ]]; then
    rm "$COMP_SYMLINK"
    ok "Removed: $COMP_SYMLINK"
else
    ok "No symlink found at $COMP_SYMLINK (already clean)"
fi

# Remove the share dir only if it's now empty
if [[ -d "$XSPACE_SHARE" ]] && [[ -z "$(ls -A "$XSPACE_SHARE" 2>/dev/null)" ]]; then
    rmdir "$XSPACE_SHARE"
    ok "Removed empty: $XSPACE_SHARE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — MARKER
# ─────────────────────────────────────────────────────────────────────────────
hr "Marker"

if [[ -f "$_X_MARKER/installed" ]]; then
    rm "$_X_MARKER/installed"
    ok "Removed .xspace/installed"
else
    ok "No installed marker found"
fi

echo ""
echo "  -- Uninstall complete ----------------------------------------"
echo ""
echo "  Open a new terminal or: source ~/$( basename "$SHELL_RC" )"
echo "  Re-install: installx"
echo ""
echo "  Press Enter to close..."
read -r _
echo ""