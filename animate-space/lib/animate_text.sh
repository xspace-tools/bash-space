#!/usr/bin/env bash
# animate-space/lib/animatex_text.sh
#
# All shell logic for animatex-text (animated GIF generation).
# Sourced by animate-space/bin/animatex-text and animate-space/lib/animatex.sh
# — never run directly.
#
# Expects XSPACE_ROOT and all xspace.conf vars to be set by the caller.
#
# Public API:
#   animatex_text_run    — routes interactive vs direct mode
#   animatex_text_help   — prints usage

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Moved from x-space/lib/ to animate-space/lib/. Path comment
#             updated. xspace.conf var names updated to ANIMATEX_TEXT_*.
#             No logic changes.
#   v0.1.0 — Initial release. Extracted from _run/run_typing_effect.sh.
#             Interactive + direct-passthrough mode. _axt_ prefix convention.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_TEXT_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_TEXT_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — interactive prompt defaults
# ─────────────────────────────────────────────────────────────────────────────

_AXT_DEFAULT_VERSION="1.0.0"
_AXT_DEFAULT_BRAND="#00CC66"
_AXT_DEFAULT_ALIGN="center"
_AXT_DEFAULT_WIDTH=1200
_AXT_DEFAULT_HEIGHT=200
_AXT_DEFAULT_FONTSIZE=64
_AXT_DEFAULT_FPS=24

# ─────────────────────────────────────────────────────────────────────────────
# PATH RESOLUTION
# ─────────────────────────────────────────────────────────────────────────────
# Called at runtime — XSPACE_ROOT guaranteed set by caller at that point.

_axt_resolve_paths() {
    _AXT_ENGINE="$XSPACE_ROOT/$ANIMATEX_TEXT_SCRIPT"
    _AXT_FONTS_DIR="$XSPACE_ROOT/$ANIMATEX_TEXT_FONTS_DIR"
    _AXT_EXPORTS_DIR="$XSPACE_ROOT/$ANIMATEX_TEXT_EXPORTS_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────

_axt_check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "animatex-text: python3 required but not found."
        echo "               Install Python 3.8+ and re-run _configure/install.sh"
        return 1
    fi
    if ! python3 -c "import PIL" &>/dev/null; then
        echo "animatex-text: Pillow not installed."
        echo "               Run: pip install pillow --break-system-packages"
        return 1
    fi
}

_axt_check_engine() {
    if [[ ! -f "$_AXT_ENGINE" ]]; then
        echo "animatex-text: engine not found: $_AXT_ENGINE"
        return 1
    fi
}

_axt_check_fonts() {
    if [[ ! -d "$_AXT_FONTS_DIR" ]] || [[ -z "$(ls -A "$_AXT_FONTS_DIR" 2>/dev/null)" ]]; then
        echo "  ⚠  No fonts in $_AXT_FONTS_DIR — PIL fallback will be used"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_axt_preview_hex() {
    local hex="${1#\#}"
    python3 - "$hex" <<'PY'
import sys
h = sys.argv[1]
try:
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
except Exception:
    print("  (invalid hex)"); sys.exit(0)
print(f"  #{h.upper()}  \033[48;2;{r};{g};{b}m        \033[0m")
PY
}

# Mutates global VERSION in-place — subshells can't propagate changes back
_axt_bump_version() {
    local ver="$1"
    [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && return 0
    local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
    echo "  1) patch  →  $major.$minor.$((patch + 1))"
    echo "  2) minor  →  $major.$((minor + 1)).0"
    echo "  3) major  →  $((major + 1)).0.0"
    echo "  4) keep   →  $ver"
    read -rp "  Select [1-4] (default: 1): " sel; sel="${sel:-1}"
    case "$sel" in
        1|p) VERSION="$major.$minor.$((patch + 1))" ;;
        2|m) VERSION="$major.$((minor + 1)).0"      ;;
        3|M) VERSION="$((major + 1)).0.0"           ;;
        *)   VERSION="$ver"                         ;;
    esac
}

_axt_pick_font() {
    mapfile -t _AXT_FONTS < <(
        find "$_AXT_FONTS_DIR" -maxdepth 1 -type f \
            \( -iname "*.ttf" -o -iname "*.otf" \) \
            -printf '%f\n' 2>/dev/null | sort
    )
    if [[ ${#_AXT_FONTS[@]} -eq 0 ]]; then
        read -rp "  No fonts found. Enter system font path: " FONTFILE; return 0
    fi
    echo ""
    echo "  Available fonts:"
    for i in "${!_AXT_FONTS[@]}"; do printf "    %3d) %s\n" $((i+1)) "${_AXT_FONTS[$i]}"; done
    read -rp "  Select [${_AXT_FONTS[0]}]: " sel
    if [[ -z "$sel" ]]; then
        FONTFILE="${_AXT_FONTS[0]}"
    elif [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#_AXT_FONTS[@]} )); then
        FONTFILE="${_AXT_FONTS[$((sel-1))]}"
    else
        FONTFILE="$sel"
    fi
}

_axt_run_engine() {
    mkdir -p "$_AXT_EXPORTS_DIR"
    python3 "$_AXT_ENGINE" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE MODE
# ─────────────────────────────────────────────────────────────────────────────

_axt_interactive() {
    echo ""
    echo "  animatex-text — animated GIF generator"
    echo "  ────────────────────────────────────────"

    read -ep "  Project name: " PROJECT;  PROJECT="${PROJECT:-project}"
    read -ep "  Version [$_AXT_DEFAULT_VERSION]: " VERSION; VERSION="${VERSION:-$_AXT_DEFAULT_VERSION}"

    read -rp "  Bump version? (y/N): " _b
    [[ "$_b" =~ ^[Yy]$ ]] && _axt_bump_version "$VERSION" && echo "  → $VERSION"

    echo ""; echo "  Sentences (blank line to finish):"
    _LINES=()
    while IFS= read -r _l; do [[ -z "$_l" ]] && break; _LINES+=("$_l"); done
    [[ ${#_LINES[@]} -eq 0 ]] && _LINES=("Hello world" "Animated gradient text")
    TEXT="$(IFS='|'; echo "${_LINES[*]}")"

    read -ep "  Brand color [$_AXT_DEFAULT_BRAND]: " BRAND; BRAND="${BRAND:-$_AXT_DEFAULT_BRAND}"
    echo "  Preview:"; _axt_preview_hex "$BRAND"

    read -ep "  Alignment (left/center/right) [$_AXT_DEFAULT_ALIGN]: " ALIGN
    ALIGN="${ALIGN:-$_AXT_DEFAULT_ALIGN}"
    read -ep "  Width  [$_AXT_DEFAULT_WIDTH]: "  WIDTH;   WIDTH="${WIDTH:-$_AXT_DEFAULT_WIDTH}"
    read -ep "  Height [$_AXT_DEFAULT_HEIGHT]: " HEIGHT;  HEIGHT="${HEIGHT:-$_AXT_DEFAULT_HEIGHT}"

    _axt_check_fonts
    _axt_pick_font

    read -ep "  Font size [$_AXT_DEFAULT_FONTSIZE]: " FONTSIZE; FONTSIZE="${FONTSIZE:-$_AXT_DEFAULT_FONTSIZE}"
    read -ep "  FPS [$_AXT_DEFAULT_FPS]: " FPS; FPS="${FPS:-$_AXT_DEFAULT_FPS}"

    local DATE; DATE="$(date +%Y%m%d)"

    echo ""
    echo "  ──────────────────────────────────────────────────────"
    echo "  Project : $PROJECT v$VERSION  ($DATE)"
    echo "  Text    : $TEXT"
    echo "  Brand   : $BRAND"
    echo "  Canvas  : ${WIDTH}×${HEIGHT} @ ${FPS}fps  align: $ALIGN"
    echo "  Font    : $FONTFILE @ ${FONTSIZE}px"
    echo "  Output  : $_AXT_EXPORTS_DIR/"
    echo "  ──────────────────────────────────────────────────────"

    read -rp "  Generate? (y/N): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "  Cancelled." && return 0

    _axt_run_engine \
        --text "$TEXT" --brand "$BRAND" --align "$ALIGN" \
        --width "$WIDTH" --height "$HEIGHT" \
        --font "$FONTFILE" --fontsize "$FONTSIZE" \
        --fps "$FPS" --project "$PROJECT" --version "$VERSION" --date "$DATE"
}

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

animatex_text_run() {
    _axt_resolve_paths
    _axt_check_python || return 1
    _axt_check_engine || return 1

    if [[ $# -eq 0 ]] || [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
        _axt_interactive; return $?
    fi

    _axt_check_fonts
    _axt_run_engine "$@"
}

animatex_text_help() {
    cat <<'HELP'

  animatex-text — animated typing GIF with gradient text

  USAGE
    animatex-text                          interactive
    animatex-text --interactive / -i       same
    animatex-text [options]                direct / scriptable

  OPTIONS
    --text       "Line 1|Line 2"    pipe-separated sentences
    --brand      "#00CC66"          primary brand hex (auto-derives gradient)
    --gradient1  "#00C800"          gradient start (overrides --brand)
    --gradient2  "#B4FF00"          gradient end   (overrides --brand)
    --align      center             left | center | right
    --width      1200               canvas width px
    --height     200                canvas height px
    --font       Poppins-Bold.ttf   filename in fonts/ or absolute path
    --fontsize   64                 font size px
    --fps        24                 frames per second
    --project    project            output filename slug
    --version    0.0.0              output filename version
    --date       YYYYMMDD           date prefix (default: today)

  OUTPUT
    animate-space/animate-text/exports/{date}_asset_animated_text_{project}_v{version}.gif

HELP
}