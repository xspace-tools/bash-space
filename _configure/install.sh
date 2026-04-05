#!/usr/bin/env bash
# _configure/install.sh
#
# Hands-free installer for the XSpace monorepo.
# Safe to re-run — every operation is idempotent.
#
# Usage:
#   cd xspace/_configure && ./install.sh

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.6.0 — Step 4 rewritten: gitspace completion now registered via a stable
#             symlink at ~/.local/share/xspace/gitspace-completion.sh. The RC
#             line references $HOME (not an absolute path), so moving the repo
#             never breaks the shell. Re-running install.sh after a move updates
#             the symlink in one step — no manual .bashrc editing needed. Old
#             absolute-path RC lines from v0.5.0 are cleaned up automatically.
#             Step 2 skips conf rewrite when backups.conf already exists (was
#             already idempotent, now also avoids touching a customised conf).
#   v0.5.0 — Folder renamed x-space/ → _configure/. Path comments updated.
#             All tool code has moved to their respective spaces — this script
#             is now a pure orchestrator.
#   v0.4.0 — (_configure was x-space) All tool code removed from _configure/bin.
#             animate-space/bin and lib created. sys-space and backup-space
#             scaffolded. backup-space/config/backups.conf.example written.
#   v0.3.0 — CONF path fixed to XSPACE_ROOT. Added animate-svg dirs.
#   v0.2.0 — Renamed bash-space → x-space; monorepo-aware.
#   v0.1.0 — Initial installer.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────
# _X_DIR    = xspace/_configure/   (NEVER named XSPACE_DIR — see xspace.conf warning)
# XSPACE_ROOT = xspace/            (where xspace.conf lives)

_X_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="$(cd "$_X_DIR/.." && pwd)"

CONF="$XSPACE_ROOT/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo ""
    echo "  ✗ xspace.conf not found at $CONF"
    echo "  It must live at the repo root (xspace/), not inside _configure/."
    echo ""
    exit 1
fi
source "$CONF"

# ─────────────────────────────────────────────────────────────────────────────
# RESOLVED PATHS
# ─────────────────────────────────────────────────────────────────────────────

_X_BIN="$_X_DIR/bin"
_X_LIB="$_X_DIR/lib"
_X_MARKER="$_X_DIR/.xspace"
USER_BIN="${USER_BIN:-${USER_BIN_DEFAULT}}"

# animate-space
ABS_ANIMATE="$XSPACE_ROOT/$ANIMATESPACE_DIR"
ABS_AX_BIN="$ABS_ANIMATE/bin"
ABS_AX_LIB="$ABS_ANIMATE/lib"
ABS_TEXT_FONTS="$XSPACE_ROOT/$ANIMATEX_TEXT_FONTS_DIR"
ABS_TEXT_EXPORTS="$XSPACE_ROOT/$ANIMATEX_TEXT_EXPORTS_DIR"
ABS_TEXT_SCRIPT="$XSPACE_ROOT/$ANIMATEX_TEXT_SCRIPT"
ABS_SVG_EXPORTS="$XSPACE_ROOT/$ANIMATEX_SVG_EXPORTS_DIR"
ABS_SVG_SCRIPT="$XSPACE_ROOT/$ANIMATEX_SVG_SCRIPT"
ABS_SVG_PYTHON="$XSPACE_ROOT/$ANIMATEX_SVG_DIR/python"

# git-space
ABS_GITSPACE="$XSPACE_ROOT/$GITSPACE_DIR"
ABS_GITSPACE_COMPLETION="$XSPACE_ROOT/$GITSPACE_COMPLETION"

# sys-space
ABS_SYSSPACE="$XSPACE_ROOT/$SYSSPACE_DIR"
ABS_SYS_BIN="$ABS_SYSSPACE/bin"
ABS_SYS_LIB="$ABS_SYSSPACE/lib"

# backup-space
ABS_BACKUPSPACE="$XSPACE_ROOT/$BACKUPSPACE_DIR"
ABS_BK_BIN="$ABS_BACKUPSPACE/bin"
ABS_BK_LIB="$ABS_BACKUPSPACE/lib"
ABS_BK_CONFIG="$XSPACE_ROOT/$BACKUPSPACE_CONFIG_DIR"
ABS_BK_LOGS="$XSPACE_ROOT/$BACKUPSPACE_LOG_DIR"
ABS_BK_CONF="$XSPACE_ROOT/$BACKUPSPACE_CONF"

# gitspace completion — stable share location (move-safe)
# The RC line always reads: $HOME/.local/share/xspace/gitspace-completion.sh
# This symlink is updated by every install run, so moving the repo = re-run install.
XSPACE_SHARE="$HOME/.local/share/xspace"
COMP_SYMLINK="$XSPACE_SHARE/gitspace-completion.sh"
# The RC line — uses $HOME variable, never a hardcoded path
COMP_LINE='_xsp="$HOME/.local/share/xspace/gitspace-completion.sh"; [[ -f "$_xsp" ]] && source "$_xsp"; unset _xsp'

PILLOW_PKG="Pillow"

# ─────────────────────────────────────────────────────────────────────────────
# SHELL RC DETECTION
# ─────────────────────────────────────────────────────────────────────────────

if   [[ -n "${ZSH_VERSION-}"  ]]; then SHELL_RC="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION-}" ]]; then SHELL_RC="$HOME/.bashrc"
else                                    SHELL_RC="$HOME/.profile"
fi

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

log()  { echo "    $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠  $*"; }
hr()   { echo ""; echo "  ── $* ──────────────────────────────────────────────────"; }

add_line_to_rc() {
    local rc="$1" line="$2" comment="$3"
    mkdir -p "$(dirname "$rc")" 2>/dev/null || true
    if ! grep -Fxq "$line" "$rc" 2>/dev/null; then
        printf "\n# %s\n%s\n" "$comment" "$line" >> "$rc"
        ok "RC: added — $comment"
    else
        ok "RC: present — $comment"
    fi
}

remove_pattern_from_rc() {
    local rc="$1" pattern="$2" label="$3"
    [[ ! -f "$rc" ]] && return 0
    if grep -q "$pattern" "$rc" 2>/dev/null; then
        local tmp; tmp="$(mktemp)"
        grep -v "$pattern" "$rc" > "$tmp"
        mv "$tmp" "$rc"
        ok "RC: cleaned stale — $label"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace installer v0.6.0"
echo "  root : $XSPACE_ROOT"
echo "  bin  : $USER_BIN"
echo "  rc   : $SHELL_RC"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────
hr "Directories"

mkdir -p "$_X_BIN" "$_X_LIB" "$USER_BIN" "$_X_MARKER"
mkdir -p "$ABS_AX_BIN" "$ABS_AX_LIB"
mkdir -p "$ABS_TEXT_FONTS" "$ABS_TEXT_EXPORTS"
mkdir -p "$ABS_SVG_EXPORTS" "$ABS_SVG_PYTHON"
mkdir -p "$XSPACE_ROOT/$ANIMATEX_SVG_FONTS_DIR"
mkdir -p "$GITSPACE_LOG_DIR"
mkdir -p "$ABS_SYS_BIN" "$ABS_SYS_LIB"
mkdir -p "$ABS_BK_BIN" "$ABS_BK_LIB" "$ABS_BK_CONFIG" "$ABS_BK_LOGS"
mkdir -p "$XSPACE_SHARE"

ok "All directories ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — BACKUPS.CONF (first install only — never overwrite a customised conf)
# ─────────────────────────────────────────────────────────────────────────────
hr "backup-space config"

if [[ ! -f "$ABS_BK_CONF" ]]; then
    cat > "$ABS_BK_CONF" <<'EOF'
# backup-space/config/backups.conf
# Format: name|method|source|dest|options
# {LOCAL_BASE}    → ~/_ (Linux/macOS) or ~/Desktop/_ (Windows)
# {RCLONE_REMOTE} → the RCLONE_REMOTE value set in backupx
#
# Run: backupx --help   for full documentation.
# Run: backupx --init   to pull remote folders to local (first time).
EOF
    ok "Created backup-space/config/backups.conf (starter)"
else
    ok "backups.conf exists — not overwritten"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — ALL SPACE BINS: PATH ENTRIES + SYMLINKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Space bins → PATH + ~/bin"

for rel_bin in "${XSPACE_ALL_BIN_DIRS[@]}"; do
    abs_bin="$XSPACE_ROOT/$rel_bin"

    if [[ ! -d "$abs_bin" ]]; then
        warn "$rel_bin not found — skipping"
        continue
    fi

    PATH_LINE="[[ \":$PATH:\" != *\":${abs_bin}:\"* ]] && PATH=\"${abs_bin}:\$PATH\""
    add_line_to_rc "$SHELL_RC" "$PATH_LINE" "xspace: ${rel_bin} on PATH"

    chmod +x "$abs_bin"/* 2>/dev/null || true
    linked=0
    for f in "$abs_bin"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        ln -sf "$f" "$USER_BIN/$name"
        (( ++linked ))
    done
    ok "${rel_bin} — $linked script(s) symlinked"
done

SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_line_to_rc "$SHELL_RC" "$SAFE_ADD" "xspace: ~/bin on PATH"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — GITSPACE COMPLETION (move-safe via stable symlink)
# ─────────────────────────────────────────────────────────────────────────────
# Design rationale:
#   Old approach: wrote the absolute repo path into .bashrc directly.
#   Problem:      moving the repo = stale path = error on every terminal open.
#   New approach: symlink  actual_path → ~/.local/share/xspace/completion.sh
#                 RC line: sources $HOME/.local/share/xspace/completion.sh
#   Benefit:      RC line uses $HOME (stable). After any move, re-run install.sh
#                 and the symlink is updated — no .bashrc editing ever needed.
# ─────────────────────────────────────────────────────────────────────────────
hr "gitspace completion (move-safe symlink)"

# Clean up any old absolute-path style RC entries from v0.5.0 and earlier.
# Safe to run every time — grep returns non-zero if nothing found.
remove_pattern_from_rc "$SHELL_RC" \
    "gitspace-completion.sh" \
    "old absolute-path completion line"

if [[ -f "$ABS_GITSPACE_COMPLETION" ]]; then
    ln -sf "$ABS_GITSPACE_COMPLETION" "$COMP_SYMLINK"
    ok "Symlink: $COMP_SYMLINK → $ABS_GITSPACE_COMPLETION"

    add_line_to_rc "$SHELL_RC" "$COMP_LINE" "xspace: gitspace tab completion"
    ok "gitspace completion registered (move-safe)"
else
    warn "gitspace-completion.sh not found at $ABS_GITSPACE_COMPLETION"
    warn "Re-run install.sh after git-space is set up"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — SPACE VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
hr "Space directories"

for entry in \
    "animate-space:$ABS_ANIMATE" \
    "git-space:$ABS_GITSPACE" \
    "sys-space:$ABS_SYSSPACE" \
    "backup-space:$ABS_BACKUPSPACE" \
    "code-space:$XSPACE_ROOT/$CODESPACE_DIR"
do
    label="${entry%%:*}"; path="${entry##*:}"
    [[ -d "$path" ]] && ok "$label" || warn "$label missing at $path"
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — PYTHON + PILLOW
# ─────────────────────────────────────────────────────────────────────────────
hr "Python + Pillow (animatex-text)"

if ! command -v python3 &>/dev/null; then
    warn "python3 not found — animatex-text will not work"
else
    ok "$(python3 --version 2>&1)"
    if python3 -c "import PIL" &>/dev/null; then
        ok "Pillow $(python3 -c 'import PIL; print(PIL.__version__)')"
    else
        log "Installing Pillow..."
        if pip3 install "$PILLOW_PKG" --break-system-packages &>/dev/null 2>&1; then
            ok "Pillow installed (system)"
        elif pip3 install "$PILLOW_PKG" --user &>/dev/null 2>&1; then
            ok "Pillow installed (user)"
        else
            warn "Pillow install failed — run: pip install pillow --break-system-packages"
        fi
    fi
fi
ok "animatex-svg: stdlib only — no extra deps"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — ENGINE CHECKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Engines"

[[ -f "$ABS_TEXT_SCRIPT" ]] && ok "animate-text engine" || warn "animate-text engine missing"
[[ -f "$ABS_SVG_SCRIPT"  ]] && ok "animate-svg engine"  || warn "animate-svg engine missing"

FC="$(find "$ABS_TEXT_FONTS" -maxdepth 1 \( -iname "*.ttf" -o -iname "*.otf" \) 2>/dev/null | wc -l)"
(( FC > 0 )) && ok "animate-text: $FC font(s)" || warn "animate-text: no fonts in $ABS_TEXT_FONTS"

hr "backup-space"
command -v rclone &>/dev/null \
    && ok "rclone $(rclone version 2>/dev/null | head -1 | awk '{print $2}')" \
    || warn "rclone not found — install from https://rclone.org/install/"
[[ -f "$ABS_BK_CONF" ]] && ok "backups.conf present" || warn "backups.conf missing"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — .gitignore FOR GENERATED OUTPUT DIRS
# ─────────────────────────────────────────────────────────────────────────────
hr ".gitignore for output dirs"

for d in "$ABS_TEXT_EXPORTS" "$ABS_SVG_EXPORTS" "$ABS_BK_LOGS"; do
    gi="$d/.gitignore"
    if [[ ! -f "$gi" ]]; then
        printf '*\n!.gitignore\n' > "$gi"
        ok "Created: $gi"
    else
        ok "Present: $gi"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

touch "$_X_MARKER/installed"

echo ""
echo "  ── Complete ──────────────────────────────────────────────────"
echo ""
echo "  Run 'refreshx' or open a new terminal to activate."
echo ""
echo "  Commands available:"
echo "    animatex --help      animated text assets"
echo "    commitx --help       git commit helper"
echo "    backupx --help       backup orchestrator"
echo "    backupx --init       first-time: pull OneDrive folders to local"
echo "    updatex --help       system + repo updater"
echo "    refreshx             reload shell"
echo ""
echo "  Adding commands: drop a script into any space's bin/ dir."
echo "  Scripts in git-space/bin, sys-space/bin, animate-space/bin,"
echo "  backup-space/bin are available on next terminal open."
echo ""
echo "  Moved the repo? Just re-run this script — the completion symlink"
echo "  is updated automatically. No .bashrc editing needed."
echo ""