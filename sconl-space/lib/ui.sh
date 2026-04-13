# sconl-space/lib/ui.sh
# Terminal rendering helpers for sconlx.
# All display output goes to stderr — only return values go to stdout.
# This matters for any function called inside $() subshells.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. ANSI colors, box drawing (╔╠╚), status badges,
#             progress bars, interactive prompts, table alignment helpers.
# ─────────────────────────────────────────────────────────────────────────────

# Double-source guard — safe to source multiple times from different libs
[[ -n "${_UI_LOADED:-}" ]] && return 0
_UI_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

# ── Colors & display ──
_UI_COLOR="${SCONLX_COLOR:-1}"       # set SCONLX_COLOR=0 to disable all ANSI
_UI_BOX_WIDTH=62                      # total box width including borders

# ── Status badges ──
_UI_BADGE_DONE="✓"
_UI_BADGE_TODO="○"
_UI_BADGE_TODAY="⚡"
_UI_BADGE_DEFERRED="↩"
_UI_BADGE_BLOCKED="⊘"
_UI_BADGE_WARN="⚠"
_UI_BADGE_ACTIVE="●"
_UI_BADGE_ARCHIVED="·"
_UI_BADGE_IDEA="💡"
_UI_BADGE_BOOK="📚"
_UI_BADGE_JOURNAL="📖"
_UI_BADGE_INBOX="📥"
_UI_BADGE_GOAL="🎯"
_UI_BADGE_CYCLE="🌀"
_UI_BADGE_SPACE="🗺"
_UI_BADGE_DIA="🔍"

# ─────────────────────────────────────────────────────────────────────────────
# ANSI HELPERS
# Output to stderr always — display, never data.
# ─────────────────────────────────────────────────────────────────────────────

_ui_has_color() { [[ "$_UI_COLOR" == "1" ]] && [[ -t 2 ]]; }

_ui_bold()    { _ui_has_color && printf '\033[1m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_dim()     { _ui_has_color && printf '\033[2m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_italic()  { _ui_has_color && printf '\033[3m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_under()   { _ui_has_color && printf '\033[4m%s\033[0m' "$*" || printf '%s' "$*"; }

# Named colors — used for system theming
_ui_cyan()    { _ui_has_color && printf '\033[36m%s\033[0m' "$*"   || printf '%s' "$*"; }
_ui_green()   { _ui_has_color && printf '\033[32m%s\033[0m' "$*"   || printf '%s' "$*"; }
_ui_magenta() { _ui_has_color && printf '\033[35m%s\033[0m' "$*"   || printf '%s' "$*"; }
_ui_yellow()  { _ui_has_color && printf '\033[33m%s\033[0m' "$*"   || printf '%s' "$*"; }
_ui_red()     { _ui_has_color && printf '\033[31m%s\033[0m' "$*"   || printf '%s' "$*"; }
_ui_blue()    { _ui_has_color && printf '\033[34m%s\033[0m' "$*"   || printf '%s' "$*"; }

# System-color aliases — each system has a color identity
_ui_scope()   { _ui_has_color && printf '\033[36m%s\033[0m' "$*"   || printf '%s' "$*"; }   # cyan
_ui_space()   { _ui_has_color && printf '\033[32m%s\033[0m' "$*"   || printf '%s' "$*"; }   # green
_ui_spark()   { _ui_has_color && printf '\033[35m%s\033[0m' "$*"   || printf '%s' "$*"; }   # magenta

# ─────────────────────────────────────────────────────────────────────────────
# STATUS LINE HELPERS (all to stderr)
# ─────────────────────────────────────────────────────────────────────────────

_ui_ok()    { printf '  %s  %s\n' "$(_ui_green "✓")" "$*" >&2; }
_ui_warn()  { printf '  %s  %s\n' "$(_ui_yellow "⚠")" "$*" >&2; }
_ui_err()   { printf '  %s  %s\n' "$(_ui_red "✗")" "$*" >&2; }
_ui_info()  { printf '  %s  %s\n' "$(_ui_blue "→")" "$*" >&2; }
_ui_cap()   { printf '  %s  %s\n' "$(_ui_green "✓")" "$(_ui_bold "$*")" >&2; }

# Simple divider line
_ui_hr() {
  printf '  %s\n' "$(printf '─%.0s' {1..58})" >&2
}

# Section header — used inside subsystem views
_ui_section() {
  local title="$1"
  printf '\n  %s\n' "$(_ui_bold "$title")" >&2
  printf '  %s\n' "$(printf '─%.0s' {1..${#title}})" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# BOX DRAWING — used for the main dashboard
# Box is _UI_BOX_WIDTH chars wide, with ║ borders.
# ─────────────────────────────────────────────────────────────────────────────

_ui_box_top() {
  local fill; fill="$(printf '═%.0s' $(seq 1 $(( _UI_BOX_WIDTH - 2 ))))"
  printf '  ╔%s╗\n' "$fill" >&2
}

_ui_box_mid() {
  local fill; fill="$(printf '═%.0s' $(seq 1 $(( _UI_BOX_WIDTH - 2 ))))"
  printf '  ╠%s╣\n' "$fill" >&2
}

_ui_box_bot() {
  local fill; fill="$(printf '═%.0s' $(seq 1 $(( _UI_BOX_WIDTH - 2 ))))"
  printf '  ╚%s╝\n' "$fill" >&2
}

# Print a line inside the box. Content is padded to fit between ║ borders.
# Usage: _ui_box_line "content" [indent_spaces]
_ui_box_line() {
  local content="${1:-}" indent="${2:-1}"
  local prefix; prefix="$(printf ' %.0s' $(seq 1 "$indent"))"
  # Strip ANSI escapes to calculate visible length
  local visible; visible="$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')"
  local inner_width=$(( _UI_BOX_WIDTH - 2 ))
  local pad=$(( inner_width - ${#prefix} - ${#visible} - 1 ))
  [[ $pad -lt 0 ]] && pad=0
  local spaces; spaces="$(printf ' %.0s' $(seq 1 "$pad"))"
  printf '  ║%s%s%s ║\n' "$prefix" "$content" "$spaces" >&2
}

# Empty box line — blank row inside the box
_ui_box_empty() {
  local inner_width=$(( _UI_BOX_WIDTH - 2 ))
  local spaces; spaces="$(printf ' %.0s' $(seq 1 "$inner_width"))"
  printf '  ║%s║\n' "$spaces" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS BAR (text only, for terminal)
# ─────────────────────────────────────────────────────────────────────────────

# Returns a filled progress bar string, e.g. "████░░░░░░ 40%"
# Usage: _ui_progress_bar current total [width]
_ui_progress_bar() {
  local current="$1" total="$2" width="${3:-16}"
  local filled=0 pct=0
  if [[ $total -gt 0 ]]; then
    filled=$(( current * width / total ))
    pct=$(( current * 100 / total ))
  fi
  local bar=""
  local i
  for (( i=0; i<width; i++ )); do
    if [[ $i -lt $filled ]]; then
      bar="${bar}█"
    else
      bar="${bar}░"
    fi
  done
  printf '%s %d%%' "$bar" "$pct"
}

# ─────────────────────────────────────────────────────────────────────────────
# STATUS BADGE
# ─────────────────────────────────────────────────────────────────────────────

_ui_status_badge() {
  case "${1:-}" in
    done|complete|synthesised)   printf '%s' "$(_ui_green   "$_UI_BADGE_DONE")" ;;
    today|active|doing)          printf '%s' "$(_ui_cyan    "$_UI_BADGE_TODAY")" ;;
    deferred)                    printf '%s' "$(_ui_yellow  "$_UI_BADGE_DEFERRED")" ;;
    blocked)                     printf '%s' "$(_ui_red     "$_UI_BADGE_BLOCKED")" ;;
    archived)                    printf '%s' "$(_ui_dim     "$_UI_BADGE_ARCHIVED")" ;;
    *)                           printf '%s' "$_UI_BADGE_TODO" ;;
  esac
}

# Compact health indicator: ●●●●●●●○○○ (for portfolio view)
_ui_health_dots() {
  local score="${1:-0}" max="${2:-10}" width="${3:-10}"
  # Strip any decimal part — bash arithmetic can't handle floats
  local score_int; score_int="${score%%.*}"
  score_int="${score_int:-0}"
  local filled=$(( score_int * width / max ))
  local dots="" i
  for (( i=0; i<width; i++ )); do
    if [[ $i -lt $filled ]]; then
      dots="${dots}$(_ui_green "●")"
    else
      dots="${dots}$(_ui_dim "○")"
    fi
  done
  printf '%s' "$dots"
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE PROMPTS
# These print prompts to stderr and return the user's input via stdout.
# ─────────────────────────────────────────────────────────────────────────────

# Simple text prompt. Returns user input (or default) via stdout.
# Usage: result="$(_ui_prompt "Question" "default")"
_ui_prompt() {
  local label="$1" default="${2:-}" required="${3:-}"
  local display_default=""
  [[ -n "$default" ]] && display_default=" $(_ui_dim "[${default}]")"
  printf '  %s%s: ' "$label" "$display_default" >&2
  local result
  IFS= read -r result
  # Use default if user just hit Enter
  [[ -z "$result" && -n "$default" ]] && result="$default"
  printf '%s' "$result"
}

# Yes/no prompt. Returns 0 for yes, 1 for no.
# Usage: _ui_confirm "Are you sure?" && do_thing
_ui_confirm() {
  local label="${1:-Are you sure?}" default="${2:-n}"
  local opts="[y/N]"
  [[ "$default" == "y" ]] && opts="[Y/n]"
  printf '  %s %s: ' "$label" "$(_ui_dim "$opts")" >&2
  local answer
  IFS= read -r answer
  [[ -z "$answer" ]] && answer="$default"
  [[ "${answer,,}" == "y" ]]
}

# Multi-choice menu. Prints numbered options; returns chosen value via stdout.
# Usage: result="$(_ui_menu "Choose type" "business" "platform" "project")"
_ui_menu() {
  local prompt="$1"; shift
  local options=("$@")
  printf '\n  %s\n' "$(_ui_bold "$prompt")" >&2
  local i
  for (( i=0; i<${#options[@]}; i++ )); do
    printf '  %s  %s\n' "$(_ui_dim "[$((i+1))]")" "${options[$i]}" >&2
  done
  printf '\n  Choice: ' >&2
  local choice
  IFS= read -r choice
  # Validate
  if [[ "$choice" =~ ^[0-9]+$ ]] && \
     [[ "$choice" -ge 1 ]] && \
     [[ "$choice" -le "${#options[@]}" ]]; then
    printf '%s' "${options[$(( choice - 1 ))]}"
  else
    printf '%s' "${options[0]}"
  fi
}

# Press Enter to continue
_ui_pause() {
  local msg="${1:-Press Enter to continue}"
  printf '\n  %s ' "$(_ui_dim "$msg")" >&2
  IFS= read -r _
}

# ─────────────────────────────────────────────────────────────────────────────
# SPACING & LAYOUT
# ─────────────────────────────────────────────────────────────────────────────

# Truncate a string to max width, adding "…" if cut
_ui_truncate() {
  local str="$1" max="${2:-40}"
  if [[ ${#str} -gt $max ]]; then
    printf '%s…' "${str:0:$(( max - 1 ))}"
  else
    printf '%s' "$str"
  fi
}

# Pad a string to exactly N chars (space-padded on right)
_ui_pad() {
  local str="$1" width="$2"
  printf '%-*s' "$width" "$str"
}

# ─────────────────────────────────────────────────────────────────────────────
# DAYS AGO HELPER
# ─────────────────────────────────────────────────────────────────────────────

# Returns a human-readable time-ago string from a YYYY-MM-DD date
_ui_days_ago() {
  local target_date="$1"
  [[ -z "$target_date" || "$target_date" == "-" ]] && printf 'never' && return 0
  local today; today="$(date +%Y-%m-%d)"
  # Use python3 for reliable cross-platform date diff
  python3 -c "
from datetime import date
try:
    d = date.fromisoformat('${target_date}')
    t = date.fromisoformat('${today}')
    diff = (t - d).days
    if diff == 0:    print('today')
    elif diff == 1:  print('yesterday')
    elif diff < 7:   print(f'{diff}d ago')
    elif diff < 30:  print(f'{diff//7}w ago')
    elif diff < 365: print(f'{diff//30}mo ago')
    else:            print(f'{diff//365}y ago')
except: print('${target_date}')
" 2>/dev/null || printf '%s' "$target_date"
}