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
#   v0.8.0 — sconl-space expanded for full iSconl suite. Step 1 creates the
#             complete directory tree: scope/, space/, spark/, reflections/,
#             journal/, notes/ under sconl-space/data/. Step 9 initializes
#             all iSconl flat-file TSV headers. ISCONL_DATA_DIR created for
#             future SQLite mode. Stale PATH cleanup extended for all spaces.
#             xspace.conf stale entry patterns updated for sconl-space/bin.
#   v0.7.1 — Critical fix: PATH_LINE now writes \$PATH (escaped) so the guard
#             in .bashrc references $PATH at shell startup, not at install time.
#             Step 3 strips stale PATH entries for all space bin dirs.
#   v0.7.0 — sconl-space added. serverx/creatorx wired. sconl-space data init.
#   v0.6.0 — Step 4 rewritten: gitspace completion via stable symlink.
#   v0.5.0 — x-space → _configure rename. Pure orchestrator.
#   v0.4.0 — animate-space/bin and lib. sys-space and backup-space scaffolded.
#   v0.3.0 — CONF path fixed. animate-svg dirs added.
#   v0.2.0 — bash-space → x-space.
#   v0.1.0 — Initial installer.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────
# _X_DIR    = xspace/_configure/   (NEVER named XSPACE_DIR — see xspace.conf)
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

# sconl-space
ABS_SCONLSPACE="$XSPACE_ROOT/$SCONLSPACE_DIR"
ABS_SC_BIN="$ABS_SCONLSPACE/bin"
ABS_SC_LIB="$ABS_SCONLSPACE/lib"
ABS_SC_DATA="$ABS_SCONLSPACE/data"

# sconl-space/data subdirectories (flat-file mode structure)
ABS_SC_DATA_SCOPE="$ABS_SC_DATA/scope"
ABS_SC_DATA_SCOPE_REFLECTIONS="$ABS_SC_DATA/scope/reflections"
ABS_SC_DATA_SPACE="$ABS_SC_DATA/space"
ABS_SC_DATA_SPARK="$ABS_SC_DATA/spark"
ABS_SC_DATA_JOURNAL="$ABS_SC_DATA/journal"
ABS_SC_DATA_NOTES="$ABS_SC_DATA/notes"

# iSconl shared data directory (SQLite mode — outside repo)
ABS_ISCONL_DATA="${ISCONL_DATA_DIR:-$HOME/.local/share/isconl}"
ABS_ISCONL_EXPORTS="$ABS_ISCONL_DATA/exports"

# gitspace completion — stable share location (move-safe)
XSPACE_SHARE="$HOME/.local/share/xspace"
COMP_SYMLINK="$XSPACE_SHARE/gitspace-completion.sh"
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

# Initialize a TSV file with a header row if it doesn't exist yet.
# Idempotent — never overwrites existing data.
init_tsv() {
    local file="$1" header="$2"
    if [[ ! -f "$file" ]]; then
        printf '%b\n' "$header" > "$file"
        ok "Initialized: $(basename "$file")"
    else
        ok "Present: $(basename "$file")"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace installer v0.8.0"
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

# sconl-space: bin, lib, and full data tree
mkdir -p "$ABS_SC_BIN" "$ABS_SC_LIB"
mkdir -p "$ABS_SC_DATA"
mkdir -p "$ABS_SC_DATA_SCOPE"
mkdir -p "$ABS_SC_DATA_SCOPE_REFLECTIONS"
mkdir -p "$ABS_SC_DATA_SPACE"
mkdir -p "$ABS_SC_DATA_SPARK"
mkdir -p "$ABS_SC_DATA_JOURNAL"
mkdir -p "$ABS_SC_DATA_NOTES"

# iSconl shared data dir (SQLite mode — outside repo, never committed)
mkdir -p "$ABS_ISCONL_DATA"
mkdir -p "$ABS_ISCONL_EXPORTS"

mkdir -p "$XSPACE_SHARE"

ok "All directories ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — BACKUPS.CONF (first install only — never overwrite)
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
EOF
    ok "Created starter backups.conf"
else
    ok "backups.conf present (not overwritten)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PATH + SYMLINKS
# Strip stale entries first (prevents accumulation on reinstall/move),
# then loop XSPACE_ALL_BIN_DIRS and write a guard + symlinks for each.
# ─────────────────────────────────────────────────────────────────────────────
hr "PATH entries + symlinks"

# Strip stale entries for all known space bin dirs before re-adding.
for _stale_space in _configure/bin animate-space/bin git-space/bin sys-space/bin \
                    backup-space/bin sconl-space/bin server-space/bin creator-space/bin; do
    remove_pattern_from_rc "$SHELL_RC" "${_stale_space}:\\\$PATH" "stale ${_stale_space} entry"
done

for rel_bin in "${XSPACE_ALL_BIN_DIRS[@]}"; do
    abs_bin="$XSPACE_ROOT/$rel_bin"

    if [[ ! -d "$abs_bin" ]]; then
        warn "$rel_bin not found — skipping"
        continue
    fi

    # Use \$PATH (escaped) so the written guard references $PATH at shell
    # startup time, not the expanded value at install time.
    PATH_LINE="[[ \":\$PATH:\" != *\":${abs_bin}:\"* ]] && PATH=\"${abs_bin}:\$PATH\""
    add_line_to_rc "$SHELL_RC" "$PATH_LINE" "xspace: ${rel_bin} on PATH"

    chmod +x "$abs_bin"/* 2>/dev/null || true
    linked=0
    for f in "$abs_bin"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        ln -sf "$f" "$USER_BIN/$name"
        (( ++linked )) || true
    done
    ok "${rel_bin} — $linked script(s) symlinked"
done

SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_line_to_rc "$SHELL_RC" "$SAFE_ADD" "xspace: ~/bin on PATH"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — GITSPACE COMPLETION (move-safe via stable symlink)
# ─────────────────────────────────────────────────────────────────────────────
hr "gitspace completion (move-safe symlink)"

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
    "sconl-space:$ABS_SCONLSPACE" \
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
    warn "python3 not found — animatex-text and Equicycle engine will not work"
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
ok "equicycle.py: stdlib only — no extra deps"

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
# STEP 9 — VM TOOLS + SCONL-SPACE FULL DATA INIT
# ─────────────────────────────────────────────────────────────────────────────
hr "VM tools"

command -v virsh &>/dev/null \
    && ok "virsh available  (serverx / creatorx → VM management)" \
    || warn "virsh not found — serverx/creatorx will not work  (sudo dnf install libvirt)"

command -v virt-viewer &>/dev/null \
    && ok "virt-viewer available  (creatorx → Windows VM GUI)" \
    || warn "virt-viewer not found — creatorx needs it  (sudo dnf install virt-viewer)"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 10 — SCONL-SPACE DATA INITIALIZATION
# ─────────────────────────────────────────────────────────────────────────────
hr "sconl-space data (flat-file mode)"

# .gitignore for data/ — personal data stays local, never committed
SCONL_DATA_GI="$ABS_SC_DATA/.gitignore"
if [[ ! -f "$SCONL_DATA_GI" ]]; then
    cat > "$SCONL_DATA_GI" <<'GITIGNORE'
# sconl-space/data — personal data, not committed to the repo.
# Everything in here is yours: tasks, journal, goals, spaces, ideas.
*
!.gitignore
GITIGNORE
    ok "Created sconl-space/data/.gitignore"
else
    ok "sconl-space/data/.gitignore present"
fi

# ── Scope flat-file TSV headers ──
init_tsv "$ABS_SC_DATA_SCOPE/inbox.tsv" \
    "ID\tTITLE\tBODY\tSTATUS\tSOURCE\tCAPTURED_AT\tEQ_YEAR\tEQ_CYCLE\tEQ_DAY"

init_tsv "$ABS_SC_DATA_SCOPE/tasks.tsv" \
    "ID\tTITLE\tSTATUS\tPRIORITY\tPROJECT_ID\tCARRY_FWD\tDUE_DATE\tENERGY\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SCOPE/goals.tsv" \
    "ID\tTITLE\tKPI\tTARGET\tCURRENT\tLEVEL\tSTATUS\tWEIGHT\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SCOPE/projects.tsv" \
    "ID\tGOAL_ID\tTITLE\tSTATUS\tDOD\tCREATED_AT"

init_tsv "$ABS_SC_DATA_SCOPE/cycles.tsv" \
    "ID\tEQ_YEAR\tCYCLE_NUM\tTHEME\tSTART_DATE\tEND_DATE\tSTATUS\tOBJ1\tOBJ2\tOBJ3"

init_tsv "$ABS_SC_DATA_SCOPE/reflections.tsv" \
    "DATE\tMOOD\tENERGY\tHAS_CONTENT"

# ── Space flat-file TSV headers ──
init_tsv "$ABS_SC_DATA_SPACE/spaces.tsv" \
    "ID\tNAME\tTYPE\tSTATUS\tHEALTH\tDESCRIPTION\tEMOJI\tCREATED_AT\tLAST_REVIEWED"

init_tsv "$ABS_SC_DATA_SPACE/projects.tsv" \
    "ID\tSPACE_ID\tTITLE\tSTATUS\tCREATED_AT"

init_tsv "$ABS_SC_DATA_SPACE/contacts.tsv" \
    "ID\tSPACE_ID\tNAME\tROLE\tLAST_CONTACT\tCREATED_AT"

init_tsv "$ABS_SC_DATA_SPACE/kpi_defs.tsv" \
    "ID\tSPACE_ID\tNAME\tUNIT\tTARGET"

init_tsv "$ABS_SC_DATA_SPACE/kpi_log.tsv" \
    "ID\tKPI_ID\tSPACE_ID\tNAME\tVALUE\tUNIT\tMEASURED_AT"

init_tsv "$ABS_SC_DATA_SPACE/events.tsv" \
    "ID\tSPACE_ID\tTYPE\tTITLE\tEVENT_DATE"

# ── Spark flat-file TSV headers ──
init_tsv "$ABS_SC_DATA_SPARK/ideas.tsv" \
    "ID\tSTAGE\tTYPE\tBODY\tTITLE\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SPARK/learning.tsv" \
    "ID\tTITLE\tTYPE\tSTATUS\tPROGRESS\tAUTHOR\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SPARK/dia.tsv" \
    "ID\tNAME\tROLE\tTYPE\tDEPTH\tLAST_CONTACT\tTRAJECTORY\tCREATED_AT"

# ── Shared event bus (flat mode) ──
init_tsv "$ABS_SC_DATA/events.tsv" \
    "ID\tSOURCE\tTYPE\tPAYLOAD\tCREATED_AT\tCONSUMED_BY"

# ── Legacy tasks.tsv compatibility (kept for v1.0.0 data migration) ──
# Only create if it doesn't already exist — preserve any existing v1.0.0 data
if [[ ! -f "$ABS_SC_DATA/tasks.tsv" ]]; then
    printf 'ID\tSTATUS\tPRIORITY\tDUE\tCREATED\tTITLE\tTAGS\n' > "$ABS_SC_DATA/tasks.tsv"
    ok "Initialized legacy tasks.tsv (v1.0.0 compatibility)"
else
    ok "Legacy tasks.tsv present"
fi

# ── Equicycle engine check ──
EQUICYCLE_PY="$ABS_SCONLSPACE/lib/equicycle.py"
if [[ -f "$EQUICYCLE_PY" ]]; then
    ok "equicycle.py engine found"
    # Quick sanity test
    if python3 "$EQUICYCLE_PY" --format fields &>/dev/null; then
        ok "equicycle.py working"
    else
        warn "equicycle.py found but failed self-test — check python3 installation"
    fi
else
    warn "equicycle.py missing at $EQUICYCLE_PY — sconlx cycle display won't work"
fi

# ── sqlite3 check (needed for SQLite mode when Flutter apps arrive) ──
command -v sqlite3 &>/dev/null \
    && ok "sqlite3 available (SQLite mode ready when Flutter apps installed)" \
    || warn "sqlite3 not found — install it for SQLite mode: sudo dnf install sqlite (or apt install sqlite3)"

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
echo "    sconlx               iSconl dashboard (tasks, journal, goals, spaces, ideas)"
echo "    sconlx --help        full command reference"
echo "    sconlx scope         daily loop: inbox, tasks, goals, reflection"
echo "    sconlx space         portfolio: businesses, projects, hobbies"
echo "    sconlx spark         inner world: journal, ideas, learning"
echo "    sconlx journal       open today's journal"
echo "    sconlx task          quick task management (legacy alias)"
echo ""
echo "    animatex --help      animated text assets"
echo "    commitx --help       git commit helper"
echo "    backupx --help       backup orchestrator"
echo "    serverx --help       server VM manager"
echo "    creatorx --help      Windows VM manager"
echo "    updatex --help       system + repo updater"
echo "    refreshx             reload shell"
echo ""
echo "  sconlx data (flat-file mode):"
echo "    $ABS_SC_DATA"
echo ""
echo "  SQLite mode activates automatically when Flutter iSconl apps are"
echo "  installed and databases appear at:"
echo "    $ABS_ISCONL_DATA"
echo ""
echo "  Moved the repo? Re-run this script — symlinks update automatically."
echo ""