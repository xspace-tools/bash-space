#!/usr/bin/env bash
# animate-space/animate-svg/animatex_svg.sh
#
# Engine library for animated SVG/HTML generation.
# Sourced by animate-space/lib/animatex.sh (auto-discovered) and by
# animate-space/bin/animatex-svg (direct shortcut).

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.4.0 — Added _ANIMATEX_SVG_ORDER=20 (appears after text in menu).
#             imports/ folder noted — replaces fonts/ for SVG source files.
#             Two planned SVG source modes flagged with TODO markers:
#               MODE A: select from animate-svg/imports/ (SVG files to animate)
#               MODE B: provide an absolute file path
#             Both are scaffolded but not yet implemented.
#   v0.3.0 — Moved into animate-svg/. Added LABEL + DESC metadata.
#   v0.2.0 — Moved from x-space/lib/.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_SVG_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_SVG_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# ENGINE METADATA
# ─────────────────────────────────────────────────────────────────────────────

_ANIMATEX_SVG_LABEL="SVG / HTML animation"
_ANIMATEX_SVG_DESC="Animated .svg or .html — scalable, no Pillow, embeds in any page"
_ANIMATEX_SVG_ORDER=20   # appears after text in menu

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
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
    _AXS_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _AXS_ENGINE="$_AXS_ENGINE_DIR/python/svg_typing_effect.py"
    _AXS_EXPORTS_DIR="$_AXS_ENGINE_DIR/exports"

    # TODO [animate-svg / source selection]:
    # The fonts/ folder has been renamed to imports/ and will hold SVG files
    # to be animated. When implementing SVG source selection, resolve this path:
    _AXS_IMPORTS_DIR="$_AXS_ENGINE_DIR/imports"
    # Two source modes planned:
    #   MODE A — pick from imports/: list *.svg files, let user select by number
    #   MODE B — provide absolute path: read -ep "  SVG file path: " AXS_SVG_PATH
    # (A third mode — generate shape from scratch — is also a future option)
    # The selected file will be passed to the Python engine as --input-svg <path>
}

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────

_axs_check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "  ✗ python3 not found — install Python 3.8+ and re-run _configure/install.sh"
        return 1
    fi
}

_axs_check_engine() {
    if [[ ! -f "$_AXS_ENGINE" ]]; then
        echo "  ✗ Python engine not found at $_AXS_ENGINE"
        echo "    Expected: animate-svg/python/svg_typing_effect.py"
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
    print("  (invalid hex — skipping preview)"); sys.exit(0)
print(f"  #{h.upper()}  \033[48;2;{r};{g};{b}m          \033[0m")
PY
}

_axs_bump_version() {
    local ver="$1"
    [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && return 0
    local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
    echo "    1)  patch  →  $major.$minor.$((patch + 1))"
    echo "    2)  minor  →  $major.$((minor + 1)).0"
    echo "    3)  major  →  $((major + 1)).0.0"
    echo "    4)  keep   →  $ver"
    read -rp "    Select [1-4] (default 1): " sel; sel="${sel:-1}"
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
    echo "  ─────────────────────────────────────────────────────────"
    echo "  animatex-svg — animated SVG / HTML generator"
    echo "  ─────────────────────────────────────────────────────────"
    echo ""

    # ── Project meta ──────────────────────────────────────────────────────────
    read -ep "  Project name: " PROJECT;  PROJECT="${PROJECT:-project}"
    echo ""

    read -ep "  Version [$_AXS_DEFAULT_VERSION]: " VERSION
    VERSION="${VERSION:-$_AXS_DEFAULT_VERSION}"

    read -rp "  Bump version? (y/N): " _b
    if [[ "$_b" =~ ^[Yy]$ ]]; then
        echo ""
        _axs_bump_version "$VERSION"
        echo "  → $VERSION"
    fi
    echo ""

    # ── Text content ──────────────────────────────────────────────────────────
    echo "  Enter sentences — one per line, blank line to finish:"
    _LINES=()
    while IFS= read -r _l; do
        [[ -z "$_l" ]] && break
        _LINES+=("$_l")
    done
    if [[ ${#_LINES[@]} -eq 0 ]]; then
        _LINES=("Hello world" "Animated SVG text")
        echo "  (no input — using sample text)"
    fi
    TEXT="$(IFS='|'; echo "${_LINES[*]}")"
    echo ""

    # ── Brand & gradient ──────────────────────────────────────────────────────
    read -ep "  Brand color (hex) [$_AXS_DEFAULT_BRAND]: " BRAND
    BRAND="${BRAND:-$_AXS_DEFAULT_BRAND}"
    _axs_preview_hex "$BRAND"
    echo ""

    # ── Typography (CSS names — not file paths) ───────────────────────────────
    read -ep "  Font family [$_AXS_DEFAULT_FONT_FAMILY]: " FONT_FAMILY
    FONT_FAMILY="${FONT_FAMILY:-$_AXS_DEFAULT_FONT_FAMILY}"

    read -ep "  Font weight [$_AXS_DEFAULT_FONT_WEIGHT]: " FONT_WEIGHT
    FONT_WEIGHT="${FONT_WEIGHT:-$_AXS_DEFAULT_FONT_WEIGHT}"

    read -ep "  Font size   [$_AXS_DEFAULT_FONT_SIZE]: " FONT_SIZE
    FONT_SIZE="${FONT_SIZE:-$_AXS_DEFAULT_FONT_SIZE}"
    echo ""

    # ── ViewBox ───────────────────────────────────────────────────────────────
    read -ep "  ViewBox width  [$_AXS_DEFAULT_VIEWBOX_WIDTH]: "  VB_W
    VB_W="${VB_W:-$_AXS_DEFAULT_VIEWBOX_WIDTH}"

    read -ep "  ViewBox height [$_AXS_DEFAULT_VIEWBOX_HEIGHT]: " VB_H
    VB_H="${VB_H:-$_AXS_DEFAULT_VIEWBOX_HEIGHT}"
    echo ""

    # ── Animation timing ──────────────────────────────────────────────────────
    read -ep "  Char delay    [$_AXS_DEFAULT_CHAR_DELAY s]: " CHAR_DELAY
    CHAR_DELAY="${CHAR_DELAY:-$_AXS_DEFAULT_CHAR_DELAY}"

    read -ep "  Pause after   [$_AXS_DEFAULT_PAUSE_DURATION s]: " PAUSE
    PAUSE="${PAUSE:-$_AXS_DEFAULT_PAUSE_DURATION}"

    read -ep "  Cursor        [$_AXS_DEFAULT_CURSOR]: " CURSOR
    CURSOR="${CURSOR:-$_AXS_DEFAULT_CURSOR}"
    echo ""

    # ── Output format ─────────────────────────────────────────────────────────
    echo "  Output format:"
    echo "    1)  html  —  standalone file, JS state machine, multi-line loop"
    echo "    2)  svg   —  embeddable, pure CSS, single-line only"
    echo ""
    read -ep "  Select [1]: " _fmt; _fmt="${_fmt:-1}"
    FORMAT="$_AXS_DEFAULT_FORMAT"
    [[ "$_fmt" == "2" || "$_fmt" == "svg" ]] && FORMAT="svg"
    echo ""

    # ── Summary ───────────────────────────────────────────────────────────────
    local DATE; DATE="$(date +%Y%m%d)"
    local EXT="$FORMAT"
    local OUTFILE="${DATE}_asset_animated_svg_${PROJECT}_v${VERSION}.${EXT}"

    echo "  ─────────────────────────────────────────────────────────"
    echo "  Project  :  $PROJECT  v$VERSION  ($DATE)"
    echo "  Text     :  $TEXT"
    echo "  Brand    :  $BRAND"
    echo "  Font     :  $FONT_FAMILY  $FONT_WEIGHT  $FONT_SIZE"
    echo "  ViewBox  :  ${VB_W}×${VB_H}"
    echo "  Timing   :  ${CHAR_DELAY}s/char  ·  pause ${PAUSE}s  ·  cursor ${CURSOR}"
    echo "  Format   :  $FORMAT"
    echo "  Output   :  $_AXS_EXPORTS_DIR/$OUTFILE"
    echo "  ─────────────────────────────────────────────────────────"
    echo ""

    read -rp "  Generate? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  Cancelled."
        return 0
    fi

    echo ""
    _axs_run_engine \
        --text "$TEXT" --brand "$BRAND" \
        --font-family "$FONT_FAMILY" --font-weight "$FONT_WEIGHT" \
        --font-size "$FONT_SIZE" \
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

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        animatex_svg_help; return 0
    fi

    _axs_run_engine "$@"
}

animatex_svg_help() {
    cat <<'HELP'

  animatex-svg — animated typing SVG/HTML with gradient text

  USAGE
    animatex-svg                         interactive (prompts for everything)
    animatex-svg --interactive / -i      same
    animatex-svg [options]               direct / scriptable

  OPTIONS
    --text           "Line 1|Line 2"   pipe-separated sentences
    --brand          "#00CC66"         primary brand hex
    --gradient1      "#00C800"         gradient start (overrides --brand)
    --gradient2      "#B4FF00"         gradient end   (overrides --brand)
    --font-family    Poppins           CSS font-family name
    --font-weight    700               CSS font-weight
    --font-size      64px              CSS font-size (include unit)
    --viewbox-width  1200              SVG viewBox width
    --viewbox-height 200               SVG viewBox height
    --char-delay     0.05              seconds between characters appearing
    --pause          2.0               seconds to hold after line completes
    --fade           0.3               fade in/out transition duration
    --cursor         true              blinking cursor (true/false)
    --cursor-char    |                 cursor character
    --cursor-blink   0.8               blink period in seconds
    --format         html              html (JS, multi-line) | svg (CSS, single-line)
    --project        project           output filename slug
    --version        0.0.0             semver string
    --date           YYYYMMDD          date prefix (default: today)

  OUTPUT FORMAT COMPARISON
    html    standalone .html file, JS state machine, multi-line loop, cursor blink
    svg     embeddable .svg, pure CSS @keyframes, single-line only, no JS

  OUTPUT
    animate-svg/exports/YYYYMMDD_asset_animated_svg_{project}_v{version}.{ext}

  NOTE — SVG source file support (coming soon):
    animate-svg/imports/ will hold SVG files to be animated.
    Two planned source modes:
      A)  select from imports/   (pick from files already in the folder)
      B)  provide a file path    (point to any SVG on the filesystem)

HELP
}