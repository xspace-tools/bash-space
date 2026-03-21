#!/usr/bin/env bash
# x-space/install.sh
#
# Hands-free installer for the XSpace monorepo.
# Reads xspace.conf to resolve sibling tool locations, validates everything
# exists, then symlinks all x-space/bin/* scripts into ~/bin.
#
# Safe to re-run at any time — every operation is idempotent.
#
# Usage:
#   cd x-space && ./install.sh
#   XSPACE_ROOT=/custom/path ./install.sh    # if repo is somewhere else

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Renamed bash-space → x-space; switched to xspace.conf for all
#             path resolution; XSPACE_ROOT auto-detected from script location;
#             added git-space and code-space validation stubs; step-based
#             output with consistent log/ok/warn helpers.
#   v0.1.0 — Initial BashSpace installer. Symlinks bin/ → ~/bin, patches
#             shell RC with PATH line, Python/Pillow check, exports .gitignore.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP — resolve XSPACE_ROOT before anything else
# ─────────────────────────────────────────────────────────────────────────────
# install.sh lives at x-space/install.sh, so its parent is x-space/, and
# one level above that is the monorepo root. readlink -f resolves symlinks
# so this works whether you run it directly or via a wrapper.

_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
XSPACE_ROOT="${XSPACE_ROOT:-$(cd "$_SELF_DIR/.." && pwd)}"
XSPACE_DIR="$_SELF_DIR"   # x-space/ itself

# Load all path declarations from config
CONF="$XSPACE_DIR/xspace.conf"
if [[ ! -f "$CONF" ]]; then
    echo "install.sh: cannot find xspace.conf at $CONF"
    echo "            Are you running this from inside x-space/?"
    exit 1
fi
# shellcheck source=./xspace.conf
source "$CONF"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — resolved absolute paths (derived from xspace.conf + XSPACE_ROOT)
# ─────────────────────────────────────────────────────────────────────────────

BIN_DIR="$XSPACE_DIR/bin"
LIB_DIR="$XSPACE_DIR/lib"
USER_BIN="${USER_BIN:-${USER_BIN_DEFAULT}}"
MARKER_DIR="$XSPACE_DIR/.xspace"

# Tool space absolute paths
ABS_ANIMATESPACE="$XSPACE_ROOT/$ANIMATESPACE_DIR"
ABS_ANIMATEX_TEXT="$XSPACE_ROOT/$ANIMATEX_TEXT_DIR"
ABS_ANIMATEX_FONTS="$XSPACE_ROOT/$ANIMATEX_FONTS_DIR"
ABS_ANIMATEX_EXPORTS="$XSPACE_ROOT/$ANIMATEX_EXPORTS_DIR"
ABS_ANIMATEX_SCRIPT="$XSPACE_ROOT/$ANIMATEX_PYTHON_SCRIPT"
ABS_GITSPACE="$XSPACE_ROOT/$GITSPACE_DIR"
ABS_CODESPACE="$XSPACE_ROOT/$CODESPACE_DIR"

# Python dependency
PILLOW_PKG="Pillow"

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT HELPERS
# ─────────────────────────────────────────────────────────────────────────────

log()  { echo "    $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠  $*"; }
fail() { echo "  ✗ $*"; exit 1; }
hr()   {
    echo ""
    echo "  ── $* ──────────────────────────────────────────────────"
}

add_path_line() {
    local rc="$1" line="$2"
    mkdir -p "$(dirname "$rc")" 2>/dev/null || true
    if ! grep -Fxq "$line" "$rc" 2>/dev/null; then
        printf "\n# x-space: add ~/bin to PATH\n%s\n" "$line" >> "$rc"
        ok "Added PATH entry to $rc"
    else
        ok "PATH already configured in $rc"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "  XSpace installer"
echo "  XSPACE_ROOT : $XSPACE_ROOT"
echo "  x-space dir : $XSPACE_DIR"
echo "  user bin    : $USER_BIN"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — DIRECTORIES
# ─────────────────────────────────────────────────────────────────────────────
hr "Directories"

mkdir -p "$BIN_DIR" "$LIB_DIR" "$USER_BIN" "$MARKER_DIR"
mkdir -p "$ABS_ANIMATEX_FONTS" "$ABS_ANIMATEX_EXPORTS"
ok "Core directories ready"
ok "animate-space directories ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — BIN SYMLINKS
# ─────────────────────────────────────────────────────────────────────────────
hr "Symlinking x-space/bin → $USER_BIN"

chmod +x "$BIN_DIR"/* 2>/dev/null || true

for f in "$BIN_DIR"/*; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    ln -sf "$f" "$USER_BIN/$name"
    ok "Linked: $name"
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PATH CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
hr "Shell PATH"

if   [[ -n "${ZSH_VERSION-}"  ]]; then SHELL_RC="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION-}" ]]; then SHELL_RC="$HOME/.bashrc"
else                                    SHELL_RC="$HOME/.profile"
fi

SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_path_line "$SHELL_RC" "$SAFE_ADD"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — SIBLING SPACE VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
# We don't own these dirs — we just confirm they exist so dispatchers don't
# silently fail later. Non-fatal: warn and continue.

hr "Sibling spaces"

for space_label in "animate-space:$ABS_ANIMATESPACE" "git-space:$ABS_GITSPACE" "code-space:$ABS_CODESPACE"; do
    label="${space_label%%:*}"
    path="${space_label##*:}"
    if [[ -d "$path" ]]; then
        ok "$label found at $path"
    else
        warn "$label not found at $path"
        warn "      Run: mkdir -p '$path'  (or clone it into place)"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — PYTHON + PILLOW (animatex dependency)
# ─────────────────────────────────────────────────────────────────────────────
hr "Python + Pillow (required for animatex text)"

if ! command -v python3 &>/dev/null; then
    warn "python3 not found — animatex text will not work."
    warn "      Fedora: sudo dnf install python3"
    warn "      Ubuntu: sudo apt install python3"
else
    PY_VER="$(python3 --version 2>&1)"
    ok "$PY_VER"

    if python3 -c "import PIL" &>/dev/null; then
        PIL_VER="$(python3 -c "import PIL; print(PIL.__version__)")"
        ok "Pillow $PIL_VER already installed"
    else
        log "Installing Pillow..."
        # --break-system-packages required on Fedora/Ubuntu 23+ (PEP 668).
        # Fall back to --user if the flag is unrecognised on older systems.
        if pip3 install "$PILLOW_PKG" --break-system-packages &>/dev/null 2>&1; then
            ok "Pillow installed (system)"
        elif pip3 install "$PILLOW_PKG" --user &>/dev/null 2>&1; then
            ok "Pillow installed (user)"
        else
            warn "Could not install Pillow automatically."
            warn "      Run: pip install pillow --break-system-packages"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — ANIMATEX ENGINE CHECK
# ─────────────────────────────────────────────────────────────────────────────
hr "animatex engine"

if [[ -f "$ABS_ANIMATEX_SCRIPT" ]]; then
    ok "Engine: $ABS_ANIMATEX_SCRIPT"
else
    warn "Engine not found at:"
    warn "      $ABS_ANIMATEX_SCRIPT"
    warn "      Expected file: gradient_typing_effect.py"
    warn "      animatex text will not work until it's in place."
fi

# Font count — non-fatal, engine falls back to PIL bitmap font
FONT_COUNT="$(find "$ABS_ANIMATEX_FONTS" -maxdepth 1 \( -iname "*.ttf" -o -iname "*.otf" \) 2>/dev/null | wc -l)"
if (( FONT_COUNT > 0 )); then
    ok "$FONT_COUNT font(s) in animate-space/animate-text/fonts/"
else
    warn "No fonts found in $ABS_ANIMATEX_FONTS"
    warn "      Animatex will fall back to PIL's built-in bitmap font."
    warn "      Copy .ttf/.otf files there for custom fonts."
    warn "      Free fonts: https://fonts.google.com"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — EXPORTS .gitignore
# ─────────────────────────────────────────────────────────────────────────────
# Generated GIFs should never be committed — write a protective .gitignore
# into the exports dir. Only runs once; idempotent after that.

hr "exports .gitignore"

EXPORTS_GITIGNORE="$ABS_ANIMATEX_EXPORTS/.gitignore"
if [[ ! -f "$EXPORTS_GITIGNORE" ]]; then
    cat > "$EXPORTS_GITIGNORE" <<'EOF'
# Generated assets — do not commit
*
!.gitignore
EOF
    ok "Created animate-space/animate-text/exports/.gitignore"
else
    ok ".gitignore already present"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — REFRESHX BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────

hr "refreshx"

REFRESHX="$BIN_DIR/refreshx"
if [[ ! -f "$REFRESHX" ]]; then
    cat > "$REFRESHX" <<'SCRIPT'
#!/usr/bin/env bash
# x-space/bin/refreshx
# Reload shell config and clear command hash cache.
# Run after install.sh or any time you add a new bin script.
source ~/.bashrc
hash -r
echo "Shell refreshed."
SCRIPT
    chmod +x "$REFRESHX"
    ln -sf "$REFRESHX" "$USER_BIN/refreshx"
    ok "Created and linked refreshx"
else
    ok "refreshx already exists"
fi

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

touch "$MARKER_DIR/installed"

echo ""
echo "  ── Install complete ─────────────────────────────────────────"
echo ""
echo "  Run 'refreshx' or open a new terminal to activate x-space."
echo "  Then try:  animatex help"
echo ""
echo "  Available commands:"
for f in "$BIN_DIR"/*; do
    [[ -f "$f" ]] && echo "    $(basename "$f")"
done
echo ""