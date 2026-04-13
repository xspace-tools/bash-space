# sconl-space/lib/cross.sh
# Cross-system command handlers for sconlx.
# Covers: full iSconl dashboard, event bus, search across all systems,
# export, backup trigger, and overall status.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Full dashboard (all 3 systems in one view), event bus
#             display/process, cross-system grep search, DB/flat-file status,
#             export (all systems → markdown), backup bridge to backupx.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_CROSS_LOADED:-}" ]] && return 0
_CROSS_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_CROSS_EXPORT_DIR="${HOME}/.local/share/isconl/exports"   # export target

# ─────────────────────────────────────────────────────────────────────────────
# ROUTER
# ─────────────────────────────────────────────────────────────────────────────

_cross_route() {
  local cmd="${1:-dashboard}"
  shift || true
  case "$cmd" in
    ""|dashboard)       _cross_dashboard ;;
    events)             _cross_events_route "$@" ;;
    status)             _cross_status ;;
    search)             _cross_search "$*" ;;
    export)             _cross_export ;;
    backup)             _cross_backup ;;
    *)                  _ui_err "Unknown cross-system command: $cmd" >&2
                        printf '\n  Usage: sconlx x [events|status|search|export|backup]\n\n' >&2 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# FULL iSCONL DASHBOARD
# This is what runs when you type bare 'sconlx' with no args.
# One view of everything.
# ─────────────────────────────────────────────────────────────────────────────

_cross_dashboard() {
  local eq_str; eq_str="$(_eq_today_short)"
  local today; today="$(_db_today)"

  # Load identity for the header line
  _db_identity_load 2>/dev/null || true

  _ui_box_top

  # Header
  local header="iSconl  ·  $eq_str"
  _ui_box_line "$(_ui_bold "$header")"
  [[ -n "${SEASON_THEME:-}" ]] && \
    _ui_box_line "$(_ui_italic "${SEASON_THEME}")"
  [[ -n "${SEASON_WORD:-}" || -n "${SEASON_NAME:-}" ]] && \
    _ui_box_line "$(_ui_dim "${SEASON_WORD:+$SEASON_WORD  ·  }${SEASON_NAME:-}")"

  _ui_box_mid

  # ── SCOPE section ──
  _ui_box_line "$(_ui_scope "$(_ui_bold "SCOPE")")"

  local inbox_count stale_count today_count goal_count reflection_done eq_year eq_cycle eq_day eq_theme
  inbox_count="$(_tsv_count "$_FLAT_SCOPE_INBOX" '$4=="new"')"
  stale_count="$(_scope_inbox_stale_count)"
  today_count="$(_tsv_count "$_FLAT_SCOPE_TASKS" '$3=="today"')"
  goal_count="$(_tsv_count "$_FLAT_SCOPE_GOALS" '$7=="active"')"
  IFS=$'\t' read -r eq_year eq_cycle eq_day eq_theme <<< "$(_eq_today_fields)"

  local reflect_file="$_FLAT_SCOPE_REFLECTIONS_DIR/../reflections.tsv"
  reflection_done="no entry"
  [[ -f "$_FLAT_SCOPE_REFLECTIONS_DIR/../reflections.tsv" ]] && \
    grep -q "$today" "$_FLAT_SCOPE_REFLECTIONS_DIR/../reflections.tsv" 2>/dev/null && \
    reflection_done="done"

  _ui_box_line "  $_UI_BADGE_INBOX Inbox: $inbox_count item(s)${stale_count:+  (${stale_count} stale)}  ·  ${_UI_BADGE_TODAY} Today: $today_count task(s)"
  _ui_box_line "  $_UI_BADGE_GOAL Goals: $goal_count active  ·  Reflect: $reflection_done"
  _ui_box_line "  $_UI_BADGE_CYCLE Cycle $eq_cycle/$eq_day  ·  $eq_theme"

  _ui_box_mid

  # ── SPACE section ──
  _ui_box_line "$(_ui_space "$(_ui_bold "SPACE")")"

  local space_total space_active space_health
  space_total="$(_tsv_count "$_FLAT_SPACE_SPACES" '$4!="archived"')"
  space_active="$(_tsv_count "$_FLAT_SPACE_SPACES" '$4=="active"')"
  space_health="$(_space_avg_health)"

  if [[ "$space_total" -gt 0 ]]; then
    _ui_box_line "  $_UI_BADGE_SPACE Portfolio: $space_active active  ·  Health: $space_health/10"

    # Show any overdue reviews
    local overdue_spaces
    overdue_spaces="$(awk -F'\t' 'NR>1 && $4!="archived" && ($9=="" || $9=="-") {print $2}' \
      "$_FLAT_SPACE_SPACES" 2>/dev/null | head -2 | tr '\n' ',' | sed 's/,$//' || true)"
    [[ -n "$overdue_spaces" ]] && \
      _ui_box_line "  $(_ui_yellow "⚠")  Review overdue: $overdue_spaces"
  else
    _ui_box_line "  No spaces yet  →  sconlx space add"
  fi

  _ui_box_mid

  # ── SPARK section ──
  _ui_box_line "$(_ui_spark "$(_ui_bold "SPARK")")"

  local journal_today ideas_cap ideas_dev ideas_ref learn_active dia_overdue
  local journal_file="$_FLAT_JOURNAL_DIR/${today}.md"

  if [[ -f "$journal_file" ]]; then
    local wc; wc="$(wc -w < "$journal_file" 2>/dev/null | tr -d ' ')"
    _ui_box_line "  $_UI_BADGE_JOURNAL Journal: ✓ done ($wc words)"
  else
    _ui_box_line "  $_UI_BADGE_JOURNAL Journal: ○ no entry today"
  fi

  ideas_cap="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="captured"')"
  ideas_dev="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="developing"')"
  ideas_ref="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="refined"')"
  learn_active="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$3=="active"')"
  dia_overdue="$(_spark_dia_overdue_count)"

  _ui_box_line "  $_UI_BADGE_IDEA Ideas: $ideas_cap captured  ·  $ideas_dev developing  ·  $ideas_ref refined"
  _ui_box_line "  $_UI_BADGE_BOOK Learning: $learn_active active  ·  $_UI_BADGE_DIA DIA: ${dia_overdue:-0} overdue"

  _ui_box_mid

  # ── QUICK ACTIONS section ──
  _ui_box_line "$(_ui_bold "NEXT ACTIONS")"

  local pending_events; pending_events="$(_ev_status)"

  # Only show relevant next actions
  [[ "$inbox_count" -gt 0 ]] && \
    _ui_box_line "  →  sconlx scope inbox       $(_ui_dim "($inbox_count to process)")"
  ! [[ -f "$journal_file" ]] && \
    _ui_box_line "  →  sconlx journal           $(_ui_dim "write today's entry")"
  [[ "$reflection_done" == "no entry" ]] && \
    _ui_box_line "  →  sconlx scope reflect     $(_ui_dim "evening reflection")"
  [[ "$pending_events" -gt 0 ]] && \
    _ui_box_line "  →  sconlx x events process  $(_ui_dim "($pending_events pending)")"
  [[ "$today_count" -eq 0 ]] && \
    _ui_box_line "  →  sconlx scope today       $(_ui_dim "select tasks for today")"

  _ui_box_bot

  printf '\n  %s\n\n' "$(_ui_dim "Mode: $_DATA_MODE  ·  sconlx --help  ·  sconlx --version")" >&2
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
  count="${count:-0}"

  printf '\n  EVENT BUS  (%s pending for sconlx)\n' "$count" >&2
  _ui_hr

  if [[ "$count" -eq 0 ]]; then
    _ui_ok "No pending events." >&2
    printf '\n' >&2; return 0
  fi

  while IFS=$'\t' read -r ev_id ev_type ev_payload; do
    [[ -z "$ev_id" ]] && continue
    local short_id; short_id="${ev_id:0:8}"
    printf '  %-10s  %-40s\n' "$short_id" "$ev_type" >&2
    [[ -n "$ev_payload" && "$ev_payload" != "{}" ]] && \
      printf '             %s\n' "$(_ui_dim "$(_ui_truncate "$ev_payload" 55)")" >&2
  done <<< "$pending"

  printf '\n  %s\n\n' "$(_ui_dim "sconlx x events process  — handle all pending events")" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────

_cross_status() {
  printf '\n  iSconl STATUS\n' >&2
  _ui_hr

  printf '\n  Data mode: %s\n' "$(_ui_bold "$_DATA_MODE")" >&2

  if [[ "$_DATA_MODE" == "sqlite" ]]; then
    printf '\n  SQLite databases:\n' >&2
    local _dbs=(
      "$_SCOPE_DB:scope.db"
      "$_SPACE_DB:space.db"
      "$_SPARK_DB:spark.db"
      "$_EVENTS_DB:isconl_events.db"
    )
    for _entry in "${_dbs[@]}"; do
      local db_var="${_entry%%:*}" db_name="${_entry##*:}"
      if [[ -f "$db_var" ]]; then
        local size; size="$(du -sh "$db_var" 2>/dev/null | cut -f1 || echo '?')"
        _ui_ok "$db_name  ($size)" >&2
      else
        _ui_warn "$db_name  not found" >&2
      fi
    done
  else
    printf '\n  Flat-file data directory: %s\n' "$_FLAT_DIR" >&2
    for f in \
      "$_FLAT_SCOPE_INBOX:inbox.tsv" \
      "$_FLAT_SCOPE_TASKS:tasks.tsv" \
      "$_FLAT_SCOPE_GOALS:goals.tsv" \
      "$_FLAT_SPACE_SPACES:spaces.tsv" \
      "$_FLAT_SPARK_IDEAS:ideas.tsv" \
      "$_FLAT_SPARK_LEARNING:learning.tsv"
    do
      local path="${f%%:*}" label="${f##*:}"
      if [[ -f "$path" ]]; then
        local rows; rows="$(_tsv_count "$path")"
        _ui_ok "$label  ($rows rows)" >&2
      else
        _ui_info "$label  (empty — will be created on first write)" >&2
      fi
    done
  fi

  # Event bus
  local ev_count; ev_count="$(_ev_status)"
  printf '\n  Event bus: %s pending event(s)\n' "$ev_count" >&2

  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# SEARCH (grep across all systems)
# ─────────────────────────────────────────────────────────────────────────────

_cross_search() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx x search <query>" >&2; return 1; }

  printf '\n  SEARCH: "%s"\n' "$query" >&2
  _ui_hr

  local found=0

  # Scope: tasks
  if [[ -f "$_FLAT_SCOPE_TASKS" ]]; then
    local matches
    matches="$(awk -F'\t' -v q="${query,,}" \
      'NR>1 && tolower($2)~q {printf "  %-8s  %-12s  %s\n", $1, $3, $2}' \
      "$_FLAT_SCOPE_TASKS" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
      printf '\n  %s\n' "$(_ui_scope "$(_ui_bold "SCOPE — TASKS")")" >&2
      printf '%s\n' "$matches" >&2
      (( ++found ))
    fi
  fi

  # Scope: goals
  if [[ -f "$_FLAT_SCOPE_GOALS" ]]; then
    local matches
    matches="$(awk -F'\t' -v q="${query,,}" \
      'NR>1 && tolower($2)~q {printf "  %-8s  %-12s  %s\n", $1, $7, $2}' \
      "$_FLAT_SCOPE_GOALS" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
      printf '\n  %s\n' "$(_ui_scope "$(_ui_bold "SCOPE — GOALS")")" >&2
      printf '%s\n' "$matches" >&2
      (( ++found ))
    fi
  fi

  # Space: spaces
  if [[ -f "$_FLAT_SPACE_SPACES" ]]; then
    local matches
    matches="$(awk -F'\t' -v q="${query,,}" \
      'NR>1 && (tolower($2)~q || tolower($6)~q) {printf "  %-8s  %-12s  %s\n", $1, $3, $2}' \
      "$_FLAT_SPACE_SPACES" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
      printf '\n  %s\n' "$(_ui_space "$(_ui_bold "SPACE — SPACES")")" >&2
      printf '%s\n' "$matches" >&2
      (( ++found ))
    fi
  fi

  # Spark: ideas
  if [[ -f "$_FLAT_SPARK_IDEAS" ]]; then
    local matches
    matches="$(awk -F'\t' -v q="${query,,}" \
      'NR>1 && (tolower($5)~q || tolower($4)~q) {printf "  %-8s  %-12s  %s\n", $1, $2, $5}' \
      "$_FLAT_SPARK_IDEAS" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
      printf '\n  %s\n' "$(_ui_spark "$(_ui_bold "SPARK — IDEAS")")" >&2
      printf '%s\n' "$matches" >&2
      (( ++found ))
    fi
  fi

  # Spark: learning
  if [[ -f "$_FLAT_SPARK_LEARNING" ]]; then
    local matches
    matches="$(awk -F'\t' -v q="${query,,}" \
      'NR>1 && tolower($2)~q {printf "  %-8s  %-12s  %s\n", $1, $4, $2}' \
      "$_FLAT_SPARK_LEARNING" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
      printf '\n  %s\n' "$(_ui_spark "$(_ui_bold "SPARK — LEARNING")")" >&2
      printf '%s\n' "$matches" >&2
      (( ++found ))
    fi
  fi

  # Journal: filenames (search inside would be slow — show dates with hits)
  if [[ -d "$_FLAT_JOURNAL_DIR" ]]; then
    local journal_hits=()
    while IFS= read -r jf; do
      grep -qi "$query" "$jf" 2>/dev/null && journal_hits+=("$(basename "$jf" .md)")
    done < <(find "$_FLAT_JOURNAL_DIR" -name "*.md" 2>/dev/null | sort -r | head -30)
    if [[ "${#journal_hits[@]}" -gt 0 ]]; then
      printf '\n  %s\n' "$(_ui_spark "$(_ui_bold "SPARK — JOURNAL")")" >&2
      printf '  %s\n' "$(_ui_dim "(Open entries to read — showing dates with matches)")" >&2
      for d in "${journal_hits[@]}"; do
        printf '  %s\n' "$d" >&2
      done
      (( ++found ))
    fi
  fi

  if [[ "$found" -eq 0 ]]; then
    printf '\n  %s\n\n' "$(_ui_dim "No results found for: $query")" >&2
  else
    printf '\n' >&2
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

_cross_export() {
  local export_dir="$_CROSS_EXPORT_DIR"
  mkdir -p "$export_dir"
  local timestamp; timestamp="$(date +%Y%m%d_%H%M%S)"
  local export_file="$export_dir/isconl_export_${timestamp}.md"

  printf '\n  EXPORT  →  %s\n' "$export_file" >&2
  _ui_hr

  {
    printf '# iSconl Export\n'
    printf '*Generated: %s*\n\n' "$(date)"
    printf '---\n\n'

    # Scope
    printf '## SCOPE\n\n'
    printf '### Tasks\n\n'
    if [[ -f "$_FLAT_SCOPE_TASKS" ]]; then
      awk -F'\t' 'NR>1 && $3!="archived" {printf "- [%s] %s (%s)\n", $3, $2, $4}' \
        "$_FLAT_SCOPE_TASKS"
    fi

    printf '\n### Goals\n\n'
    if [[ -f "$_FLAT_SCOPE_GOALS" ]]; then
      awk -F'\t' 'NR>1 && $7=="active" {
        pct = ($4+0 > 0) ? int($5*100/$4) : 0
        printf "- %s  [%d%%]\n", $2, pct
      }' "$_FLAT_SCOPE_GOALS"
    fi

    # Space
    printf '\n---\n\n## SPACE\n\n'
    printf '### Portfolio\n\n'
    if [[ -f "$_FLAT_SPACE_SPACES" ]]; then
      awk -F'\t' 'NR>1 && $4!="archived" {printf "- **%s** (%s) — %s — health %s/10\n", $2, $3, $4, $5}' \
        "$_FLAT_SPACE_SPACES"
    fi

    # Spark
    printf '\n---\n\n## SPARK\n\n'
    printf '### Ideas Pipeline\n\n'
    if [[ -f "$_FLAT_SPARK_IDEAS" ]]; then
      awk -F'\t' 'NR>1 && $2!="archived" && $2!="exported" {printf "- [%s] %s\n", $2, $5}' \
        "$_FLAT_SPARK_IDEAS"
    fi

    printf '\n### Learning Library\n\n'
    if [[ -f "$_FLAT_SPARK_LEARNING" ]]; then
      awk -F'\t' 'NR>1 {printf "- [%s] %s (%s%%) — %s\n", $4, $2, $5, $3}' \
        "$_FLAT_SPARK_LEARNING"
    fi

  } > "$export_file"

  _ui_cap "Export saved: $export_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP (bridge to backupx)
# ─────────────────────────────────────────────────────────────────────────────

_cross_backup() {
  if command -v backupx &>/dev/null; then
    _ui_info "Triggering backupx for iSconl data..." >&2
    backupx
  else
    _ui_warn "backupx not found. Run: sconlx x export  for a local export." >&2
    _ui_info "To set up backupx: cd xspace/_configure && ./install.sh" >&2
  fi
}