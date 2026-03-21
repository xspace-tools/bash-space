#!/usr/bin/env bash
# x-space/lib/animatex.sh
#
# All shell logic for the animatex tool suite.
# Sourced by bin/animatex — never run directly.
#
# Expects these variables to already be set by the caller (bin/animatex does this):
#   XSPACE_ROOT   — absolute path to the xspace monorepo root
#   XSPACE_DIR    — absolute path to x-space/
#   (all xspace.conf vars already sourced)
#
# Exports:
#   animatex_text    — routes 'animatex text' (interactive or direct CLI)
#   animatex_help    — prints usage
#   _ax_*            — internal helpers (prefixed to avoid polluting the shell)

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Renamed bash-space → x-space; engine paths now resolved via
#             XSPACE_ROOT + xspace.conf vars (no hardcoded relative paths);
#             XSPACE_DIR replaces BASHSPACE_ROOT; guard against double-source.
#   v0.1.0 — Initial release. Extracted from _run/run_typing_effect.sh and
#             generalised: interactive + direct-passthrough mode; config block;
#             _ax_ prefix convention for internals.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — tunables that live here, not scattered across functions
# ─────────────────────────────────────────────────────────────────────────────

# ── Interactive prompt defaults ───────────────────────────────────────────────
_AX_DEFAULT_VERSION="1.0.0"
_AX_DEFAULT_BRAND="#00CC66"
_AX_DEFAULT_ALIGN="center"
_AX_DEFAULT_WIDTH=1200
_AX_DEFAULT_HEIGHT=200
_AX_DEFAULT_FONTSIZE=64
_AX_DEFAULT_FPS=24

# ─────────────────────────────────────────────────────────────────────────────
# PATH RESOLUTION
# ─────────────────────────────────────────────────────────────────────────────
# All paths derived from XSPACE_ROOT + the vars in xspace.conf.
# _ax_resolve_paths() is called at the start of animatex_text — not at
# source time — so XSPACE_ROOT is guaranteed to be set by then.

_ax_resolve_paths() {
    _AX_ENGINE_SCRIPT="$XSPACE_ROOT/$ANIMATEX_PYTHON_SCRIPT"
    _AX_FONTS_DIR="$XSPACE_ROOT/$ANIMATEX_FONTS_DIR"
    _AX_EXPORTS_DIR="$XSPACE_ROOT/$ANIMATEX_EXPORTS_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

_ax_check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "animatex: python3 is required but not found."
        echo "          Install Python 3.8+ and re-run x-space/install.sh"
        return 1
    fi
    if ! python3 -c "import PIL" &>/dev/null; then
        echo "animatex: Pillow is not installed."
        echo "          Run: pip install pillow --break-system-packages"
        return 1
    fi
}

_ax_check_engine() {
    if [[ ! -f "$_AX_ENGINE_SCRIPT" ]]; then
        echo "animatex: engine not found:"
        echo "          $_AX_ENGINE_SCRIPT"
        echo "          Expected: gradient_typing_effect.py"
        echo "          Place it in: $XSPACE_ROOT/$ANIMATEX_TEXT_DIR/python/"
        return 1
    fi
}

_ax_check_fonts_dir() {
    # Non-fatal — falls back to PIL bitmap font. Just warn.
    if [[ ! -d "$_AX_FONTS_DIR" ]] || [[ -z "$(ls -A "$_AX_FONTS_DIR" 2>/dev/null)" ]]; then
        echo "  ⚠  No fonts in $_AX_FONTS_DIR"
        echo "     Falling back to PIL's built-in bitmap font."
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Print a small ANSI 24-bit color swatch — sanity check before a long render
_ax_preview_hex() {
    local hex="${1#\#}"
    python3 - "$hex" <<'PY'
import sys
h = sys.argv[1]
try:
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
except Exception:
    print("  (invalid hex — skipping preview)")
    sys.exit(0)
print(f"  #{h.upper()}  \033[48;2;{r};{g};{b}m        \033[0m")
PY
}

# Mutates global VERSION in-place — subshells can't propagate changes back
_ax_bump_version() {
    local ver="$1"

    if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "  '$ver' is not semver — keeping unchanged."
        return 0
    fi

    local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"

    echo "  1) patch  →  $major.$minor.$((patch + 1))    small fixes"
    echo "  2) minor  →  $major.$((minor + 1)).0         new features"
    echo "  3) major  →  $((major + 1)).0.0              breaking changes"
    echo "  4) keep   →  $ver"
    read -rp "  Select [1-4 | p/m/M/k] (default: 1): " sel
    sel="${sel:-1}"

    case "$sel" in
        1|p|patch) VERSION="$major.$minor.$((patch + 1))" ;;
        2|m|minor) VERSION="$major.$((minor + 1)).0"      ;;
        3|M|major) VERSION="$((major + 1)).0.0"           ;;
        4|k|keep)  VERSION="$ver"                         ;;
        *)         echo "  Unrecognised — keeping: $ver"; VERSION="$ver" ;;
    esac
}

# Numbered font picker — sets global FONTFILE
_ax_pick_font() {
    mapfile -t _AX_FONTFILES < <(
        find "$_AX_FONTS_DIR" -maxdepth 1 -type f \
            \( -iname "*.ttf" -o -iname "*.otf" \) \
            -printf '%f\n' 2>/dev/null | sort
    )

    if [[ ${#_AX_FONTFILES[@]} -eq 0 ]]; then
        read -rp "  No fonts found. Enter a system font path: " FONTFILE
        return 0
    fi

    echo "  Available fonts:"
    for i in "${!_AX_FONTFILES[@]}"; do
        printf "    %3d) %s\n" $((i + 1)) "${_AX_FONTFILES[$i]}"
    done

    read -rp "  Select by number or filename [${_AX_FONTFILES[0]}]: " sel
    if [[ -z "$sel" ]]; then
        FONTFILE="${_AX_FONTFILES[0]}"
    elif [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#_AX_FONTFILES[@]} )); then
        FONTFILE="${_AX_FONTFILES[$((sel - 1))]}"
    else
        FONTFILE="$sel"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ENGINE RUNNER
# ─────────────────────────────────────────────────────────────────────────────

_ax_run_engine() {
    mkdir -p "$_AX_EXPORTS_DIR"
    python3 "$_AX_ENGINE_SCRIPT" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE MODE
# ─────────────────────────────────────────────────────────────────────────────

_ax_text_interactive() {
    echo ""
    echo "  animatex text"
    echo "  ─────────────────────────────────"

    read -ep "  Project name: " PROJECT;  PROJECT="${PROJECT:-project}"
    read -ep "  Version [$_AX_DEFAULT_VERSION]: " VERSION; VERSION="${VERSION:-$_AX_DEFAULT_VERSION}"

    read -rp "  Bump version? (y/N): " _bump
    if [[ "$_bump" =~ ^[Yy]$ ]]; then
        _ax_bump_version "$VERSION"
        echo "  → $VERSION"
    fi

    echo ""
    echo "  Enter sentences (blank line to finish):"
    _AX_LINES=()
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && break
        _AX_LINES+=("$_line")
    done
    if [[ ${#_AX_LINES[@]} -eq 0 ]]; then
        echo "  No input — using sample text."
        _AX_LINES=("Hello world" "Animated gradient text")
    fi
    TEXT="$(IFS='|'; echo "${_AX_LINES[*]}")"

    read -ep "  Brand color [$_AX_DEFAULT_BRAND]: " BRAND; BRAND="${BRAND:-$_AX_DEFAULT_BRAND}"
    echo "  Preview:"
    _ax_preview_hex "$BRAND"

    read -ep "  Alignment (left/center/right) [$_AX_DEFAULT_ALIGN]: " ALIGN
    ALIGN="${ALIGN:-$_AX_DEFAULT_ALIGN}"

    read -ep "  Width  [$_AX_DEFAULT_WIDTH]: "  WIDTH;   WIDTH="${WIDTH:-$_AX_DEFAULT_WIDTH}"
    read -ep "  Height [$_AX_DEFAULT_HEIGHT]: " HEIGHT;  HEIGHT="${HEIGHT:-$_AX_DEFAULT_HEIGHT}"

    _ax_check_fonts_dir
    _ax_pick_font

    read -ep "  Font size [$_AX_DEFAULT_FONTSIZE]: " FONTSIZE; FONTSIZE="${FONTSIZE:-$_AX_DEFAULT_FONTSIZE}"
    read -ep "  FPS [$_AX_DEFAULT_FPS]: "              FPS;     FPS="${FPS:-$_AX_DEFAULT_FPS}"

    local DATE; DATE="$(date +%Y%m%d)"
    local OUTFILE="${DATE}_asset_animated_text_${PROJECT}_v${VERSION}.gif"

    echo ""
    echo "  ─────────────────────────────────────────────────────"
    echo "  Project : $PROJECT"
    echo "  Version : $VERSION"
    echo "  Date    : $DATE"
    echo "  Text    : $TEXT"
    echo "  Brand   : $BRAND"
    echo "  Align   : $ALIGN"
    echo "  Canvas  : ${WIDTH}×${HEIGHT}  @  ${FPS}fps"
    echo "  Font    : $FONTFILE @ ${FONTSIZE}px"
    echo "  Output  : $_AX_EXPORTS_DIR/$OUTFILE"
    echo "  ─────────────────────────────────────────────────────"

    read -rp "  Generate? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  Cancelled."
        return 0
    fi

    _ax_run_engine \
        --text      "$TEXT"     \
        --brand     "$BRAND"    \
        --align     "$ALIGN"    \
        --width     "$WIDTH"    \
        --height    "$HEIGHT"   \
        --font      "$FONTFILE" \
        --fontsize  "$FONTSIZE" \
        --fps       "$FPS"      \
        --project   "$PROJECT"  \
        --version   "$VERSION"  \
        --date      "$DATE"
}

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

animatex_text() {
    _ax_resolve_paths
    _ax_check_python || return 1
    _ax_check_engine || return 1

    # No args or explicit --interactive → guided prompt
    if [[ $# -eq 0 ]] || [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
        _ax_text_interactive
        return $?
    fi

    # Direct passthrough — all args forwarded to Python. No prompts.
    # This is the CI / scripting path.
    # Example: animatex text --brand "#FF6B00" --text "Launch|Live"
    _ax_check_fonts_dir
    _ax_run_engine "$@"
}

animatex_help() {
    cat <<'HELP'

  animatex — animated text asset generator

  USAGE
    animatex <subcommand> [options]

  SUBCOMMANDS
    text        Generate an animated typing GIF with gradient text
    help        Show this message
    version     Print installed version

  TEXT — interactive (prompts for everything):
    animatex text
    animatex text --interactive

  TEXT — direct / scriptable (no prompts):
    animatex text --brand "#00CC66" --text "Line 1|Line 2" [options]

    --text       <str>   Pipe-separated lines       e.g. "Hello|World"
    --brand      <hex>   Primary brand color        e.g. "#00CC66"
                         (engine computes gradient start automatically)
    --gradient1  <hex>   Gradient start  (overrides --brand)
    --gradient2  <hex>   Gradient end    (overrides --brand)
    --align      <str>   left | center | right      [center]
    --width      <int>   Canvas width px            [1200]
    --height     <int>   Canvas height px           [200]
    --font       <str>   Font filename or path      [Poppins-Bold.ttf]
    --fontsize   <int>   Font size px               [64]
    --fps        <int>   Frames per second          [24]
    --project    <str>   Project name slug          [project]
    --version    <str>   Semver string              [0.0.0]
    --date       <str>   Date prefix YYYYMMDD       [today]

  EXAMPLES
    animatex text
    animatex text --brand "#FF6B00" --text "Launch day|We're live" --project acme
    animatex text --gradient1 "#00C800" --gradient2 "#B4FF00" --align left

  OUTPUT
    animate-space/animate-text/exports/

HELP
}