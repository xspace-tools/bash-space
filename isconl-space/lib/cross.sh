# sconl-space/lib/cross.sh
# Cross-system layer for sconlx.
# Covers: the main iSconl dashboard, guided "what now" menu, first-run setup,
# event bus, cross-system search, export, backup.
#
# The dashboard is the face of the entire system. Design principles:
#   - No emojis, no tables. Clean hierarchy.
#   - Load all context in one Python call (_ctx_load).
#   - Every piece of information earns its place — minimal cognitive load.
#   - End with a guided action menu, not a wall of hints.
#   - First-run detection triggers identity setup automatically.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v2.0.0 — Complete redesign. Clean dashboard (no emojis, no tables),
#             _ctx_load for single Python call, intelligent guided menu,
#             first-run detection, time-aware suggestions, AI hook scaffolding.
#   v1.0.0 — Initial. Dashboard, events, search, export, backup.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_CROSS_LOADED:-}" ]] && return 0
_CROSS_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_CROSS_EXPORT_DIR="$HOME/.local/share/isconl/exports"
_CROSS_FIRST_RUN_MARKER="$_FLAT_DIR/.firstrun_complete"

# Current hour for time-aware suggestions — force base-10, avoid octal trap
_CROSS_HOUR=$(( 10#$(date +%H) ))

# ─────────────────────────────────────────────────────────────────────────────
# ROUTER
# ─────────────────────────────────────────────────────────────────────────────

_cross_route() {
  local cmd="${1:-dashboard}"
  shift || true
  case "$cmd" in
    ""|dashboard)  _cross_dashboard ;;
    events)        _cross_events_route "$@" ;;
    status)        _cross_status ;;
    search)        _cross_search "$*" ;;
    export)        _cross_export ;;
    backup)        _cross_backup ;;
    *)
      _ui_err "Unknown command: $cmd"
      printf '\n%s  Usage: sconlx x [events|status|search|export|backup]\n\n' "$_UI_INDENT" >&2 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# FIRST-RUN CHECK
# ─────────────────────────────────────────────────────────────────────────────

_cross_is_first_run() {
  # Show welcome only if identity not set AND marker not present
  # Once skipped or completed, marker is touched and welcome never shows again
  [[ -f "${_CROSS_FIRST_RUN_MARKER:-/dev/null}" ]] && return 1
  ! _db_identity_exists
}

_cross_first_run_welcome() {
  _ui_blank
  _ui_box_top
  _ui_box_line "$(_ui_bold "Welcome to iSconl")"
  _ui_box_sep
  _ui_box_line "Your personal workspace — scope, space, and spark."
  _ui_box_line "Before the daily loop, set up your identity layer."
  _ui_box_line "It takes about 5 minutes and anchors everything else."
  _ui_box_bot

  _ui_blank
  local choice
  choice="$(_ui_action_menu "How do you want to proceed?" \
    "Set up identity now  (recommended):setup" \
    "Skip — go to dashboard:skip")" || return 0

  case "$choice" in
    setup)
      _scope_identity_edit
      touch "$_CROSS_FIRST_RUN_MARKER" 2>/dev/null || true
      ;;
    skip)
      _ui_info "Skipped. Run anytime: sconlx scope identity edit"
      touch "${_CROSS_FIRST_RUN_MARKER}" 2>/dev/null || true
      ;;
  esac
}

# Helper: re-show the guided menu (used by back navigation from sub-menus)
_cross_guided_menu_loop() {
  # Re-read state and re-show menu without redrawing the full dashboard
  local today; today="$(_db_today)"
  local has_reflection="no"
  [[ -f "$_FLAT_SCOPE_REFLECTIONS_TSV" ]] && \
    grep -qF "$today" "$_FLAT_SCOPE_REFLECTIONS_TSV" 2>/dev/null && has_reflection="yes"
  local inbox_count today_count i_ref
  inbox_count="$(_tsv_count "$_FLAT_SCOPE_INBOX" '$4=="new"')"
  today_count="$(_tsv_count "$_FLAT_SCOPE_TASKS" '$3=="today"')"
  i_ref="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="refined"')"
  _cross_guided_menu "$today" "$has_reflection" "$inbox_count" "$today_count" "$i_ref"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────

_cross_dashboard() {
  # First-run check — identity setup gate
  if _cross_is_first_run; then
    _cross_first_run_welcome
    # After setup (or skip), show dashboard
  fi

  # Load all context in one Python call
  _ctx_load || true
  _db_identity_load 2>/dev/null || true

  local today; today="$(_db_today)"

  # ── HEADER — clean line-separated, no box drawing ──
  local day_theme; day_theme="$(_db_day_theme)"
  local block_status; block_status="$(_db_block_status)"

  _ui_blank
  _ui_hr
  printf '%s%s  %s\n' "$_UI_INDENT"     "$(_ui_bold "iSconl")"     "$(_ui_dim "·  $_DATA_MODE mode")" >&2
  _ui_hr

  # Date + time systems
  printf '%s%s\n' "$_UI_INDENT" "$(_ui_bold "$CTX_GREGORIAN")" >&2
  printf '%s%s  %s\n' "$_UI_INDENT"     "$CTX_EQ_SHORT"     "$(_ui_dim "·  $CTX_SPRINT_SHORT")" >&2

  # Day theme + focus block status on same line
  local block_note=""
  case "$block_status" in
    IN:*)
      local _bn="${block_status#IN:}"; _bn="${_bn%%:*}"
      local _br="${block_status##*:}"
      block_note="  $(_ui_dim "·")  $(_ui_bold "$_bn block")  $(_ui_dim "($_br)")" ;;
    NEXT:*)
      local _bi="${block_status#NEXT:}"; local _bn="${_bi%%:*}"; local _bu="${_bi##*:}"
      block_note="  $(_ui_dim "·  next: $_bn  ($_bu)")" ;;
  esac
  printf '%s%s%s\n' "$_UI_INDENT" "$(_ui_dim "$day_theme")" "$block_note" >&2

  # Year progress
  printf '%sYear %s  %s\n' "$_UI_INDENT"     "${CTX_YEAR_PCT}%"     "$(_ui_dim "${CTX_YEAR_BAR}  day ${CTX_YEAR_DAY} / ${CTX_YEAR_TOTAL}")" >&2

  # Age (only when birthday set)
  if [[ -n "${CTX_AGE_SHORT:-}" ]]; then
    printf '%sAge %s  %s\n' "$_UI_INDENT"       "$(_ui_bold "$CTX_AGE_SHORT")"       "$(_ui_dim "·  ${CTX_DAYS_TO_BDAY}d to birthday  (turning $CTX_TURNING)")" >&2
  fi

  # Season / identity  
  if [[ -n "${SEASON_THEME:-${SEASON_NAME:-}}" ]]; then
    _ui_hr
    printf '%s%s\n' "$_UI_INDENT" "$(_ui_italic "${SEASON_THEME:-$SEASON_NAME}")" >&2
    [[ -n "${CORE_VALUES:-}" ]] &&       printf '%s%s\n' "$_UI_INDENT" "$(_ui_dim "${CORE_VALUES//|/ · }")" >&2
  fi

  _ui_hr

  # ── SCOPE ──
  _ui_section_scope "SCOPE" "daily rhythm"

  local inbox_count today_count done_count goal_count deferred_count
  inbox_count="$(_tsv_count "$_FLAT_SCOPE_INBOX" '$4=="new"')"
  today_count="$(_tsv_count "$_FLAT_SCOPE_TASKS"  '$3=="today"')"
  done_count="$(_tsv_count  "$_FLAT_SCOPE_TASKS"  '$3=="done"')"
  deferred_count="$(_tsv_count "$_FLAT_SCOPE_TASKS" '$3=="deferred"')"
  goal_count="$(_tsv_count "$_FLAT_SCOPE_GOALS" '$7=="active"')"

  # Inbox
  local inbox_line="$inbox_count item(s)"
  [[ "$inbox_count" -eq 0 ]] && inbox_line="$(_ui_dim "empty")"
  _ui_row "Inbox" "$inbox_line"

  # Today's tasks
  local today_line=""
  if [[ "$today_count" -gt 0 ]]; then
    today_line="$today_count selected  $(_ui_dim "($done_count done)")"
  else
    today_line="$(_ui_dim "none selected")"
  fi
  [[ "$deferred_count" -gt 0 ]] && today_line="${today_line}  $(_ui_yellow "${deferred_count} deferred")"
  _ui_row "Today" "$today_line"

  # Active goals with first goal preview
  if [[ "$goal_count" -gt 0 ]]; then
    local first_goal first_pct
    first_goal="$(awk -F'\t' 'NR>1 && $7=="active" {print $2; exit}' "$_FLAT_SCOPE_GOALS" 2>/dev/null | head -c 35)"
    first_pct="$(awk -F'\t' 'NR>1 && $7=="active" {pct=($4>0)?int($5*100/$4):0; print pct; exit}' \
      "$_FLAT_SCOPE_GOALS" 2>/dev/null)"
    local goal_bar; goal_bar="$(_ui_bar "${first_pct:-0}" 100 12)"
    _ui_row "Goals" "$goal_count active  $(_ui_dim "·  ${first_goal:-}  $goal_bar ${first_pct:-0}%")"
  else
    _ui_row "Goals" "$(_ui_dim "none yet")"
  fi

  # Cycle progress
  local cycle_line
  cycle_line="Cycle $CTX_EQ_CYCLE  $(_ui_dim "·  Day $CTX_EQ_DAY / 28  $CTX_CYCLE_BAR  $CTX_CYCLE_PCT%")"
  _ui_row "Cycle" "$cycle_line"

  # Reflection
  local has_reflection="no"
  [[ -f "$_FLAT_SCOPE_REFLECTIONS_TSV" ]] && \
    grep -qF "$today" "$_FLAT_SCOPE_REFLECTIONS_TSV" 2>/dev/null && has_reflection="yes"
  local refl_line
  if [[ "$has_reflection" == "yes" ]]; then
    refl_line="$(_ui_green "done")"
  else
    if [[ "$_CROSS_HOUR" -ge 17 ]]; then
      refl_line="$(_ui_yellow "due  (evening reflection)")"
    else
      refl_line="$(_ui_dim "not yet")"
    fi
  fi
  _ui_row "Reflection" "$refl_line"

  # ── SPACE ──
  _ui_section_space "SPACE" "domain portfolio"

  local space_total space_active space_health
  space_total="$(_tsv_count "$_FLAT_SPACE_SPACES" '$4!="archived"')"

  if [[ "$space_total" -gt 0 ]]; then
    space_active="$(_tsv_count "$_FLAT_SPACE_SPACES" '$4=="active"')"
    space_health="$(_space_avg_health)"
    _ui_row "Portfolio" "$space_active active  $(_ui_dim "·  health $space_health/10  $(_ui_health_dots "$space_health" 10 8)")"

    # Show first 2 active spaces inline
    awk -F'\t' 'NR>1 && $4=="active" {
      printf "%-20s  %-10s  %s/10\n", substr($2,1,20), $3, $5
      if (++n>=2) exit
    }' "$_FLAT_SPACE_SPACES" 2>/dev/null | while IFS= read -r line; do
      _ui_hint "$line"
    done

    # Overdue reviews
    local overdue_spaces
    overdue_spaces="$(_cross_overdue_reviews)"
    [[ -n "$overdue_spaces" ]] && _ui_warn "Review overdue: $overdue_spaces"
  else
    _ui_row "Portfolio" "$(_ui_dim "no spaces yet  — sconlx space add")"
  fi

  # ── SPARK ──
  _ui_section_spark "SPARK" "inner world"

  # Journal
  # Check both new (YYYYMMDD_HHMM_title.md) and legacy (YYYYMMDD.md) formats
  local journal_file; journal_file="$(_journal_today_file 2>/dev/null || true)"
  if [[ -n "$journal_file" ]]; then
    local wc; wc="$(wc -w < "$journal_file" 2>/dev/null | tr -d ' ')"
    local streak; streak="$(_spark_journal_streak)"
    _ui_row "Journal" "$(_ui_green "written")  $(_ui_dim "·  $wc words  ·  streak: ${streak}d")"
  else
    _ui_row "Journal" "$(_ui_dim "no entry today")"
  fi

  # Ideas
  local i_cap i_dev i_ref
  i_cap="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="captured"')"
  i_dev="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="developing"')"
  i_ref="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="refined"')"
  local idea_line="${i_cap} captured"
  [[ "$i_dev" -gt 0 ]] && idea_line="${idea_line}  ·  ${i_dev} developing"
  [[ "$i_ref" -gt 0 ]] && idea_line="${idea_line}  ·  $(_ui_yellow "${i_ref} refined — decide")"
  _ui_row "Ideas" "$idea_line"

  # Learning
  local learn_active; learn_active="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$4=="active"')"
  if [[ "$learn_active" -gt 0 ]]; then
    local learn_title learn_pct learn_bar
    learn_title="$(awk -F'\t' 'NR>1 && $4=="active" {print $2; exit}' "$_FLAT_SPARK_LEARNING" 2>/dev/null | head -c 30)"
    learn_pct="$(awk -F'\t'  'NR>1 && $4=="active" {print $5+0; exit}' "$_FLAT_SPARK_LEARNING" 2>/dev/null)"
    learn_bar="$(_ui_bar "${learn_pct:-0}" 100 10)"
    _ui_row "Learning" "$(_ui_truncate "${learn_title:-active}" 25)  $learn_bar ${learn_pct:-0}%"
  else
    _ui_row "Learning" "$(_ui_dim "nothing active")"
  fi

  # DIA overdue
  local dia_overdue; dia_overdue="$(_spark_dia_overdue_count)"
  [[ "$dia_overdue" -gt 0 ]] && _ui_warn "DIA: $dia_overdue profile(s) need interaction"

  # ── GUIDED ACTION MENU ──
  _cross_guided_menu "$today" "$has_reflection" "$inbox_count" \
    "$today_count" "$i_ref"
}

# ─────────────────────────────────────────────────────────────────────────────
# GUIDED ACTION MENU
# The "what now?" prompt — scores and presents prioritized options.
# This is what makes the daily loop feel like a conversation.
# ─────────────────────────────────────────────────────────────────────────────

_cross_guided_menu() {
  local today="$1" has_reflection="$2" inbox_count="$3"
  local today_count="$4" ideas_refined="$5"

  local -a actions=()
  local -a keys=()

  # Build priority-ordered action list based on current state

  # Morning focus: tasks and inbox
  if [[ "$_CROSS_HOUR" -lt 12 ]]; then
    [[ "$today_count" -eq 0 ]] && {
      actions+=("Select tasks for today")
      keys+=("scope_today")
    }
    [[ "$inbox_count" -gt 0 ]] && {
      actions+=("Process inbox  ($inbox_count items)")
      keys+=("scope_inbox")
    }
    ! _journal_has_today 2>/dev/null && {
      actions+=("Write morning journal entry")
      keys+=("journal")
    }

  # Evening focus: reflection and review
  elif [[ "$_CROSS_HOUR" -ge 17 ]]; then
    [[ "$has_reflection" == "no" ]] && {
      actions+=("Evening reflection")
      keys+=("scope_reflect")
    }
    ! _journal_has_today 2>/dev/null && {
      actions+=("Write journal entry")
      keys+=("journal")
    }
    [[ "$today_count" -gt 0 ]] && {
      actions+=("Review today's tasks")
      keys+=("scope_task_list")
    }

  # Daytime: balanced
  else
    ! _journal_has_today 2>/dev/null && {
      actions+=("Write journal entry")
      keys+=("journal")
    }
    [[ "$inbox_count" -gt 0 ]] && {
      actions+=("Process inbox  ($inbox_count items)")
      keys+=("scope_inbox")
    }
    [[ "$today_count" -eq 0 ]] && {
      actions+=("Select tasks for today")
      keys+=("scope_today")
    }
  fi

  # Always-available options
  [[ "$ideas_refined" -gt 0 ]] && {
    actions+=("Decide on refined ideas  ($ideas_refined)")
    keys+=("spark_ideas")
  }
  actions+=("Capture something  (inbox / idea / note)")
  keys+=("capture")
  actions+=("View all Scope")
  keys+=("scope")
  actions+=("View all Space")
  keys+=("space")
  actions+=("View all Spark")
  keys+=("spark")

  _ui_blank
  _ui_hr
  printf '%s%s\n' "$_UI_INDENT" "$(_ui_bold "What would you like to do?")" >&2
  _ui_blank

  local i max_show=6
  local n="${#actions[@]}"
  [[ $n -lt $max_show ]] && max_show=$n

  for (( i=0; i<max_show; i++ )); do
    printf '%s  [%d]  %s\n' "$_UI_INDENT" "$(( i+1 ))" "${actions[$i]}" >&2
  done
  [[ $n -gt $max_show ]] && \
    printf '%s  [m]  More options\n' "$_UI_INDENT" >&2
  printf '%s  [q]  Quit\n' "$_UI_INDENT" >&2
  _ui_blank
  printf '%s  > ' "$_UI_INDENT" >&2

  local choice
  IFS= read -r choice

  _ui_is_quit "$choice" && return 0

  # Handle 'more'
  if [[ "${choice,,}" == "m" ]]; then
    _cross_more_actions
    return 0
  fi

  # Validate number
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
     [[ "$choice" -lt 1 ]] || \
     [[ "$choice" -gt $max_show ]]; then
    return 0
  fi

  local key="${keys[$(( choice - 1 ))]}"
  _cross_dispatch_action "$key"
}

_cross_dispatch_action() {
  local key="$1"
  case "$key" in
    scope_inbox)    _scope_inbox_route ;;
    scope_today)    _scope_today_route ;;
    scope_reflect)  _scope_reflect_guided ;;
    scope_task_list) _scope_task_list ;;
    scope)          _scope_dashboard ;;
    space)          _space_dashboard ;;
    spark)          _spark_dashboard ;;
    journal)        _spark_journal_open ;;
    spark_ideas)    _spark_idea_list ;;
    capture)        _cross_capture_menu ;;
    *)              _ui_info "Unknown action." ;;
  esac
}

_cross_more_actions() {
  local action
  _UI_SHOW_BACK=1 _UI_BACK_LABEL="Back to main menu"
  action="$(_ui_action_menu "All options" \
    "Add a task:scope_task_add" \
    "Add a goal:scope_goal_add" \
    "Add an idea:spark_idea_add" \
    "Quick note:spark_note_capture" \
    "Add a space:space_add" \
    "Log a KPI:space_kpi_log" \
    "Log a DIA interaction:spark_dia_log" \
    "Cross-system search:cross_search" \
    "Export all data:cross_export" \
    "DB / file status:cross_status")" || return 0

  case "$action" in
    scope_task_add)   _scope_task_add ;;
    scope_goal_add)   _scope_goal_add ;;
    spark_idea_add)   _spark_idea_add ;;
    spark_note_capture) _spark_note_capture ;;
    space_add)        _space_add ;;
    space_kpi_log)    _space_kpi_log ;;
    spark_dia_log)    _spark_dia_log ;;
    cross_search)
      local q; q="$(_ui_prompt "Search query")" || return 0
      _cross_search "$q" ;;
    cross_export)     _cross_export ;;
    cross_status)     _cross_status ;;
  esac
  _UI_SHOW_BACK=0
}

# Quick capture menu
_cross_capture_menu() {
  local action
  _UI_SHOW_BACK=1 _UI_BACK_LABEL="Back to menu"
  action="$(_ui_action_menu "Capture what?" \
    "Inbox item  (process later):inbox" \
    "Idea  (goes to Spark pipeline):idea" \
    "Quick note  (opens editor):note" \
    "Task  (goes to Scope backlog):task")"
  local _rc=$?
  _UI_SHOW_BACK=0
  [[ $_rc -eq 2 ]] && _cross_guided_menu_loop && return 0  # back
  [[ $_rc -ne 0 ]] && return 0

  case "$action" in
    inbox) _scope_inbox_add ;;
    idea)  _spark_idea_add ;;
    note)  _spark_note_capture ;;
    task)  _scope_task_add ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# EVENTS
# ─────────────────────────────────────────────────────────────────────────────

_cross_events_route() {
  case "${1:-list}" in
    list|"") _cross_events_list ;;
    process) _ev_process_all ;;
    *)       _cross_events_list ;;
  esac
}

_cross_events_list() {
  local pending; pending="$(_ev_pending)"
  local count; count="$(printf '%s\n' "$pending" | wc -l | tr -d ' ')"
  [[ -z "$pending" ]] && count=0

  _ui_section "EVENT BUS" "$count pending"

  if [[ "${count:-0}" -eq 0 ]]; then
    _ui_ok "No pending events."
    _ui_blank
    return 0
  fi

  while IFS=$'\t' read -r ev_id ev_type ev_payload; do
    [[ -z "$ev_id" ]] && continue
    printf '%s  %-10s  %s\n' "$_UI_INDENT" "${ev_id:0:8}" "$ev_type" >&2
    [[ -n "$ev_payload" && "$ev_payload" != "{}" ]] && \
      _ui_hint "$(_ui_truncate "$ev_payload" 52)"
  done <<< "$pending"

  _ui_blank
  _ui_hint "sconlx x events process  — handle all"
  _ui_blank
}

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────

_cross_status() {
  _ui_section "STATUS"

  _ui_row "Data mode" "$(_ui_bold "$_DATA_MODE")"
  _ui_row "Data dir"  "$_FLAT_DIR"
  _ui_blank

  if [[ "$_DATA_MODE" == "sqlite" ]]; then
    _ui_subsection "SQLite databases"
    local _dbs=("$_SCOPE_DB:scope.db" "$_SPACE_DB:space.db" \
                "$_SPARK_DB:spark.db" "$_EVENTS_DB:isconl_events.db")
    for _e in "${_dbs[@]}"; do
      local _p="${_e%%:*}" _n="${_e##*:}"
      if [[ -f "$_p" ]]; then
        local sz; sz="$(du -sh "$_p" 2>/dev/null | cut -f1)"
        _ui_ok "$_n  ($sz)"
      else
        _ui_warn "$_n  not found"
      fi
    done
  else
    _ui_subsection "Flat-file data"
    for _e in \
      "$_FLAT_SCOPE_INBOX:inbox.tsv" \
      "$_FLAT_SCOPE_TASKS:tasks.tsv" \
      "$_FLAT_SCOPE_GOALS:goals.tsv" \
      "$_FLAT_SPACE_SPACES:spaces.tsv" \
      "$_FLAT_SPARK_IDEAS:ideas.tsv" \
      "$_FLAT_SPARK_LEARNING:learning.tsv"
    do
      local _p="${_e%%:*}" _n="${_e##*:}"
      if [[ -f "$_p" ]]; then
        local rows; rows="$(_tsv_count "$_p")"
        _ui_ok "$_n  ($rows rows)"
      else
        _ui_info "$_n  (no data yet)"
      fi
    done
  fi

  _ui_blank
  local ev_n; ev_n="$(_ev_status)"
  _ui_row "Event bus" "$ev_n pending event(s)"
  _ui_blank
}

# ─────────────────────────────────────────────────────────────────────────────
# SEARCH
# ─────────────────────────────────────────────────────────────────────────────

_cross_search() {
  local query="$1"
  if [[ -z "$query" ]]; then
    query="$(_ui_prompt "Search query")" || return 0
  fi

  _ui_section "SEARCH" "\"$query\""

  local found=0

  _cross_search_tsv "$_FLAT_SCOPE_TASKS" "2" "$query" \
    "3" "SCOPE  Tasks" "_ui_scope" && (( ++found )) || true

  _cross_search_tsv "$_FLAT_SCOPE_GOALS" "2" "$query" \
    "7" "SCOPE  Goals" "_ui_scope" && (( ++found )) || true

  _cross_search_tsv "$_FLAT_SPACE_SPACES" "2" "$query" \
    "4" "SPACE  Spaces" "_ui_space" && (( ++found )) || true

  _cross_search_tsv "$_FLAT_SPARK_IDEAS" "5" "$query" \
    "2" "SPARK  Ideas" "_ui_spark" && (( ++found )) || true

  _cross_search_tsv "$_FLAT_SPARK_LEARNING" "2" "$query" \
    "4" "SPARK  Learning" "_ui_spark" && (( ++found )) || true

  # Journal — filename search only (grep content)
  if [[ -d "$_FLAT_JOURNAL_DIR" ]]; then
    local hits=()
    while IFS= read -r jf; do
      grep -qi "$query" "$jf" 2>/dev/null && hits+=("$(basename "$jf" .md)")
    done < <(find "$_FLAT_JOURNAL_DIR" -name "*.md" 2>/dev/null | sort -r | head -30)
    if [[ "${#hits[@]}" -gt 0 ]]; then
      _ui_subsection "$(_ui_spark "SPARK  Journal")"
      _ui_hint "(dates with matching entries — open to read)"
      for d in "${hits[@]}"; do
        printf '%s  %s\n' "$_UI_INDENT" "$d" >&2
      done
      (( ++found ))
    fi
  fi

  [[ "$found" -eq 0 ]] && _ui_info "No results for: $query"
  _ui_blank
}

_cross_search_tsv() {
  local file="$1" title_field="$2" query="$3" \
        status_field="$4" label="$5" cfn="${6:-}"
  [[ -f "$file" ]] || return 1
  local matches
  matches="$(awk -F'\t' -v q="${query,,}" -v tf="$title_field" -v sf="$status_field" '
    NR>1 && tolower($tf)~q {
      printf "  %-8s  %-12s  %s\n", $1, $sf, $tf
    }' "$file" 2>/dev/null || true)"
  [[ -z "$matches" ]] && return 1
  _ui_subsection "$("${cfn:-printf}" "${cfn:+$label}" 2>/dev/null || printf '%s' "$label")"
  printf '%s\n' "$matches" >&2
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

_cross_export() {
  mkdir -p "$_CROSS_EXPORT_DIR"
  local ts; ts="$(date +%Y%m%d_%H%M%S)"
  local out="$_CROSS_EXPORT_DIR/isconl_export_${ts}.md"

  printf '# iSconl Export\n*%s*\n\n---\n\n' "$(date)" > "$out"

  {
    printf '## SCOPE\n\n### Tasks\n\n'
    [[ -f "$_FLAT_SCOPE_TASKS" ]] && \
      awk -F'\t' 'NR>1 && $3!="archived" {printf "- [%s] %s (%s)\n",$3,$2,$4}' "$_FLAT_SCOPE_TASKS"

    printf '\n### Goals\n\n'
    [[ -f "$_FLAT_SCOPE_GOALS" ]] && \
      awk -F'\t' 'NR>1 && $7=="active" {
        pct=($4>0)?int($5*100/$4):0
        printf "- %s  [%d%%]\n",$2,pct
      }' "$_FLAT_SCOPE_GOALS"

    printf '\n---\n\n## SPACE\n\n### Spaces\n\n'
    [[ -f "$_FLAT_SPACE_SPACES" ]] && \
      awk -F'\t' 'NR>1 && $4!="archived" {printf "- **%s** (%s) — %s — health %s/10\n",$2,$3,$4,$5}' \
        "$_FLAT_SPACE_SPACES"

    printf '\n---\n\n## SPARK\n\n### Ideas\n\n'
    [[ -f "$_FLAT_SPARK_IDEAS" ]] && \
      awk -F'\t' 'NR>1 && $2!="archived" && $2!="exported" {printf "- [%s] %s\n",$2,$5}' \
        "$_FLAT_SPARK_IDEAS"

    printf '\n### Learning\n\n'
    [[ -f "$_FLAT_SPARK_LEARNING" ]] && \
      awk -F'\t' 'NR>1 {printf "- [%s] %s (%s%%) — %s\n",$4,$2,$5,$3}' \
        "$_FLAT_SPARK_LEARNING"
  } >> "$out"

  _ui_cap "Exported: $out"
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP
# ─────────────────────────────────────────────────────────────────────────────

_cross_backup() {
  if command -v backupx &>/dev/null; then
    _ui_info "Triggering backupx for iSconl data..."
    backupx
  else
    _ui_warn "backupx not found."
    _ui_hint "Run: sconlx x export  for a local markdown export."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Return comma-separated names of spaces with overdue reviews
_cross_overdue_reviews() {
  [[ -f "$_FLAT_SPACE_SPACES" ]] || return 0
  local today; today="$(_db_today)"
  awk -F'\t' -v today="$today" '
    NR>1 && $4!="archived" {
      if ($9=="" || $9=="-") { print $2; next }
      cmd="python3 -c \"from datetime import date; print((date.fromisoformat('"'"'"today"'"'"')-date.fromisoformat('"'"'"$9"'"'"')).days)\" 2>/dev/null"
      cmd | getline d; close(cmd)
      if (d+0 > 14) print $2
    }' "$_FLAT_SPACE_SPACES" 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//'
}