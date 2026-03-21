#!/usr/bin/env bash
# _run/20260309_run_typing_effect_v0.1.0.sh
#
# Interactive wrapper for gradient_typing_effect.py.
# Prompts for all generation parameters, shows a summary, then hands off
# to the Python engine.

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.1.0 — Refactor: all tunables moved to CONFIG block; output dir updated
#             to 'exports'; file-path comment added to line 1; PYTHON_SCRIPT
#             reference updated to v0.1.0; comments rewritten to explain why;
#             paths consistently derived from config vars.
#   v0.0.0 — Initial release. Interactive prompt wrapper with version bump
#             helper and terminal color preview.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — change values here, not scattered across the script
# ─────────────────────────────────────────────────────────────────────────────
# Paths are all relative to ROOT_DIR so you can move the project and only
# update these two lines.

# ── Project layout ────────────────────────────────────────────────────────────
PYTHON_SCRIPT_NAME="20260309_gradient_typing_effect_v0.1.0.py"
PYTHON_SUBDIR="_run/../python"   # resolve to python/ from _run/
OUTPUT_SUBDIR="exports"          # renamed from generated-assets
FONTS_SUBDIR="fonts"

# ── Prompt defaults ───────────────────────────────────────────────────────────
DEFAULT_VERSION="1.0.0"
DEFAULT_BRAND="#00CC66"
DEFAULT_ALIGN="center"
DEFAULT_WIDTH=1200
DEFAULT_HEIGHT=200
DEFAULT_FONTSIZE=64

# ─────────────────────────────────────────────────────────────────────────────
# PATHS — derived from config, not hardcoded
# ─────────────────────────────────────────────────────────────────────────────
# _run/ sits one level below the project root, same as python/, fonts/, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

PYTHON_SCRIPT="$ROOT_DIR/python/$PYTHON_SCRIPT_NAME"
FONTS_DIR="$ROOT_DIR/$FONTS_SUBDIR"
OUTPUT_DIR="$ROOT_DIR/$OUTPUT_SUBDIR"

mkdir -p "$OUTPUT_DIR"


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# bump_version: mutates global VERSION rather than using command substitution —
# avoids subshell scoping issues that silently discard the updated value.
bump_version() {
    local ver="$1"

    if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "Version '$ver' isn't semver — keeping it unchanged."
        return 0
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"

    echo "Choose a bump:"
    echo "  1) patch  →  $major.$minor.$((patch + 1))   small fixes"
    echo "  2) minor  →  $major.$((minor + 1)).0        new features (backwards compat)"
    echo "  3) major  →  $((major + 1)).0.0             breaking changes"
    echo "  4) keep   →  $ver"

    read -rp "Select [1-4 | p/m/M/k] (default: 1 — patch): " sel
    sel="${sel:-1}"

    case "$sel" in
        1|p|P|patch)  VERSION="$major.$minor.$((patch + 1))" ;;
        2|m|minor)    VERSION="$major.$((minor + 1)).0"      ;;
        3|M|major)    VERSION="$((major + 1)).0.0"           ;;
        4|k|keep)     VERSION="$ver"                         ;;
        *)
            # Still try to handle a stray numeric input rather than bailing out
            if [[ "$sel" =~ ^[1-4]$ ]]; then
                case "$sel" in
                    1) VERSION="$major.$minor.$((patch + 1))" ;;
                    2) VERSION="$major.$((minor + 1)).0"      ;;
                    3) VERSION="$((major + 1)).0.0"           ;;
                    4) VERSION="$ver"                         ;;
                esac
            else
                echo "Didn't recognise '$sel' — keeping: $ver"
                VERSION="$ver"
            fi
            ;;
    esac
}

# Print a small ANSI color swatch for a hex string — handy sanity check
# before committing to a 24fps render.
preview_hex() {
    local hex_in
    hex_in="${1#\#}"   # strip leading # if present
    python3 - "$hex_in" <<'PY'
import sys
h = sys.argv[1]
try:
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
except Exception:
    print("(invalid hex — skipping preview)")
    sys.exit(0)
print(f"  #{h.upper()}  \033[48;2;{r};{g};{b}m        \033[0m")
PY
}


# ─────────────────────────────────────────────────────────────────────────────
# PROMPTS
# ─────────────────────────────────────────────────────────────────────────────

read -ep "Project name: " PROJECT
PROJECT="${PROJECT:-project}"

read -ep "Version (semver) [$DEFAULT_VERSION]: " VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"

read -rp "Bump the version? (y/N): " bumpyn
if [[ "$bumpyn" =~ ^[Yy]$ ]]; then
    bump_version "$VERSION"
    echo "→ $VERSION"
fi

# Collect lines — blank line ends input
echo ""
echo "Enter sentences (blank line to finish):"
LINES=()
while IFS= read -r LINE; do
    [[ -z "$LINE" ]] && break
    LINES+=("$LINE")
done
if [[ ${#LINES[@]} -eq 0 ]]; then
    echo "No lines entered — using built-in sample."
    LINES=("Hello world" "Animated gradient text")
fi
# Pipe-delimited: the Python side splits on | to recover individual lines
TEXT="$(IFS='|'; echo "${LINES[*]}")"

read -ep "Primary brand color (hex) [$DEFAULT_BRAND]: " BRAND
BRAND="${BRAND:-$DEFAULT_BRAND}"
echo "Color preview:"
preview_hex "$BRAND"

read -ep "Alignment (left/center/right) [$DEFAULT_ALIGN]: " ALIGN
ALIGN="${ALIGN:-$DEFAULT_ALIGN}"

read -ep "Width  [$DEFAULT_WIDTH]: "  WIDTH;  WIDTH="${WIDTH:-$DEFAULT_WIDTH}"
read -ep "Height [$DEFAULT_HEIGHT]: " HEIGHT; HEIGHT="${HEIGHT:-$DEFAULT_HEIGHT}"

# Font selection — enumerate what's actually in the fonts dir
echo ""
echo "Fonts available in $FONTS_DIR:"
mapfile -t FONTFILES < <(
    find "$FONTS_DIR" -maxdepth 1 -type f \( -iname "*.ttf" -o -iname "*.otf" \) \
        -printf '%f\n' 2>/dev/null | sort
)

FONTFILE=""
if [[ ${#FONTFILES[@]} -gt 0 ]]; then
    for i in "${!FONTFILES[@]}"; do
        printf "  %3d) %s\n" $((i + 1)) "${FONTFILES[$i]}"
    done
    read -rp "Select font by number or filename [${FONTFILES[0]}]: " FONTSEL
    if [[ -z "$FONTSEL" ]]; then
        FONTFILE="${FONTFILES[0]}"
    elif [[ "$FONTSEL" =~ ^[0-9]+$ ]] && (( FONTSEL >= 1 && FONTSEL <= ${#FONTFILES[@]} )); then
        FONTFILE="${FONTFILES[$((FONTSEL - 1))]}"
    else
        FONTFILE="$FONTSEL"
    fi
else
    read -rp "No fonts found in $FONTS_DIR — enter a system font path: " FONTFILE
fi

read -ep "Font size [$DEFAULT_FONTSIZE]: " FONTSIZE
FONTSIZE="${FONTSIZE:-$DEFAULT_FONTSIZE}"


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY + CONFIRM
# ─────────────────────────────────────────────────────────────────────────────

DATE="$(date +%Y%m%d)"
OUTFILE="${DATE}_asset_animated_text_${PROJECT}_v${VERSION}.gif"

echo ""
echo "─────────────────────────────────"
echo "  Project : $PROJECT"
echo "  Version : $VERSION"
echo "  Date    : $DATE"
echo "  Text    : $TEXT"
echo "  Brand   : $BRAND  (engine derives gradient start automatically)"
echo "  Align   : $ALIGN"
echo "  Canvas  : ${WIDTH}×${HEIGHT}"
echo "  Font    : $FONTFILE @ ${FONTSIZE}px"
echo "  Output  : $OUTPUT_DIR/$OUTFILE"
echo "─────────────────────────────────"

read -rp "Generate GIF? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi


# ─────────────────────────────────────────────────────────────────────────────
# GENERATE
# ─────────────────────────────────────────────────────────────────────────────

python3 "$PYTHON_SCRIPT" \
    --text      "$TEXT"     \
    --brand     "$BRAND"    \
    --align     "$ALIGN"    \
    --width     "$WIDTH"    \
    --height    "$HEIGHT"   \
    --font      "$FONTFILE" \
    --fontsize  "$FONTSIZE" \
    --project   "$PROJECT"  \
    --version   "$VERSION"  \
    --date      "$DATE"

echo ""
echo "Done. Assets are in: $OUTPUT_DIR"