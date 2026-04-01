#!/usr/bin/env bash
# x-space/install.sh
#
# Hands-free installer for the XSpace monorepo.
# Safe to re-run — every operation is idempotent.
#
# Usage:
#   cd xspace/x-space && ./install.sh

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.5.0 — All tool code removed from x-space/bin (pure orchestrator now).
#             animate-space/bin and lib created. sys-space and backup-space
#             dirs scaffolded. backup-space/config/backups.conf.example written
#             on first install if no conf present. Loops XSPACE_ALL_BIN_DIRS
#             for PATH + symlinks covering all five spaces.
#   v0.4.0 — Fixed nested x-space/x-space/ bug (_X_DIR). XSPACE_ALL_BIN_DIRS
#             added. git-space auto-wired.
#   v0.3.0 — Fixed CONF path to XSPACE_ROOT. Added animate-svg dirs.
#   v0.2.0 — Renamed bash-space → x-space; monorepo-aware.
#   v0.1.0 — Initial installer.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────
# _X_DIR = xspace/x-space/  (never named XSPACE_DIR — see xspace.conf warning)
# XSPACE_ROOT = xspace/

_X_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="$(cd "$_X_DIR/.." && pwd)"

CONF="$XSPACE_ROOT/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo ""
    echo "  ✗ xspace.conf not found at $CONF"
    echo "  It must live at the repo root (xspace/), not inside x-space/."
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

PILLOW_PKG="Pillow"

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

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace installer v0.5.0"
echo "  root : $XSPACE_ROOT"
echo "  bin  : $USER_BIN"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────
hr "Directories"

# x-space internals
mkdir -p "$_X_BIN" "$_X_LIB" "$USER_BIN" "$_X_MARKER"

# animate-space (bin + lib at space root; engines nested under animate-text/ etc.)
mkdir -p "$ABS_AX_BIN" "$ABS_AX_LIB"
mkdir -p "$ABS_TEXT_FONTS" "$ABS_TEXT_EXPORTS"
mkdir -p "$ABS_SVG_EXPORTS" "$ABS_SVG_PYTHON"
mkdir -p "$XSPACE_ROOT/$ANIMATEX_SVG_FONTS_DIR"

# git-space (structure already exists — just ensure log dir)
mkdir -p "$GITSPACE_LOG_DIR"

# sys-space
mkdir -p "$ABS_SYS_BIN" "$ABS_SYS_LIB"

# backup-space
mkdir -p "$ABS_BK_BIN" "$ABS_BK_LIB" "$ABS_BK_CONFIG" "$ABS_BK_LOGS"

ok "All directories ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — BACKUPS.CONF EXAMPLE (first install only)
# ─────────────────────────────────────────────────────────────────────────────
hr "backup-space config"

if [[ ! -f "$ABS_BK_CONF" ]]; then
    cat > "$ABS_BK_CONF" <<'EOF'
# backup-space/config/backups.conf
#
# One backup job per line. Format: method|source|dest|options|mode
#
# method : rclone | rsync | tar
# source : absolute local path
# dest   : destination path (local, remote, or archive path)
# options: tool-specific flags (passed verbatim)
# mode   : copy (additive) | sync (mirror)
#
# Lines starting with # are ignored.
#
# ── Examples ─────────────────────────────────────────────────────────────────
# rclone|/home/user/Documents|gdrive:Backups/Documents|--progress --transfers=4|sync
# rclone|/home/user/Projects|dropbox:Dev/Projects|--progress|copy
# rsync|/home/user/Documents|backup@server:/backups/docs|-avz --delete|sync
# tar|/home/user/important|/mnt/usb/important.tar.gz|--exclude='.git'|copy
# ─────────────────────────────────────────────────────────────────────────────
#
# Add your jobs below:
EOF
    ok "Created backup-space/config/backups.conf (edit to add your backup jobs)"
else
    ok "backups.conf already exists"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — ALL SPACE BINS: PATH ENTRIES + SYMLINKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Space bins → PATH + ~/bin"

if   [[ -n "${ZSH_VERSION-}"  ]]; then SHELL_RC="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION-}" ]]; then SHELL_RC="$HOME/.bashrc"
else                                    SHELL_RC="$HOME/.profile"
fi

for rel_bin in "${XSPACE_ALL_BIN_DIRS[@]}"; do
    abs_bin="$XSPACE_ROOT/$rel_bin"

    if [[ ! -d "$abs_bin" ]]; then
        warn "$rel_bin not found — skipping"
        continue
    fi

    # PATH entry — the auto-discovery mechanism for new scripts in this dir
    PATH_LINE="[[ \":$PATH:\" != *\":${abs_bin}:\"* ]] && PATH=\"${abs_bin}:\$PATH\""
    add_line_to_rc "$SHELL_RC" "$PATH_LINE" "xspace: ${rel_bin} on PATH"

    # Symlink all current executables to ~/bin
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

# ~/bin itself — fallback for shells that cache PATH lookups
SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_line_to_rc "$SHELL_RC" "$SAFE_ADD" "xspace: ~/bin on PATH"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — GITSPACE COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
hr "gitspace completion"

if [[ -f "$ABS_GITSPACE_COMPLETION" ]]; then
    COMP_LINE="[[ -f \"$ABS_GITSPACE_COMPLETION\" ]] && source \"$ABS_GITSPACE_COMPLETION\""
    add_line_to_rc "$SHELL_RC" "$COMP_LINE" "xspace: gitspace tab completion"
    ok "gitspace completion registered"
else
    warn "gitspace completion not found — re-run install after git-space is set up"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — SIBLING SPACE VALIDATION
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
    warn "      Fedora: sudo dnf install python3"
    warn "      Ubuntu: sudo apt install python3"
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
ok "animatex-svg: stdlib only"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — ENGINE CHECKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Engines"

[[ -f "$ABS_TEXT_SCRIPT" ]] && ok "animate-text engine" || warn "animate-text engine missing at $ABS_TEXT_SCRIPT"
[[ -f "$ABS_SVG_SCRIPT"  ]] && ok "animate-svg engine"  || warn "animate-svg engine missing at $ABS_SVG_SCRIPT"

FC="$(find "$ABS_TEXT_FONTS" -maxdepth 1 \( -iname "*.ttf" -o -iname "*.otf" \) 2>/dev/null | wc -l)"
(( FC > 0 )) && ok "animate-text: $FC font(s)" || warn "animate-text: no fonts in $ABS_TEXT_FONTS"

# rclone check for backup-space
hr "backup-space"
if command -v rclone &>/dev/null; then
    ok "rclone $(rclone version 2>/dev/null | head -1 | awk '{print $2}')"
else
    warn "rclone not found — rclone backup jobs will not run"
    warn "      Install: https://rclone.org/install/"
fi
[[ -f "$ABS_BK_CONF" ]] && ok "backups.conf present" || warn "backups.conf missing at $ABS_BK_CONF"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — EXPORTS .gitignore
# ─────────────────────────────────────────────────────────────────────────────
hr "exports .gitignore"

for exports_dir in "$ABS_TEXT_EXPORTS" "$ABS_SVG_EXPORTS"; do
    gi="$exports_dir/.gitignore"
    if [[ ! -f "$gi" ]]; then
        printf '*\n!.gitignore\n' > "$gi"
        ok "Created: $gi"
    else
        ok "Present: $gi"
    fi
done

# Also gitignore the backup logs (auto-generated, not for version control)
BK_LOGS_GI="$ABS_BK_LOGS/.gitignore"
if [[ ! -f "$BK_LOGS_GI" ]]; then
    printf '*\n!.gitignore\n' > "$BK_LOGS_GI"
    ok "Created: backup-space/logs/.gitignore"
fi

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

touch "$_X_MARKER/installed"

echo ""
echo "  ── Complete ──────────────────────────────────────────────────"
echo ""
echo "  Run 'refreshx' or open a new terminal to activate."
echo ""
echo "  Try:"
echo "    animatex --help"
echo "    commitx --help"
echo "    backupx --help"
echo "    updatex --help"
echo ""
echo "  Adding new commands:"
echo "    drop a script into any space's bin/ dir"
echo "    git-space/bin, sys-space/bin, backup-space/bin → available on next terminal"
echo "    animate-space/bin → same"
echo "    x-space/bin → run install.sh once to create the symlink"
echo ""