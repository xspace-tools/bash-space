#!/usr/bin/env bash
# _configure/lib/install.sh
#
# Hands-free installer for the XSpace monorepo.
# Safe to re-run — every operation is idempotent.
#
# Usage:
#   cd xspace/_configure/lib && ./install.sh
#   installx                            # after first install
#   installx --no-pause                 # suppress the "Press Enter" prompt
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Moved to _configure/lib/ (bootstrap updated: _LIB_DIR / _X_DIR
#             / XSPACE_ROOT now properly resolved from the new location).
#             Windows support: OS detection (_detect_os), portable _readlink_f,
#             OS-aware package-manager hints for all install suggestions,
#             Windows-safe python/pip detection, virsh/virt-viewer skipped on
#             Windows with a note. WSL2 detected and treated as Linux.
#             Change tracking: every idempotent helper now records new / updated
#             / existing outcomes into arrays (_CHG_NEW / _CHG_UPDATED /
#             _CHG_WARNED / _CHG_EXISTING). Summary section printed before the
#             final "Complete" block shows exactly what changed vs what was
#             already present. --no-pause flag added; without it the script
#             waits for Enter before exiting (supports "Run as Program" in
#             GNOME Files and other GUI launchers).
#   v0.9.0 — (internal: header updated; _configure/lib/ migration prep)
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
#   v0.5.0 — x-space -> _configure rename. Pure orchestrator.
#   v0.4.0 — animate-space/bin and lib. sys-space and backup-space scaffolded.
#   v0.3.0 — CONF path fixed. animate-svg dirs added.
#   v0.2.0 — bash-space -> x-space.
#   v0.1.0 — Initial installer.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# FLAGS  (parsed before anything else so helpers can see them)
# ─────────────────────────────────────────────────────────────────────────────

_NO_PAUSE=0
for _arg in "$@"; do
    [[ "$_arg" == "--no-pause" ]] && _NO_PAUSE=1
done

# ─────────────────────────────────────────────────────────────────────────────
# PORTABLE READLINK  (macOS BSD readlink has no -f; Git Bash works fine)
# ─────────────────────────────────────────────────────────────────────────────

_readlink_f() {
    local target="$1"
    # GNU readlink -f
    if readlink -f "$target" &>/dev/null 2>&1; then
        readlink -f "$target"; return
    fi
    # Homebrew greadlink on macOS
    if command -v greadlink &>/dev/null; then
        greadlink -f "$target"; return
    fi
    # Pure bash fallback (resolves one symlink level — good enough for bootstrap)
    local dir; dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)"
    echo "${dir}/$(basename "$target")"
}

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────
# _LIB_DIR   = xspace/_configure/lib/    (where this script lives)
# _X_DIR     = xspace/_configure/        (orchestrator root, has bin/ lib/ .xspace/)
# XSPACE_ROOT = xspace/                  (repo root, where xspace.conf lives)
# NOTE: _X_DIR must NEVER be named XSPACE_DIR — that name is reserved in xspace.conf

_LIB_DIR="$(cd "$(dirname "$(_readlink_f "${BASH_SOURCE[0]}")")" && pwd)"
_X_DIR="$(cd "$_LIB_DIR/.." && pwd)"
XSPACE_ROOT="$(cd "$_X_DIR/.." && pwd)"

CONF="$XSPACE_ROOT/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo ""
    echo "  x  xspace.conf not found at $CONF"
    echo "  It must live at the repo root (xspace/), not inside _configure/."
    echo ""
    exit 1
fi
source "$CONF"

# ─────────────────────────────────────────────────────────────────────────────
# OS DETECTION
# ─────────────────────────────────────────────────────────────────────────────

_detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Linux*)               echo "linux"   ;;
        Darwin*)              echo "mac"     ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                    echo "unknown" ;;
    esac
}
OS="$(_detect_os)"

# Detect WSL2 (uname -s returns Linux, but version contains 'microsoft')
IS_WSL=false
if [[ "$OS" == "linux" && -f /proc/version ]]; then
    grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true || true
fi

# Package manager hint (used in install suggestions)
case "$OS" in
    linux)
        if   command -v dnf    &>/dev/null; then PKG_MGR="sudo dnf install"
        elif command -v apt    &>/dev/null; then PKG_MGR="sudo apt install"
        elif command -v pacman &>/dev/null; then PKG_MGR="sudo pacman -S"
        else                                     PKG_MGR="<your package manager>"
        fi ;;
    mac)
        if command -v brew &>/dev/null; then PKG_MGR="brew install"
        else                                 PKG_MGR="brew install  # https://brew.sh"
        fi ;;
    windows)
        if   command -v winget &>/dev/null; then PKG_MGR="winget install"
        elif command -v choco  &>/dev/null; then PKG_MGR="choco install"
        else                                     PKG_MGR="winget install"
        fi ;;
    *) PKG_MGR="<your package manager>" ;;
esac

# Portable python detection (Windows may only have 'python' or 'py', not 'python3')
PYTHON3=""
for _p in python3 python py; do
    if command -v "$_p" &>/dev/null \
       && "$_p" -c "import sys; assert sys.version_info >= (3,8)" &>/dev/null 2>&1; then
        PYTHON3="$_p"; break
    fi
done

# Portable pip detection
PIP3=""
for _p in pip3 pip "python3 -m pip" "python -m pip"; do
    # shellcheck disable=SC2086
    if eval "command -v $_p" &>/dev/null 2>&1; then PIP3="$_p"; break; fi
done

# ─────────────────────────────────────────────────────────────────────────────
# RESOLVED PATHS
# ─────────────────────────────────────────────────────────────────────────────

_X_BIN="$_X_DIR/bin"
_X_LIB="$_LIB_DIR"
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
# CHANGE TRACKING
# ─────────────────────────────────────────────────────────────────────────────
# Every meaningful outcome is recorded into one of these arrays.
# The summary section at the end reads them to show what changed.

_CHG_NEW=()       # created for the first time this run
_CHG_UPDATED=()   # existed but was modified / refreshed
_CHG_WARNED=()    # warning: something missing or failed
_CHG_EXISTING=0   # already present and unchanged (count only — not printed during run)

_chg_new()      { _CHG_NEW+=("$*"); }
_chg_updated()  { _CHG_UPDATED+=("$*"); }
_chg_existing() { (( ++_CHG_EXISTING )) || true; }
_chg_warned()   { _CHG_WARNED+=("$*"); }

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

log()  { echo "    $*"; }
ok()   { echo "  + $*"; }
warn() { _chg_warned "$*"; echo "  ! $*"; }
hr()   { echo ""; echo "  -- $* ---------------------------------------------------"; }

# Wrapper: mkdir -p with change tracking. Call with a label and one or more dirs.
# Usage: _mkdirs "label" dir1 [dir2 ...]
_mkdirs() {
    local label="$1"; shift
    local any_new=false
    local d
    for d in "$@"; do
        if [[ ! -d "$d" ]]; then
            mkdir -p "$d"
            any_new=true
        fi
    done
    if [[ "$any_new" == true ]]; then
        _chg_new "$label"
        ok "Created: $label"
    else
        _chg_existing
    fi
}

add_line_to_rc() {
    local rc="$1" line="$2" comment="$3"
    mkdir -p "$(dirname "$rc")" 2>/dev/null || true
    if ! grep -Fxq "$line" "$rc" 2>/dev/null; then
        printf "\n# %s\n%s\n" "$comment" "$line" >> "$rc"
        _chg_new "RC: $comment"
        ok "RC: added — $comment"
    else
        _chg_existing
    fi
}

remove_pattern_from_rc() {
    local rc="$1" pattern="$2" label="$3"
    [[ ! -f "$rc" ]] && return 0
    if grep -q "$pattern" "$rc" 2>/dev/null; then
        local tmp; tmp="$(mktemp)"
        grep -v "$pattern" "$rc" > "$tmp"
        mv "$tmp" "$rc"
        _chg_updated "RC cleaned: $label"
        ok "RC: cleaned stale — $label"
    fi
}

# Initialize a TSV file with a header row if it doesn't exist yet.
# Idempotent — never overwrites existing data.
init_tsv() {
    local file="$1" header="$2"
    if [[ ! -f "$file" ]]; then
        printf '%b\n' "$header" > "$file"
        _chg_new "$(basename "$file")"
        ok "Initialized: $(basename "$file")"
    else
        _chg_existing
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace installer v1.0.0"
echo "  root : $XSPACE_ROOT"
echo "  bin  : $USER_BIN"
echo "  rc   : $SHELL_RC"
echo "  os   : $OS$(${IS_WSL} && echo ' (WSL2)' || true)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────
hr "Directories"

_mkdirs "_configure/bin + lib"      "$_X_BIN" "$_X_LIB" "$USER_BIN"
_mkdirs "_configure/.xspace marker" "$_X_MARKER"
_mkdirs "animate-space/bin + lib"   "$ABS_AX_BIN" "$ABS_AX_LIB"
_mkdirs "animate-space font/export dirs" \
        "$ABS_TEXT_FONTS" "$ABS_TEXT_EXPORTS" \
        "$ABS_SVG_EXPORTS" "$ABS_SVG_PYTHON" \
        "$XSPACE_ROOT/$ANIMATEX_SVG_FONTS_DIR"
_mkdirs "git-space log dir"         "$GITSPACE_LOG_DIR"
_mkdirs "sys-space/bin + lib"       "$ABS_SYS_BIN" "$ABS_SYS_LIB"
_mkdirs "backup-space dirs"         "$ABS_BK_BIN" "$ABS_BK_LIB" "$ABS_BK_CONFIG" "$ABS_BK_LOGS"
_mkdirs "sconl-space/bin + lib"     "$ABS_SC_BIN" "$ABS_SC_LIB"
_mkdirs "sconl-space/data root"     "$ABS_SC_DATA"
_mkdirs "sconl-space/data/scope"    "$ABS_SC_DATA_SCOPE" "$ABS_SC_DATA_SCOPE_REFLECTIONS"
_mkdirs "sconl-space/data/space"    "$ABS_SC_DATA_SPACE"
_mkdirs "sconl-space/data/spark"    "$ABS_SC_DATA_SPARK"
_mkdirs "sconl-space/data/journal"  "$ABS_SC_DATA_JOURNAL"
_mkdirs "sconl-space/data/notes"    "$ABS_SC_DATA_NOTES"
_mkdirs "iSconl shared data dir"    "$ABS_ISCONL_DATA" "$ABS_ISCONL_EXPORTS"
_mkdirs "xspace share dir"          "$XSPACE_SHARE"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — BACKUPS.CONF (first install only — never overwrite)
# ─────────────────────────────────────────────────────────────────────────────
hr "backup-space config"

if [[ ! -f "$ABS_BK_CONF" ]]; then
    cat > "$ABS_BK_CONF" <<'EOF'
# backup-space/config/backups.conf
# Format: name|method|source|dest|options
# {LOCAL_BASE}    -> ~/_ (Linux/macOS) or ~/Desktop/_ (Windows)
# {RCLONE_REMOTE} -> the RCLONE_REMOTE value set in backupx
#
# Run: backupx --help   for full documentation.
EOF
    _chg_new "backup-space/config/backups.conf"
    ok "Created starter backups.conf"
else
    _chg_existing
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
    updated_links=0
    for f in "$abs_bin"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        target="$USER_BIN/$name"
        if [[ -L "$target" && "$(readlink "$target")" == "$f" ]]; then
            (( ++linked )) || true       # already correct
        elif [[ -L "$target" ]]; then
            ln -sf "$f" "$target"        # stale symlink — update
            (( ++updated_links )) || true
        else
            ln -sf "$f" "$target"        # new symlink
            (( ++linked )) || true
        fi
    done

    if (( updated_links > 0 )); then
        _chg_updated "${rel_bin} — $updated_links symlink(s) updated"
        ok "${rel_bin} — $updated_links symlink(s) updated, $linked already correct"
    else
        _chg_existing
        ok "${rel_bin} — $linked script(s) symlinked"
    fi
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
    if [[ ! -L "$COMP_SYMLINK" || "$(readlink "$COMP_SYMLINK")" != "$ABS_GITSPACE_COMPLETION" ]]; then
        ln -sf "$ABS_GITSPACE_COMPLETION" "$COMP_SYMLINK"
        _chg_updated "gitspace completion symlink -> $ABS_GITSPACE_COMPLETION"
        ok "Symlink updated: $COMP_SYMLINK"
    else
        _chg_existing
        ok "Symlink: $COMP_SYMLINK (up to date)"
    fi
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
    if [[ -d "$path" ]]; then
        _chg_existing
        ok "$label"
    else
        warn "$label missing at $path"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — PYTHON + PILLOW
# ─────────────────────────────────────────────────────────────────────────────
hr "Python + Pillow (animatex-text)"

if [[ -z "$PYTHON3" ]]; then
    warn "python3 not found — animatex-text and equicycle engine will not work"
    case "$OS" in
        linux)   warn "Install: $PKG_MGR python3" ;;
        mac)     warn "Install: $PKG_MGR python3" ;;
        windows) warn "Install: winget install Python.Python.3  or  https://www.python.org/" ;;
    esac
else
    _chg_existing
    ok "$("$PYTHON3" --version 2>&1)"
    if "$PYTHON3" -c "import PIL" &>/dev/null 2>&1; then
        _chg_existing
        ok "Pillow $("$PYTHON3" -c 'import PIL; print(PIL.__version__)')"
    else
        log "Installing Pillow..."
        _pillow_installed=false

        if [[ -n "$PIP3" ]]; then
            if eval "$PIP3 install $PILLOW_PKG --break-system-packages" &>/dev/null 2>&1; then
                _pillow_installed=true
            elif eval "$PIP3 install $PILLOW_PKG --user" &>/dev/null 2>&1; then
                _pillow_installed=true
            fi
        fi

        if [[ "$_pillow_installed" == true ]]; then
            _chg_new "Pillow (Python imaging library)"
            ok "Pillow installed"
        else
            case "$OS" in
                windows) warn "Pillow install failed — run: pip install pillow" ;;
                *)       warn "Pillow install failed — run: pip install pillow --break-system-packages" ;;
            esac
        fi
    fi
fi

_chg_existing  # animatex-svg stdlib note (always passes)
ok "animatex-svg: stdlib only — no extra deps"
ok "equicycle.py: stdlib only — no extra deps"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — ENGINE CHECKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Engines"

[[ -f "$ABS_TEXT_SCRIPT" ]] && { _chg_existing; ok "animate-text engine"; } \
    || warn "animate-text engine missing"
[[ -f "$ABS_SVG_SCRIPT"  ]] && { _chg_existing; ok "animate-svg engine"; } \
    || warn "animate-svg engine missing"

FC="$(find "$ABS_TEXT_FONTS" -maxdepth 1 \( -iname "*.ttf" -o -iname "*.otf" \) 2>/dev/null | wc -l)"
(( FC > 0 )) && { _chg_existing; ok "animate-text: $FC font(s)"; } \
    || warn "animate-text: no fonts in $ABS_TEXT_FONTS"

hr "backup-space"

if command -v rclone &>/dev/null; then
    _chg_existing
    ok "rclone $(rclone version 2>/dev/null | head -1 | awk '{print $2}')"
else
    case "$OS" in
        linux)   warn "rclone not found — install: $PKG_MGR rclone  or  https://rclone.org/install/" ;;
        mac)     warn "rclone not found — install: brew install rclone  or  https://rclone.org/install/" ;;
        windows) warn "rclone not found — install: winget install Rclone.Rclone  or  https://rclone.org/install/" ;;
        *)       warn "rclone not found — see https://rclone.org/install/" ;;
    esac
fi

[[ -f "$ABS_BK_CONF" ]] && { _chg_existing; ok "backups.conf present"; } \
    || warn "backups.conf missing"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — .gitignore FOR GENERATED OUTPUT DIRS
# ─────────────────────────────────────────────────────────────────────────────
hr ".gitignore for output dirs"

for d in "$ABS_TEXT_EXPORTS" "$ABS_SVG_EXPORTS" "$ABS_BK_LOGS"; do
    gi="$d/.gitignore"
    if [[ ! -f "$gi" ]]; then
        printf '*\n!.gitignore\n' > "$gi"
        _chg_new ".gitignore in $(basename "$d")"
        ok "Created: $gi"
    else
        _chg_existing
        ok "Present: $gi"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 9 — VM TOOLS  (Linux/macOS only — skip on Windows)
# ─────────────────────────────────────────────────────────────────────────────
hr "VM tools"

if [[ "$OS" == "windows" ]]; then
    ok "Windows detected — virsh/virt-viewer not applicable"
    ok "serverx/creatorx require Linux with libvirt. Use WSL2 or a Linux host."
else
    if command -v virsh &>/dev/null; then
        _chg_existing
        ok "virsh available  (serverx / creatorx -> VM management)"
    else
        case "$OS" in
            linux) warn "virsh not found — serverx/creatorx will not work  ($PKG_MGR libvirt)" ;;
            mac)   warn "virsh not found — serverx/creatorx require Linux  (use UTM or a VM)" ;;
        esac
    fi

    if command -v virt-viewer &>/dev/null; then
        _chg_existing
        ok "virt-viewer available  (creatorx -> Windows VM GUI)"
    else
        case "$OS" in
            linux) warn "virt-viewer not found — creatorx needs it  ($PKG_MGR virt-viewer)" ;;
            mac)   warn "virt-viewer not found — not available on macOS" ;;
        esac
    fi
fi

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
    _chg_new "sconl-space/data/.gitignore"
    ok "Created sconl-space/data/.gitignore"
else
    _chg_existing
    ok "sconl-space/data/.gitignore present"
fi

# -- Scope flat-file TSV headers --
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

# -- Space flat-file TSV headers --
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

# -- Spark flat-file TSV headers --
init_tsv "$ABS_SC_DATA_SPARK/ideas.tsv" \
    "ID\tSTAGE\tTYPE\tBODY\tTITLE\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SPARK/learning.tsv" \
    "ID\tTITLE\tTYPE\tSTATUS\tPROGRESS\tAUTHOR\tCREATED_AT\tUPDATED_AT"

init_tsv "$ABS_SC_DATA_SPARK/dia.tsv" \
    "ID\tNAME\tROLE\tTYPE\tDEPTH\tLAST_CONTACT\tTRAJECTORY\tCREATED_AT"

# -- Shared event bus (flat mode) --
init_tsv "$ABS_SC_DATA/events.tsv" \
    "ID\tSOURCE\tTYPE\tPAYLOAD\tCREATED_AT\tCONSUMED_BY"

# -- Legacy tasks.tsv compatibility (kept for v1.0.0 data migration) --
if [[ ! -f "$ABS_SC_DATA/tasks.tsv" ]]; then
    printf 'ID\tSTATUS\tPRIORITY\tDUE\tCREATED\tTITLE\tTAGS\n' > "$ABS_SC_DATA/tasks.tsv"
    _chg_new "legacy tasks.tsv (v1.0.0 compatibility)"
    ok "Initialized legacy tasks.tsv (v1.0.0 compatibility)"
else
    _chg_existing
    ok "Legacy tasks.tsv present"
fi

# -- Calendar data init --
CALENDAR_JSON="$ABS_SC_DATA/calendar.json"
if [[ ! -f "$CALENDAR_JSON" ]]; then
    cat > "$CALENDAR_JSON" << 'JSON'
{
  "_comment": "sconl-space/data/calendar.json — personal calendar data. Edit directly or: sconlx cal edit",
  "birthdays": [],
  "custom_events": [],
  "settings": {
    "upcoming_days_ahead": 30,
    "birthday_warn_days": 7,
    "show_holidays": true,
    "holiday_regions": ["KE", "INT"],
    "show_today_in_history": true,
    "history_facts_per_day": 3
  }
}
JSON
    _chg_new "calendar.json"
    ok "Initialized calendar.json"
else
    _chg_existing
    ok "calendar.json present"
fi

# -- Equicycle engine check --
EQUICYCLE_PY="$ABS_SCONLSPACE/lib/equicycle.py"
if [[ -f "$EQUICYCLE_PY" ]]; then
    _chg_existing
    ok "equicycle.py engine found"
    if [[ -n "$PYTHON3" ]] && "$PYTHON3" "$EQUICYCLE_PY" --format fields &>/dev/null 2>&1; then
        _chg_existing
        ok "equicycle.py working"
    else
        warn "equicycle.py found but failed self-test — check $PYTHON3 installation"
    fi
else
    warn "equicycle.py missing at $EQUICYCLE_PY — sconlx cycle display won't work"
fi

# -- sqlite3 check --
if command -v sqlite3 &>/dev/null; then
    _chg_existing
    ok "sqlite3 available (SQLite mode ready when Flutter apps installed)"
else
    case "$OS" in
        linux)   warn "sqlite3 not found — install: $PKG_MGR sqlite" ;;
        mac)     warn "sqlite3 not found — install: brew install sqlite" ;;
        windows) warn "sqlite3 not found — install: winget install SQLite.SQLite" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# DONE — marker
# ─────────────────────────────────────────────────────────────────────────────

touch "$_X_MARKER/installed"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  -- Install summary -------------------------------------------"
echo ""

if (( ${#_CHG_NEW[@]} > 0 )); then
    echo "  New (${#_CHG_NEW[@]})"
    for item in "${_CHG_NEW[@]}"; do
        echo "    +  $item"
    done
    echo ""
fi

if (( ${#_CHG_UPDATED[@]} > 0 )); then
    echo "  Updated (${#_CHG_UPDATED[@]})"
    for item in "${_CHG_UPDATED[@]}"; do
        echo "    ~  $item"
    done
    echo ""
fi

if (( ${#_CHG_WARNED[@]} > 0 )); then
    echo "  Warnings (${#_CHG_WARNED[@]})"
    for item in "${_CHG_WARNED[@]}"; do
        echo "    !  $item"
    done
    echo ""
fi

_total_changes=$(( ${#_CHG_NEW[@]} + ${#_CHG_UPDATED[@]} ))
if (( _total_changes == 0 )); then
    echo "  Everything already up to date."
    echo ""
else
    echo "  ${#_CHG_NEW[@]} new   ${#_CHG_UPDATED[@]} updated   ${_CHG_EXISTING} unchanged   ${#_CHG_WARNED[@]} warnings"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# COMPLETE
# ─────────────────────────────────────────────────────────────────────────────

echo "  -- Complete --------------------------------------------------"
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
echo "    installx             re-run this installer (from anywhere)"
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
echo "  Moved the repo? Re-run installx — symlinks update automatically."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PAUSE  (keeps the window open after "Run as Program" in GNOME Files, etc.)
# Suppress with --no-pause when called from update.sh, installx, or CI.
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$_NO_PAUSE" != "1" ]]; then
    echo "  Press Enter to close..."
    read -r _
    echo ""
fi