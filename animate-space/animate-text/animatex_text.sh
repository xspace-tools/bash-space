#!/usr/bin/env bash
# animate-space/animate-text/animatex_text.sh
#
# Engine library for animated GIF generation.
# Sourced by animate-space/lib/animatex.sh (auto-discovered) and by
# animate-space/bin/animatex-text (direct shortcut).

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.4.0 — Added _ANIMATEX_TEXT_ORDER=10 so this engine sorts before SVG
#             in the menu (alphabetically svg < text, so without ORDER the
#             SVG engine was appearing first). No logic changes.
#   v0.3.0 — Moved into animate-text/. Added LABEL + DESC metadata.
#   v0.2.0 — Moved from x-space/lib/.
#   v0.1.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_TEXT_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_TEXT_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# ENGINE METADATA
# ─────────────────────────────────────────────────────────────────────────────

_ANIMATEX_TEXT_LABEL="Gradient typing GIF"
_ANIMATEX_TEXT_DESC="Animated .gif — pixel-perfect, plays anywhere (email, Slack, GitHub)"
_ANIMATEX_TEXT_ORDER=10   # lower = higher in menu

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
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

_axt_resolve_paths() {
    _AXT_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _AXT_ENGINE="$_AXT_ENGINE_DIR/python/gradient_typing_effect.py"
    _AXT_FONTS_DIR="$_AXT_ENGINE_DIR/fonts"
    _AXT_EXPORTS_DIR="$_AXT_ENGINE_DIR/exports"
}

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────

_axt_check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "  ✗ python3 not found — install Python 3.8+ and re-run _configure/install.sh"
        return 1
    fi
    if ! python3 -c "import PIL" &>/dev/null; then
        echo "  ✗ Pillow not installed"
        echo "    Run: pip install pillow --break-system-packages"
        return 1
    fi
}

_axt_check_engine() {
    if [[ ! -f "$_AXT_ENGINE" ]]; then
        echo "  ✗ Python engine not found at $_AXT_ENGINE"
        echo "    Expected: animate-text/python/gradient_typing_effect.py"
        return 1
    fi
}

_axt_check_fonts() {
    if [[ ! -d "$_AXT_FONTS_DIR" ]] || [[ -z "$(ls -A "$_AXT_FONTS_DIR" 2>/dev/null)" ]]; then
        echo "  ⚠  No fonts in $_AXT_FONTS_DIR"
        echo "     Falling back to PIL's built-in bitmap font."
        echo "     Copy .ttf/.otf files there for custom fonts."
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
    print("  (invalid hex — skipping preview)"); sys.exit(0)
print(f"  #{h.upper()}  \033[48;2;{r};{g};{b}m          \033[0m")
PY
}

_axt_bump_version() {
    local ver="$1"
    [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && return 0
    local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
    echo "    1)  patch  →  $major.$minor.$((patch + 1))   small fix"
    echo "    2)  minor  →  $major.$((minor + 1)).0       new feature"
    echo "    3)  major  →  $((major + 1)).0.0            breaking change"
    echo "    4)  keep   →  $ver"
    read -rp "    Select [1-4] (default 1): " sel; sel="${sel:-1}"
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
        read -rp "  No fonts found — enter system font path: " FONTFILE
        return 0
    fi
    echo ""
    echo "  Available fonts:"
    local i
    for i in "${!_AXT_FONTS[@]}"; do
        printf "    %3d)  %s\n" $((i+1)) "${_AXT_FONTS[$i]}"
    done
    echo ""
    read -rp "  Select font [1 = ${_AXT_FONTS[0]}]: " sel
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
    echo "  ─────────────────────────────────────────────────────────"
    echo "  animatex-text — animated gradient typing GIF"
    echo "  ─────────────────────────────────────────────────────────"
    echo ""

    # ── Project meta ──────────────────────────────────────────────────────────
    read -ep "  Project name: " PROJECT;  PROJECT="${PROJECT:-project}"
    echo ""

    read -ep "  Version [$_AXT_DEFAULT_VERSION]: " VERSION
    VERSION="${VERSION:-$_AXT_DEFAULT_VERSION}"

    read -rp "  Bump version? (y/N): " _b
    if [[ "$_b" =~ ^[Yy]$ ]]; then
        echo ""
        _axt_bump_version "$VERSION"
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
        _LINES=("Hello world" "Animated gradient text")
        echo "  (no input — using sample text)"
    fi
    TEXT="$(IFS='|'; echo "${_LINES[*]}")"
    echo ""

    # ── Brand & gradient ──────────────────────────────────────────────────────
    read -ep "  Brand color (hex) [$_AXT_DEFAULT_BRAND]: " BRAND
    BRAND="${BRAND:-$_AXT_DEFAULT_BRAND}"
    _axt_preview_hex "$BRAND"
    echo ""

    # ── Layout ────────────────────────────────────────────────────────────────
    read -ep "  Alignment (left/center/right) [$_AXT_DEFAULT_ALIGN]: " ALIGN
    ALIGN="${ALIGN:-$_AXT_DEFAULT_ALIGN}"

    read -ep "  Canvas width  [$_AXT_DEFAULT_WIDTH px]: "  WIDTH
    WIDTH="${WIDTH:-$_AXT_DEFAULT_WIDTH}"

    read -ep "  Canvas height [$_AXT_DEFAULT_HEIGHT px]: " HEIGHT
    HEIGHT="${HEIGHT:-$_AXT_DEFAULT_HEIGHT}"
    echo ""

    # ── Font ──────────────────────────────────────────────────────────────────
    _axt_check_fonts
    _axt_pick_font
    echo ""

    read -ep "  Font size [$_AXT_DEFAULT_FONTSIZE px]: " FONTSIZE
    FONTSIZE="${FONTSIZE:-$_AXT_DEFAULT_FONTSIZE}"

    read -ep "  FPS [$_AXT_DEFAULT_FPS]: " FPS
    FPS="${FPS:-$_AXT_DEFAULT_FPS}"
    echo ""

    # ── Summary ───────────────────────────────────────────────────────────────
    local DATE; DATE="$(date +%Y%m%d)"
    local OUTFILE="${DATE}_asset_animated_text_${PROJECT}_v${VERSION}.gif"

    echo "  ─────────────────────────────────────────────────────────"
    echo "  Project  :  $PROJECT  v$VERSION  ($DATE)"
    echo "  Text     :  $TEXT"
    echo "  Brand    :  $BRAND"
    echo "  Canvas   :  ${WIDTH}×${HEIGHT} px  @  ${FPS} fps  ·  $ALIGN"
    echo "  Font     :  $FONTFILE  @  ${FONTSIZE} px"
    echo "  Output   :  $_AXT_EXPORTS_DIR/$OUTFILE"
    echo "  ─────────────────────────────────────────────────────────"
    echo ""

    read -rp "  Generate? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  Cancelled."
        return 0
    fi

    echo ""
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

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        animatex_text_help; return 0
    fi

    _axt_check_fonts
    _axt_run_engine "$@"
}

animatex_text_help() {
    cat <<'HELP'

  animatex-text — animated typing GIF with gradient text

  USAGE
    animatex-text                          interactive (prompts for everything)
    animatex-text --interactive / -i       same
    animatex-text [options]                direct / scriptable (no prompts)

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
    --version    0.0.0              semver string
    --date       YYYYMMDD           date prefix (default: today)

  OUTPUT
    animate-text/exports/YYYYMMDD_asset_animated_text_{project}_v{version}.gif

  EXAMPLES
    animatex-text
    animatex-text --brand "#FF6B00" --text "Launch|Live" --project acme
    animatex-text --font "Barlow-BlackItalic.ttf" --fontsize 96 --brand "#5C3BFF"

HELP
}