# sconl-space/lib/ui.sh
# Terminal rendering helpers for sconlx.
# Design: no emojis, clear visual hierarchy, system color themes.
# All display output → stderr. Only return values → stdout.
#
# Color themes (pick these up everywhere):
#   Scope  → cyan    (36m)   the daily rhythm
#   Space  → green   (32m)   the domain portfolio
#   Spark  → magenta (35m)   the inner world
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v2.0.0 — Complete redesign. No emojis, clean text hierarchy, thin-line
#             boxes, system color theming, _ui_action_menu with [q] quit,
#             _ui_prompt with quit detection via exit code, progress bars,
#             row/label display helpers.
#   v1.0.0 — Initial. ANSI, box drawing, emoji badges, prompts.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_UI_LOADED:-}" ]] && return 0
_UI_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_UI_COLOR="${SCONLX_COLOR:-1}"
_UI_WIDTH=60
_UI_INDENT="  "

# Text markers — no emojis
_UI_MARK_OK="✓"
_UI_MARK_WARN="!"
_UI_MARK_ERR="✗"
_UI_MARK_INFO="→"
_UI_MARK_DONE="[x]"
_UI_MARK_TODO="[ ]"
_UI_MARK_TODAY="[>]"
_UI_MARK_DEFERRED="[~]"
_UI_MARK_BLOCKED="[!]"
_UI_MARK_ACTIVE="[*]"
_UI_MARK_BULLET=" · "

# ─────────────────────────────────────────────────────────────────────────────
# ANSI COLOR HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_ui_has_color() { [[ "$_UI_COLOR" == "1" ]] && [[ -t 2 ]]; }

_ui_bold()    { _ui_has_color && printf '\033[1m%s\033[0m' "$*"  || printf '%s' "$*"; }
_ui_dim()     { _ui_has_color && printf '\033[2m%s\033[0m' "$*"  || printf '%s' "$*"; }
_ui_italic()  { _ui_has_color && printf '\033[3m%s\033[0m' "$*"  || printf '%s' "$*"; }
_ui_under()   { _ui_has_color && printf '\033[4m%s\033[0m' "$*"  || printf '%s' "$*"; }

# System identity colors — always use these, not raw colors, for system names
_ui_scope()   { _ui_has_color && printf '\033[36m%s\033[0m' "$*" || printf '%s' "$*"; }  # cyan
_ui_space()   { _ui_has_color && printf '\033[32m%s\033[0m' "$*" || printf '%s' "$*"; }  # green
_ui_spark()   { _ui_has_color && printf '\033[35m%s\033[0m' "$*" || printf '%s' "$*"; }  # magenta

# Utility colors
_ui_green()   { _ui_has_color && printf '\033[32m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_yellow()  { _ui_has_color && printf '\033[33m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_red()     { _ui_has_color && printf '\033[31m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_cyan()    { _ui_has_color && printf '\033[36m%s\033[0m' "$*" || printf '%s' "$*"; }
_ui_magenta() { _ui_has_color && printf '\033[35m%s\033[0m' "$*" || printf '%s' "$*"; }

# ─────────────────────────────────────────────────────────────────────────────
# STATUS LINES (all → stderr)
# ─────────────────────────────────────────────────────────────────────────────

_ui_ok()   { printf '%s%s  %s\n' "$_UI_INDENT" "$(_ui_green  "$_UI_MARK_OK")"   "$*"              >&2; }
_ui_warn() { printf '%s%s  %s\n' "$_UI_INDENT" "$(_ui_yellow "$_UI_MARK_WARN")" "$(_ui_yellow "$*")" >&2; }
_ui_err()  { printf '%s%s  %s\n' "$_UI_INDENT" "$(_ui_red    "$_UI_MARK_ERR")"  "$(_ui_red "$*")"  >&2; }
_ui_info() { printf '%s%s  %s\n' "$_UI_INDENT" "$(_ui_dim    "$_UI_MARK_INFO")" "$*"              >&2; }
_ui_cap()  { printf '%s%s  %s\n' "$_UI_INDENT" "$(_ui_green  "$_UI_MARK_OK")"   "$(_ui_bold "$*")" >&2; }
_ui_hint() { printf '%s    %s\n' "$_UI_INDENT" "$(_ui_dim "$*")"                                  >&2; }
_ui_blank() { printf '\n' >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# HORIZONTAL RULES
# ─────────────────────────────────────────────────────────────────────────────

_ui_hr() {
  local w="${1:-$_UI_WIDTH}"
  printf '%s%s\n' "$_UI_INDENT" "$(printf '─%.0s' $(seq 1 "$w"))" >&2
}

_ui_divider() {
  local w="${1:-38}"
  printf '%s  %s\n' "$_UI_INDENT" "$(_ui_dim "$(printf '╌%.0s' $(seq 1 "$w"))")" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION HEADERS
# ─────────────────────────────────────────────────────────────────────────────

# Top-level system section: colored bold name + horizontal rule
_ui_section_scope() { _ui_section_colored "_ui_scope"   "$@"; }
_ui_section_space() { _ui_section_colored "_ui_space"   "$@"; }
_ui_section_spark() { _ui_section_colored "_ui_spark"   "$@"; }

_ui_section_colored() {
  local cfn="$1" title="$2" sub="${3:-}"
  _ui_blank
  local t; t="$("$cfn" "$(_ui_bold "$title")")"
  printf '%s%s' "$_UI_INDENT" "$t" >&2
  [[ -n "$sub" ]] && printf '  %s' "$(_ui_dim "$sub")" >&2
  printf '\n' >&2
  _ui_hr
}

# Plain section (no system color)
_ui_section() {
  local title="$1" sub="${2:-}"
  _ui_blank
  printf '%s%s' "$_UI_INDENT" "$(_ui_bold "$title")" >&2
  [[ -n "$sub" ]] && printf '  %s' "$(_ui_dim "$sub")" >&2
  printf '\n' >&2
  _ui_hr
}

# Sub-section within a section
_ui_subsection() {
  printf '\n%s  %s\n' "$_UI_INDENT" "$(_ui_bold "$1")" >&2
}

# Label:value row — aligned label column
_ui_row() {
  local label="$1" value="$2" cfn="${3:-}"
  local pad=16
  local display_val="$value"
  [[ -n "$cfn" ]] && display_val="$("$cfn" "$value")"
  printf '%s  %-*s  %s\n' "$_UI_INDENT" "$pad" "$(_ui_dim "$label")" "$display_val" >&2
}

# Indented bullet item
_ui_item() {
  local marker="${1:-·}" text="$2" detail="${3:-}"
  printf '%s  %s  %s' "$_UI_INDENT" "$marker" "$text" >&2
  [[ -n "$detail" ]] && printf '  %s' "$(_ui_dim "$detail")" >&2
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# THIN-LINE BOX (dashboard header)
# ─────────────────────────────────────────────────────────────────────────────

_ui_box_top() {
  local w="${1:-$_UI_WIDTH}"
  printf '%s┌%s┐\n' "$_UI_INDENT" "$(printf '─%.0s' $(seq 1 $(( w - 2 ))))" >&2
}

_ui_box_bot() {
  local w="${1:-$_UI_WIDTH}"
  printf '%s└%s┘\n' "$_UI_INDENT" "$(printf '─%.0s' $(seq 1 $(( w - 2 ))))" >&2
}

_ui_box_sep() {
  local w="${1:-$_UI_WIDTH}"
  printf '%s├%s┤\n' "$_UI_INDENT" "$(printf '─%.0s' $(seq 1 $(( w - 2 ))))" >&2
}

# Print a padded line inside the box
_ui_box_line() {
  local content="${1:-}" lpad="${2:-2}"
  local w="$_UI_WIDTH"
  local visible; visible="$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')"
  local inner=$(( w - 2 ))
  local used=$(( lpad + ${#visible} + 1 ))
  local rpad=$(( inner - used ))
  [[ $rpad -lt 0 ]] && rpad=0
  local pfx spc
  pfx="$(printf ' %.0s' $(seq 1 "$lpad"))"
  spc="$(printf ' %.0s' $(seq 1 "$rpad"))"
  printf '%s│%s%s%s │\n' "$_UI_INDENT" "$pfx" "$content" "$spc" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS BAR
# ─────────────────────────────────────────────────────────────────────────────

# Returns bar string: [████░░░░░░░░░░░░░░░░]
_ui_bar() {
  local cur="$1" tot="$2" w="${3:-20}"
  local filled=0
  [[ $tot -gt 0 ]] && filled=$(( cur * w / tot ))
  local bar="" i
  for (( i=0; i<w; i++ )); do
    [[ $i -lt $filled ]] && bar="${bar}█" || bar="${bar}░"
  done
  printf '[%s]' "$bar"
}

# Health dot line: ●●●●●●●○○○
_ui_health_dots() {
  local score="${1:-0}" max="${2:-10}" w="${3:-10}"
  local si="${score%%.*}"
  si="${si:-0}"
  local filled=$(( si * w / max ))
  local out="" i
  for (( i=0; i<w; i++ )); do
    if [[ $i -lt $filled ]]; then out="${out}$(_ui_green "●")"
    else                          out="${out}$(_ui_dim   "○")"; fi
  done
  printf '%s' "$out"
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE PROMPTS
# Typing 'q' or 'Q' at any prompt returns exit code 1 (quit signal).
# Callers must check: value=$(_ui_prompt ...) || { _ui_info "Cancelled."; return 0; }
# ─────────────────────────────────────────────────────────────────────────────

_ui_is_quit() { [[ "${1,,}" == "q" || "${1,,}" == "quit" ]]; }
_ui_is_back() { [[ "${1,,}" == "b" || "${1,,}" == "back" ]]; }

# Text prompt — returns exit 1 if user types q
_ui_prompt() {
  local label="$1" default="${2:-}" hint="${3:-}"
  local dsp=""
  [[ -n "$default" ]] && dsp=" $(_ui_dim "[$default]")"
  [[ -z "$hint" ]] && hint="[q] cancel"
  printf '\n%s  %s%s  %s\n%s  > ' \
    "$_UI_INDENT" "$label" "$dsp" "$(_ui_dim "$hint")" "$_UI_INDENT" >&2
  local r
  IFS= read -r r
  [[ -z "$r" && -n "$default" ]] && r="$default"
  _ui_is_quit "$r" && return 1
  printf '%s' "$r"
}

# Compact single-line prompt
_ui_prompt_inline() {
  local label="$1" default="${2:-}"
  local dsp=""
  [[ -n "$default" ]] && dsp=" $(_ui_dim "[$default]")"
  printf '%s  %s%s: ' "$_UI_INDENT" "$label" "$dsp" >&2
  local r
  IFS= read -r r
  [[ -z "$r" && -n "$default" ]] && r="$default"
  _ui_is_quit "$r" && return 1
  printf '%s' "$r"
}

# Yes/No confirm — returns 0 for yes, 1 for no or quit
_ui_confirm() {
  local label="${1:-Continue?}" default="${2:-n}"
  local opts="[y/N]"
  [[ "$default" == "y" ]] && opts="[Y/n]"
  printf '%s  %s %s %s: ' \
    "$_UI_INDENT" "$label" "$(_ui_dim "$opts")" "$(_ui_dim "[q]cancel")" >&2
  local a
  IFS= read -r a
  [[ -z "$a" ]] && a="$default"
  _ui_is_quit "$a" && return 1
  [[ "${a,,}" == "y" ]]
}

# Numbered action menu — prints options, reads choice, returns chosen value.
# Always appends [q] Quit as the last option.
# Returns exit 1 if user quits.
_ui_action_menu() {
  # Args: title "Display text:return_key" ...
  # Exit codes: 0=choice made, 1=quit, 2=back
  local title="${1:-}" back_label="${_UI_BACK_LABEL:-Back}"; shift
  local items=("$@")
  _ui_blank
  printf '%s%s\n' "$_UI_INDENT" "$(_ui_bold "$title")" >&2
  _ui_blank
  local i
  for (( i=0; i<${#items[@]}; i++ )); do
    local display="${items[$i]%%:*}"
    printf '%s  [%d]  %s\n' "$_UI_INDENT" "$(( i+1 ))" "$display" >&2
  done
  # Show [b] Back only if caller set _UI_SHOW_BACK=1
  [[ "${_UI_SHOW_BACK:-0}" == "1" ]] &&     printf '%s  [b]  %s\n' "$_UI_INDENT" "$(_ui_dim "$back_label")" >&2
  printf '%s  [q]  Quit\n' "$_UI_INDENT" >&2
  _ui_blank
  printf '%s  > ' "$_UI_INDENT" >&2
  local c
  IFS= read -r c
  _ui_is_quit "$c" && return 1
  _ui_is_back "$c" && return 2
  if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -ge 1 ]] && [[ "$c" -le "${#items[@]}" ]]; then
    printf '%s' "${items[$(( c-1 ))]##*:}"
  else
    return 1
  fi
}

# Simple numbered list picker (no key suffixes — returns display text)
_ui_menu_choice() {
  local title="${1:-}"; shift
  local opts=("$@")
  _ui_blank
  printf '%s%s\n' "$_UI_INDENT" "$(_ui_bold "$title")" >&2
  _ui_blank
  local i
  for (( i=0; i<${#opts[@]}; i++ )); do
    printf '%s  [%d]  %s\n' "$_UI_INDENT" "$(( i+1 ))" "${opts[$i]}" >&2
  done
  [[ "${_UI_SHOW_BACK:-0}" == "1" ]] &&     printf '%s  [b]  %s\n' "$_UI_INDENT" "$(_ui_dim "Back")" >&2
  printf '%s  [q]  Cancel\n' "$_UI_INDENT" >&2
  _ui_blank
  printf '%s  > ' "$_UI_INDENT" >&2
  local c
  IFS= read -r c
  _ui_is_quit "$c" && return 1
  _ui_is_back "$c" && return 2
  if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -ge 1 ]] && [[ "$c" -le "${#opts[@]}" ]]; then
    printf '%s' "${opts[$(( c-1 ))]}"
  else
    return 1
  fi
}

_ui_pause() {
  printf '\n%s  %s ' "$_UI_INDENT" "$(_ui_dim "Press Enter to continue  [q to quit]")" >&2
  local k
  IFS= read -r k
  _ui_is_quit "$k" && return 1
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# STRING HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_ui_truncate() {
  local s="$1" max="${2:-40}"
  [[ ${#s} -gt $max ]] && printf '%s…' "${s:0:$(( max-1 ))}" || printf '%s' "$s"
}

_ui_pad() { printf '%-*s' "$2" "$1"; }

_ui_strip_ansi() { printf '%s' "$*" | sed 's/\x1b\[[0-9;]*m//g'; }

_ui_days_ago() {
  local t="${1:-}"
  [[ -z "$t" || "$t" == "-" ]] && printf 'never' && return 0
  python3 -c "
from datetime import date
try:
    d=date.fromisoformat('${t}'); n=(date.today()-d).days
    if n==0:   print('today')
    elif n==1: print('yesterday')
    elif n<7:  print(f'{n}d ago')
    elif n<30: print(f'{n//7}w ago')
    elif n<365:print(f'{n//30}mo ago')
    else:      print(f'{n//365}y ago')
except: print('${t}')
" 2>/dev/null || printf '%s' "$t"
}