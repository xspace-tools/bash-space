#!/usr/bin/env bash
# animate-space/lib/animatex_svg.sh
#
# All shell logic for animatex-svg (animated SVG/HTML generation).
# Sourced by animate-space/bin/animatex-svg and animate-space/lib/animatex.sh
# — never run directly.
#
# Key differences from animatex_text:
#   - No Pillow dependency — Python stdlib only
#   - Output is .svg or .html (not .gif)
#   - No fps — CSS/JS handles timing
#   - Font specified as CSS font-family name, not a file
#   - html mode: JS state machine, multi-line, standalone file
#   - svg mode: pure CSS @keyframes, single-line, embeddable anywhere
#
# Public API:
#   animatex_svg_run    — routes interactive vs direct
#   animatex_svg_help   — prints usage

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Moved from x-space/lib/ to animate-space/lib/. Path comment
#             updated. xspace.conf var names updated to ANIMATEX_SVG_*.
#             No logic changes.
#   v0.1.0 — Initial release. Separate from animatex_text — different engine,
#             config, and output format. _axs_ prefix convention.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_SVG_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_SVG_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — SVG-specific defaults
# ─────────────────────────────────────────────────────────────────────────────

_AXS_DEFAULT_VIEWBOX_WIDTH=1200
_AXS_DEFAULT_VIEWBOX_HEIGHT=200
_AXS_DEFAULT_FONT_FAMILY="Poppins"
_AXS_DEFAULT_FONT_WEIGHT="700"
_AXS_DEFAULT_FONT_SIZE="64px"
_AXS_DEFAULT_CHAR_DELAY="0.05"
_AXS_DEFAULT_PAUSE_DURATION="2.0"
_AXS_DEFAULT_FADE_DURATION="0.3"
_AXS_DEFAULT_CURSOR="true"
_AXS_DEFAULT_CURSOR_CHAR="|"
_AXS_DEFAULT_CURSOR_BLINK="0.8"
_AXS_DEFAULT_FORMAT="html"
_AXS_DEFAULT_BRAND="#00CC66"
_AXS_DEFAULT_VERSION="1.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# PATH RESOLUTION
# ─────────────────────────────────────────────────────────────────────────────

_axs_resolve_paths() {
    _AXS_ENGINE="$XSPACE_ROOT/$ANIMATEX_SVG_SCRIPT"
    _AXS_FONTS_DIR="$XSPACE_ROOT/$ANIMATEX_SVG_FONTS_DIR"
    _AXS_EXPORTS_DIR="$XSPACE_ROOT/$ANIMATEX_SVG_EXPORTS_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────

_axs_check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "animatex-svg: python3 required but not found."
        return 1
    fi
}

_axs_check_engine() {
    if [[ ! -f "$_AXS_ENGINE" ]]; then
        echo "animatex-svg: engine not found: $_AXS_ENGINE"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_axs_preview_hex() {
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

_axs_bump_version() {
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

_axs_run_engine() {
    mkdir -p "$_AXS_EXPORTS_DIR"
    python3 "$_AXS_ENGINE" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE MODE
# ─────────────────────────────────────────────────────────────────────────────

_axs_interactive() {
    echo ""
    echo "  animatex-svg — animated SVG/HTML generator"
    echo "  ────────────────────────────────────────────"

    read -ep "  Project name: " PROJECT;  PROJECT="${PROJECT:-project}"
    read -ep "  Version [$_AXS_DEFAULT_VERSION]: " VERSION; VERSION="${VERSION:-$_AXS_DEFAULT_VERSION}"

    read -rp "  Bump version? (y/N): " _b
    [[ "$_b" =~ ^[Yy]$ ]] && _axs_bump_version "$VERSION" && echo "  → $VERSION"

    echo ""; echo "  Sentences (blank line to finish):"
    _LINES=()
    while IFS= read -r _l; do [[ -z "$_l" ]] && break; _LINES+=("$_l"); done
    [[ ${#_LINES[@]} -eq 0 ]] && _LINES=("Hello world" "Animated SVG text")
    TEXT="$(IFS='|'; echo "${_LINES[*]}")"

    read -ep "  Brand color [$_AXS_DEFAULT_BRAND]: " BRAND; BRAND="${BRAND:-$_AXS_DEFAULT_BRAND}"
    echo "  Preview:"; _axs_preview_hex "$BRAND"

    read -ep "  Font family [$_AXS_DEFAULT_FONT_FAMILY]: " FONT_FAMILY
    FONT_FAMILY="${FONT_FAMILY:-$_AXS_DEFAULT_FONT_FAMILY}"
    read -ep "  Font weight [$_AXS_DEFAULT_FONT_WEIGHT]: " FONT_WEIGHT
    FONT_WEIGHT="${FONT_WEIGHT:-$_AXS_DEFAULT_FONT_WEIGHT}"
    read -ep "  Font size [$_AXS_DEFAULT_FONT_SIZE]: " FONT_SIZE
    FONT_SIZE="${FONT_SIZE:-$_AXS_DEFAULT_FONT_SIZE}"

    read -ep "  ViewBox width  [$_AXS_DEFAULT_VIEWBOX_WIDTH]: "  VB_W
    VB_W="${VB_W:-$_AXS_DEFAULT_VIEWBOX_WIDTH}"
    read -ep "  ViewBox height [$_AXS_DEFAULT_VIEWBOX_HEIGHT]: " VB_H
    VB_H="${VB_H:-$_AXS_DEFAULT_VIEWBOX_HEIGHT}"

    read -ep "  Char delay [$_AXS_DEFAULT_CHAR_DELAY]: " CHAR_DELAY
    CHAR_DELAY="${CHAR_DELAY:-$_AXS_DEFAULT_CHAR_DELAY}"
    read -ep "  Pause after line [$_AXS_DEFAULT_PAUSE_DURATION]: " PAUSE
    PAUSE="${PAUSE:-$_AXS_DEFAULT_PAUSE_DURATION}"

    read -ep "  Cursor (true/false) [$_AXS_DEFAULT_CURSOR]: " CURSOR
    CURSOR="${CURSOR:-$_AXS_DEFAULT_CURSOR}"

    echo "  Output format:"
    echo "    1) html — JS state machine, multi-line loop (recommended)"
    echo "    2) svg  — pure CSS, single-line, embeddable"
    read -ep "  Select [1]: " _fmt; _fmt="${_fmt:-1}"
    FORMAT="$_AXS_DEFAULT_FORMAT"
    [[ "$_fmt" == "2" || "$_fmt" == "svg" ]] && FORMAT="svg"

    local DATE; DATE="$(date +%Y%m%d)"

    echo ""
    echo "  ──────────────────────────────────────────────────────"
    echo "  Project   : $PROJECT v$VERSION  ($DATE)"
    echo "  Text      : $TEXT"
    echo "  Brand     : $BRAND"
    echo "  Font      : $FONT_FAMILY $FONT_WEIGHT @ $FONT_SIZE"
    echo "  ViewBox   : ${VB_W}×${VB_H}"
    echo "  Timing    : ${CHAR_DELAY}s/char  pause: ${PAUSE}s"
    echo "  Cursor    : $CURSOR"
    echo "  Format    : $FORMAT"
    echo "  Output    : $_AXS_EXPORTS_DIR/"
    echo "  ──────────────────────────────────────────────────────"

    read -rp "  Generate? (y/N): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "  Cancelled." && return 0

    _axs_run_engine \
        --text "$TEXT" --brand "$BRAND" \
        --font-family "$FONT_FAMILY" --font-weight "$FONT_WEIGHT" --font-size "$FONT_SIZE" \
        --viewbox-width "$VB_W" --viewbox-height "$VB_H" \
        --char-delay "$CHAR_DELAY" --pause "$PAUSE" \
        --cursor "$CURSOR" --format "$FORMAT" \
        --project "$PROJECT" --version "$VERSION" --date "$DATE"
}

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

animatex_svg_run() {
    _axs_resolve_paths
    _axs_check_python || return 1
    _axs_check_engine || return 1

    if [[ $# -eq 0 ]] || [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
        _axs_interactive; return $?
    fi

    _axs_run_engine "$@"
}

animatex_svg_help() {
    cat <<'HELP'

  animatex-svg — animated typing SVG/HTML with gradient text

  USAGE
    animatex-svg                         interactive
    animatex-svg --interactive / -i      same
    animatex-svg [options]               direct / scriptable

  OPTIONS
    --text           "Line 1|Line 2"   pipe-separated sentences
    --brand          "#00CC66"         primary brand hex
    --gradient1      "#00C800"         gradient start (overrides --brand)
    --gradient2      "#B4FF00"         gradient end   (overrides --brand)
    --font-family    Poppins           CSS font-family
    --font-weight    700               CSS font-weight
    --font-size      64px              CSS font-size with unit
    --viewbox-width  1200              SVG viewBox width
    --viewbox-height 200               SVG viewBox height
    --char-delay     0.05              seconds between characters
    --pause          2.0               hold time after line completes
    --fade           0.3               fade transition duration
    --cursor         true              show blinking cursor (true/false)
    --cursor-char    |                 cursor character
    --cursor-blink   0.8               blink period seconds
    --format         html              html (JS, multi-line) | svg (CSS, single-line)
    --project        project           output filename slug
    --version        0.0.0             output filename version
    --date           YYYYMMDD          date prefix (default: today)

  OUTPUT
    animate-space/animate-svg/exports/{date}_asset_animated_svg_{project}_v{version}.{ext}

HELP
}