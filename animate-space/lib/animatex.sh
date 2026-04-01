#!/usr/bin/env bash
# animate-space/lib/animatex.sh
#
# Router library for the animatex command.
# Sourced by animate-space/bin/animatex — never run directly.
#
# This file's only job:
#   1. Source animatex_text.sh and animatex_svg.sh from same lib/ dir
#   2. Ask the user what they want to generate (or read --type from args)
#   3. Delegate to the right library's run function

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.2.0 — Moved from x-space/lib/ to animate-space/lib/. BASH_SOURCE[0]
#             now resolves to animate-space/lib/ — no other logic change.
#   v0.1.0 — Initial router. Sources both sub-libs; type-selection menu.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# SOURCE SUB-LIBRARIES
# ─────────────────────────────────────────────────────────────────────────────
# Both libs live in the same dir as this file (animate-space/lib/).
# Sourcing both upfront means animatex_text_run and animatex_svg_run are
# available before the user selects a type — double-source guards are cheap.

_AX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AX_TEXT_LIB="$_AX_LIB_DIR/animatex_text.sh"
_AX_SVG_LIB="$_AX_LIB_DIR/animatex_svg.sh"

if [[ ! -f "$_AX_TEXT_LIB" ]]; then
    echo "animatex: animate-space/lib/animatex_text.sh not found"
    echo "          Re-run x-space/install.sh"
    return 1
fi
if [[ ! -f "$_AX_SVG_LIB" ]]; then
    echo "animatex: animate-space/lib/animatex_svg.sh not found"
    echo "          Re-run x-space/install.sh"
    return 1
fi

# shellcheck source=./animatex_text.sh
source "$_AX_TEXT_LIB"
# shellcheck source=./animatex_svg.sh
source "$_AX_SVG_LIB"

# ─────────────────────────────────────────────────────────────────────────────
# TYPE SELECTION MENU
# ─────────────────────────────────────────────────────────────────────────────

_ax_pick_type() {
    echo ""
    echo "  animatex — what would you like to generate?"
    echo ""
    echo "    1)  Gradient typing GIF"
    echo "        Animated .gif — raster, pixel-perfect, plays anywhere"
    echo "        Output: animate-text/exports/"
    echo ""
    echo "    2)  SVG / HTML animation"
    echo "        Animated .svg or .html — scalable, no Pillow needed,"
    echo "        transparent background, embeds in any webpage"
    echo "        Output: animate-svg/exports/"
    echo ""
    read -rp "  Select [1/2]: " _sel

    case "${_sel:-}" in
        1|t|text|gif)  echo "text" ;;
        2|s|svg|html)  echo "svg"  ;;
        *)
            echo "  Please enter 1 (GIF) or 2 (SVG/HTML)." >&2
            _ax_pick_type
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

animatex_run() {
    local type=""
    local remaining=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)   type="$2"; shift 2 ;;
            --type=*) type="${1#--type=}"; shift ;;
            *)        remaining+=("$1"); shift ;;
        esac
    done

    if [[ -z "$type" ]]; then
        type="$(_ax_pick_type)"
    fi

    case "$type" in
        text|gif|1) animatex_text_run "${remaining[@]+"${remaining[@]}"}" ;;
        svg|html|2) animatex_svg_run  "${remaining[@]+"${remaining[@]}"}" ;;
        *)
            echo "animatex: unknown type '${type}'. Use: --type text  or  --type svg"
            return 1
            ;;
    esac
}

animatex_help() {
    cat <<'HELP'

  animatex — animated asset generator

  USAGE
    animatex                            interactive — prompts for type then options
    animatex --type text [options]      skip menu, go straight to GIF prompt
    animatex --type svg  [options]      skip menu, go straight to SVG prompt
    animatex --help
    animatex --version

  TYPES
    text / gif    Animated typing GIF with gradient text (requires Pillow)
                  Output: animate-space/animate-text/exports/*.gif

    svg / html    Animated typing SVG or HTML (stdlib only — no Pillow needed)
                  Output: animate-space/animate-svg/exports/*.svg or *.html

  SHORTCUTS (bypass the type menu)
    animatex-text [options]
    animatex-svg  [options]

  EXAMPLES
    animatex --type text --brand "#FF6B00" --text "Launch|Live" --project acme
    animatex --type svg  --brand "#5C3BFF" --text "Hello|World" --format html

  Full option lists:
    animatex-text --help
    animatex-svg  --help

HELP
}