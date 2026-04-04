#!/usr/bin/env bash
# animate-space/lib/animatex.sh
#
# Auto-discovering router for the animatex command suite.
# Sourced by animate-space/bin/animatex — never run directly.
#
# ── Engine convention ─────────────────────────────────────────────────────────
# Each engine lives in animate-space/animate-{type}/animatex_{type}.sh
# and must define:
#
#   _ANIMATEX_{TYPE}_LABEL   "Display name for menu"
#   _ANIMATEX_{TYPE}_DESC    "One-line description shown under the name"
#   _ANIMATEX_{TYPE}_ORDER   10   (lower = higher in menu; default 50)
#
#   animatex_{type}_run()   — interactive or direct generation
#   animatex_{type}_help()  — full option reference
#
# Adding a new engine: create animate-space/animate-shape/animatex_shape.sh
# with the vars and functions above. It appears in the menu automatically
# on the next terminal open — nothing else needs changing.

# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v0.4.0 — Fixed two critical bugs:
#             Bug A: menu display text was going to stdout, captured by the
#               $(...) command substitution in animatex_run, causing the entire
#               menu to be stored in $type. Fix: all display output now goes
#               to stderr (>&2); only the chosen type word goes to stdout.
#             Bug B: find returned animate-svg before animate-text (alpha
#               order), putting SVG first. Fix: _ANIMATEX_{TYPE}_ORDER metadata
#               var controls sort position; text=10, svg=20 by default.
#             UX: menu now shows numbered list with label + description before
#               the prompt, not after. Prompt shows the range clearly.
#   v0.3.0 — Complete rewrite as auto-discovering router.
#   v0.2.0 — Moved from x-space/lib/ to animate-space/lib/.
#   v0.1.0 — Initial router (hardcoded text + svg).
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_ANIMATEX_LIB_LOADED:-}" ]] && return 0
_ANIMATEX_LIB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# ENGINE DISCOVERY
# ─────────────────────────────────────────────────────────────────────────────

_AX_LIB_FILE="${BASH_SOURCE[0]}"
_AX_SPACE_DIR="$(cd "$(dirname "$_AX_LIB_FILE")/.." && pwd)"

# Parallel arrays — one slot per discovered engine
_AX_ENGINE_TYPES=()
_AX_ENGINE_LABELS=()
_AX_ENGINE_DESCS=()
_AX_ENGINE_ORDERS=()

_ax_discover_engines() {
    # Collect all engine lib paths, then sort by ORDER number so the menu
    # respects the engine's preferred position rather than filesystem order.

    local engine_lib type upper_type label_var desc_var order_var
    local -a found_types=() found_libs=() found_orders=()

    while IFS= read -r engine_lib; do
        [[ -f "$engine_lib" ]] || continue

        type="$(basename "$engine_lib" .sh)"   # animatex_text
        type="${type#animatex_}"               # text

        # shellcheck source=/dev/null
        source "$engine_lib"

        upper_type="${type^^}"
        label_var="_ANIMATEX_${upper_type}_LABEL"
        desc_var="_ANIMATEX_${upper_type}_DESC"
        order_var="_ANIMATEX_${upper_type}_ORDER"

        found_types+=("$type")
        found_libs+=("$engine_lib")
        found_orders+=("${!order_var:-50}")

    done < <(find "$_AX_SPACE_DIR" -path "*/animate-*/animatex_*.sh" | sort)

    if [[ ${#found_types[@]} -eq 0 ]]; then
        echo "animatex: no engines found in animate-space/animate-*/" >&2
        echo "          Expected files: animate-*/animatex_*.sh" >&2
        return 1
    fi

    # Sort by ORDER number (simple insertion sort — N is always tiny)
    local n="${#found_types[@]}"
    for (( i=1; i<n; i++ )); do
        local key_type="${found_types[$i]}"
        local key_order="${found_orders[$i]}"
        local j=$(( i - 1 ))
        while (( j >= 0 )) && (( found_orders[j] > key_order )); do
            found_types[$((j+1))]="${found_types[$j]}"
            found_orders[$((j+1))]="${found_orders[$j]}"
            (( j-- ))
        done
        found_types[$((j+1))]="$key_type"
        found_orders[$((j+1))]="$key_order"
    done

    # Populate the final ordered arrays with metadata
    for type in "${found_types[@]}"; do
        upper_type="${type^^}"
        label_var="_ANIMATEX_${upper_type}_LABEL"
        desc_var="_ANIMATEX_${upper_type}_DESC"
        _AX_ENGINE_TYPES+=("$type")
        _AX_ENGINE_LABELS+=("${!label_var:-$type}")
        _AX_ENGINE_DESCS+=("${!desc_var:-}")
    done
}

_ax_discover_engines || return 1

# ─────────────────────────────────────────────────────────────────────────────
# TYPE SELECTION MENU
# ─────────────────────────────────────────────────────────────────────────────
# ⚠ CRITICAL: ALL output here goes to stderr (>&2).
# This function is called as: type="$(_ax_pick_type)"
# Command substitution $(...) captures stdout. If the menu prints to stdout,
# the entire menu text ends up stored in $type instead of the user's choice.
# Only the final "echo $chosen" goes to stdout — that's the return value.

_ax_print_menu() {
    local n="${#_AX_ENGINE_TYPES[@]}"
    echo "" >&2
    echo "  ╭─────────────────────────────────────────────────────────╮" >&2
    echo "  │  animatex — animated asset generator                    │" >&2
    echo "  ╰─────────────────────────────────────────────────────────╯" >&2
    echo "" >&2

    local i
    for (( i=0; i<n; i++ )); do
        printf "  %d)  %s\n" $(( i + 1 )) "${_AX_ENGINE_LABELS[$i]}" >&2
        if [[ -n "${_AX_ENGINE_DESCS[$i]:-}" ]]; then
            printf "       %s\n" "${_AX_ENGINE_DESCS[$i]}" >&2
        fi
        echo "" >&2
    done
}

_ax_pick_type() {
    local n="${#_AX_ENGINE_TYPES[@]}"

    _ax_print_menu

    local _sel chosen=""
    while true; do
        # Prompt goes to stderr too — read -p writes its prompt to stderr by default
        read -rp "  Select [1-${n}]: " _sel >&2

        # Accept a number
        if [[ "$_sel" =~ ^[0-9]+$ ]] && (( _sel >= 1 && _sel <= n )); then
            chosen="${_AX_ENGINE_TYPES[$(( _sel - 1 ))]}"
            break
        fi

        # Accept a type name directly (power-user path)
        local t
        for t in "${_AX_ENGINE_TYPES[@]}"; do
            if [[ "$_sel" == "$t" ]]; then
                chosen="$t"
                break 2
            fi
        done

        # Invalid — re-prompt without reprinting the full menu
        echo "  Please enter a number between 1 and ${n}." >&2
    done

    # stdout only — this is the return value captured by $()
    echo "$chosen"
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

    # No --type → show interactive menu
    if [[ -z "$type" ]]; then
        type="$(_ax_pick_type)"
        # Blank line between menu and the engine's own prompt
        echo "" >&2
    fi

    # Validate
    local found=0 t
    for t in "${_AX_ENGINE_TYPES[@]}"; do
        [[ "$t" == "$type" ]] && found=1 && break
    done

    if (( found == 0 )); then
        echo "animatex: unknown type '${type}'" >&2
        echo "          Available: ${_AX_ENGINE_TYPES[*]}" >&2
        return 1
    fi

    "animatex_${type}_run" "${remaining[@]+"${remaining[@]}"}"
}

animatex_help() {
    local n="${#_AX_ENGINE_TYPES[@]}"

    cat <<'HELP'

  animatex — animated asset generator

  USAGE
    animatex                            interactive menu
    animatex --type <type> [options]    skip menu, go straight to prompt
    animatex --help
    animatex --version

HELP

    echo "  AVAILABLE TYPES"
    echo ""
    local i
    for (( i=0; i<n; i++ )); do
        printf "    %-8s  %s\n" "${_AX_ENGINE_TYPES[$i]}" "${_AX_ENGINE_LABELS[$i]}"
        [[ -n "${_AX_ENGINE_DESCS[$i]:-}" ]] && \
            printf "    %-8s  %s\n" "" "${_AX_ENGINE_DESCS[$i]}"
    done

    cat <<'HELP'

  SHORTCUTS
    animatex-text [options]     direct GIF generation
    animatex-svg  [options]     direct SVG/HTML generation

  EXAMPLES
    animatex
    animatex --type text --brand "#FF6B00" --text "Launch|Live" --project acme
    animatex --type svg  --brand "#5C3BFF" --text "Hello|World" --format html

HELP
}