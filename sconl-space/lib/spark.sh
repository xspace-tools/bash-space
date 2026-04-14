# sconl-space/lib/spark.sh
# Spark command handlers — growth & inner world layer.
# Covers: journal, notes, ideas (pipeline), learning, DIA (names/dates only).
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Journal (editor + view + list), quick notes, idea
#             pipeline (add/list/develop/advance/export), learning library
#             (add/list/progress/done), DIA profiles (metadata only — no
#             encrypted content in CLI per security decision 005).
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_SPARK_LOADED:-}" ]] && return 0
_SPARK_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_SPARK_IDEA_REVIEW_DAYS=7    # ideas in Captured stage older than this get flagged
_SPARK_DIA_OVERDUE_DAYS=30   # DIA profiles not contacted in this many days → flagged

# Idea stage progression
_SPARK_IDEA_STAGES=("captured" "developing" "refined" "decided" "exported" "archived")

# Learning resource types
_SPARK_LEARN_TYPES=("book" "course" "article" "video" "podcast" "other")

# DIA relationship types
_SPARK_DIA_TYPES=("mentor" "peer" "client" "partner" "collaborator" "friend" "advisor")

# ─────────────────────────────────────────────────────────────────────────────
# ROUTER
# ─────────────────────────────────────────────────────────────────────────────

_spark_route() {
  local cmd="${1:-dashboard}"
  shift || true
  case "$cmd" in
    ""|dashboard)  _spark_dashboard ;;
    journal)       _spark_journal_route "$@" ;;
    note)          _spark_note_route "$@" ;;
    idea)          _spark_idea_route "$@" ;;
    learn)         _spark_learn_route "$@" ;;
    dia)           _spark_dia_route "$@" ;;
    *)             _ui_err "Unknown spark command: $cmd" >&2
                   printf '\n  Usage: sconlx spark [journal|note|idea|learn|dia]\n\n' >&2 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# SPARK DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────

_spark_dashboard() {
  local eq_str; eq_str="$(_eq_today_short)"
  printf '\n  Spark  ·  %s\n' "$eq_str" >&2
  _ui_hr

  # Journal
  local today; today="$(_db_today)"
  local journal_file="$_FLAT_JOURNAL_DIR/${today}.md"
  printf '\n  %s  %s\n' "Journal" "$(_ui_bold "JOURNAL")" >&2
  if [[ -f "$journal_file" ]]; then
    local wc; wc="$(wc -w < "$journal_file" 2>/dev/null || echo 0)"
    printf '  %s  Entry written today (%s words)\n' "$(_ui_green "✓")" "$wc" >&2
  else
    printf '  %s  No entry today  → %s\n' "○" "$(_ui_dim "sconlx journal")" >&2
  fi

  # Streak
  local streak; streak="$(_spark_journal_streak)"
  [[ "$streak" -gt 0 ]] && printf '  Streak: %s days\n' "$streak" >&2

  # Ideas pipeline
  local ideas_captured ideas_developing ideas_refined
  ideas_captured="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="captured"')"
  ideas_developing="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="developing"')"
  ideas_refined="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2=="refined"')"

  printf '\n  %s  %s\n' "Ideas" "$(_ui_bold "IDEAS")" >&2
  printf '  Captured: %s  ·  Developing: %s  ·  Refined: %s\n' \
    "$ideas_captured" "$ideas_developing" "$ideas_refined" >&2

  # Flag stale ideas
  local stale_ideas; stale_ideas="$(_spark_stale_ideas_count)"
  [[ "$stale_ideas" -gt 0 ]] && \
    _ui_warn "$stale_ideas idea(s) in Captured >7 days — time to develop or archive" >&2

  # Learning
  local active_learning
  active_learning="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$3=="active"')"
  printf '\n  %s  %s\n' "Learning" "$(_ui_bold "LEARNING")" >&2
  if [[ "$active_learning" -gt 0 ]]; then
    awk -F'\t' 'NR>1 && $3=="active" {
      bar=""
      pct=$5+0
      for(i=1;i<=10;i++) bar=bar (i<=int(pct/10)?"█":"░")
      printf "  %-30s  %s  %d%%\n", substr($2,1,30), bar, pct
    }' "$_FLAT_SPARK_LEARNING" | head -2 >&2 || true
  else
    printf '  %s\n' "$(_ui_dim "No active resources")" >&2
  fi

  # DIA
  local dia_total dia_overdue
  dia_total="$(_tsv_count "$_FLAT_SPARK_DIA")"
  dia_overdue="$(_spark_dia_overdue_count)"
  printf '\n  %s  %s\n' "DIA" "$(_ui_bold "DIA")" >&2
  printf '  %s profiles' "$dia_total" >&2
  [[ "$dia_overdue" -gt 0 ]] && printf '  ·  %s overdue' "$(_ui_yellow "$dia_overdue")" >&2
  printf '\n' >&2

  printf '\n  %s\n\n' "$(_ui_dim "sconlx journal  ·  sconlx spark idea add  ·  sconlx spark learn")" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# JOURNAL
# ─────────────────────────────────────────────────────────────────────────────

_spark_journal_route() {
  local cmd="${1:-open}"
  # If arg looks like a date, treat it as a date override
  if [[ "$cmd" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    _spark_journal_open "$cmd"; return 0
  fi
  case "$cmd" in
    view)  shift; _spark_journal_view ;;
    list)  _spark_journal_list ;;
    new)   _spark_journal_new ;;
    ""|open) _spark_journal_open ;;
    *)     _spark_journal_open ;;
  esac
}

_spark_journal_open() {
  local date_target="${1:-$(_db_today)}"
  local journal_file="$_FLAT_JOURNAL_DIR/${date_target}.md"
  local editor="${EDITOR:-${VISUAL:-nano}}"

  # Create with template if it doesn't exist
  if [[ ! -f "$journal_file" ]]; then
    local eq_str; eq_str="$(_eq_for_date "$date_target" | awk -F'\t' \
      '{printf "Cycle %s · Day %s · %s", $2, $3, $4}')"
    local today_tasks=""
    if [[ "$date_target" == "$(_db_today)" ]]; then
      today_tasks="$(awk -F'\t' 'NR>1 && $3=="today" {printf "- [ ] %s\n", $2}' \
        "$_FLAT_SCOPE_TASKS" 2>/dev/null | head -5 || true)"
    fi

    cat > "$journal_file" <<TEMPLATE
# Journal — $date_target
**Equicycle:** $eq_str

## Morning
_What is the intention for today?_


## Notes
${today_tasks:+### Today's tasks
$today_tasks
}

## Evening
_What happened? What am I grateful for?_


TEMPLATE
  fi

  # Offer to expand on yesterday's reflection if available
  local yesterday; yesterday="$(python3 -c \
    "from datetime import date, timedelta; print(str(date.fromisoformat('$date_target') - timedelta(1)))" \
    2>/dev/null || true)"
  local reflect_file="$_FLAT_SCOPE_REFLECTIONS_DIR/${yesterday}.md"
  if [[ -f "$reflect_file" && ! -s "${journal_file}.expanded" ]]; then
    _ui_info "Yesterday's reflection is available to expand into this entry." >&2
    if _ui_confirm "Append it as context?" "n"; then
      printf '\n\n---\n## From Yesterday'\''s Scope Reflection\n' >> "$journal_file"
      cat "$reflect_file" >> "$journal_file"
      touch "${journal_file}.expanded"  # mark so we don't offer again
    fi
  fi

  "$editor" "$journal_file"
  local wc; wc="$(wc -w < "$journal_file" 2>/dev/null || echo 0)"
  _ui_ok "Journal saved — $wc words  ($date_target)"
}

_spark_journal_view() {
  local today; today="$(_db_today)"
  local journal_file="$_FLAT_JOURNAL_DIR/${today}.md"
  if [[ -f "$journal_file" ]]; then
    cat "$journal_file" >&2
  else
    _ui_info "No journal entry for today. Run: sconlx journal" >&2
  fi
}

_spark_journal_list() {
  printf '\n  JOURNAL ENTRIES\n' >&2
  _ui_hr
  if [[ -d "$_FLAT_JOURNAL_DIR" ]]; then
    find "$_FLAT_JOURNAL_DIR" -name "*.md" | sort -r | head -30 | \
    while IFS= read -r f; do
      local date_str; date_str="$(basename "$f" .md)"
      local wc; wc="$(wc -w < "$f" 2>/dev/null | tr -d ' ')"
      printf '  %-12s  %s words\n' "$date_str" "$wc" >&2
    done
  else
    _ui_info "No entries yet." >&2
  fi
  printf '\n' >&2
}

_spark_journal_new() {
  local editor="${EDITOR:-${VISUAL:-nano}}"
  local eq_str; eq_str="$(_eq_today_short)"
  local timestamp; timestamp="$(date +%Y%m%d_%H%M%S)"
  local note_file="$_FLAT_JOURNAL_DIR/free_${timestamp}.md"
  cat > "$note_file" <<TEMPLATE
# Free Entry — $(_db_today)
**Equicycle:** $eq_str

TEMPLATE
  "$editor" "$note_file"
  _ui_ok "Entry saved: $note_file"
}

_spark_journal_streak() {
  # Count consecutive days with journal entries ending today
  local streak=0
  local check_date; check_date="$(_db_today)"
  while true; do
    local check_file="$_FLAT_JOURNAL_DIR/${check_date}.md"
    [[ -f "$check_file" ]] || break
    (( ++streak ))
    check_date="$(python3 -c \
      "from datetime import date, timedelta; print(str(date.fromisoformat('$check_date') - timedelta(1)))" \
      2>/dev/null || break)"
    [[ $streak -ge 365 ]] && break  # safety cap
  done
  printf '%d' "$streak"
}

# ─────────────────────────────────────────────────────────────────────────────
# NOTES
# ─────────────────────────────────────────────────────────────────────────────

_spark_note_route() {
  case "${1:-capture}" in
    list)  _spark_note_list ;;
    *)     _spark_note_capture "$*" ;;
  esac
}

_spark_note_capture() {
  local title_hint="$1"
  local timestamp; timestamp="$(date +%Y%m%d_%H%M%S)"
  local editor="${EDITOR:-${VISUAL:-nano}}"

  # Fast path: if title provided, create note immediately
  if [[ -n "$title_hint" ]]; then
    local slug; slug="$(printf '%s' "$title_hint" | tr ' ' '_' | tr -cd '[:alnum:]_-' | cut -c1-40)"
    local note_file="$_FLAT_NOTES_DIR/${timestamp}_${slug}.md"
    cat > "$note_file" <<TEMPLATE
# $title_hint
*Created: $(_db_today) — $(_eq_today_short)*

TEMPLATE
    "$editor" "$note_file"
    _ui_cap "Note saved: $note_file"
    return 0
  fi

  # Interactive
  local title; title="$(_ui_prompt "Note title")"
  [[ -z "$title" ]] && { _ui_warn "No title." >&2; return 0; }
  local slug; slug="$(printf '%s' "$title" | tr ' ' '_' | tr -cd '[:alnum:]_-' | cut -c1-40)"
  local note_file="$_FLAT_NOTES_DIR/${timestamp}_${slug}.md"

  cat > "$note_file" <<TEMPLATE
# $title
*Created: $(_db_today) — $(_eq_today_short)*

TEMPLATE
  "$editor" "$note_file"
  _ui_cap "Note saved: $note_file"
}

_spark_note_list() {
  printf '\n  NOTES\n' >&2
  _ui_hr
  if [[ -d "$_FLAT_NOTES_DIR" ]]; then
    find "$_FLAT_NOTES_DIR" -name "*.md" | sort -r | head -20 | \
    while IFS= read -r f; do
      local name; name="$(basename "$f" .md)"
      local first_line; first_line="$(head -1 "$f" 2>/dev/null | sed 's/^# //')"
      printf '  %-25s  %s\n' "$name" "$first_line" >&2
    done
  else
    _ui_info "No notes yet." >&2
  fi
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# IDEAS
# ─────────────────────────────────────────────────────────────────────────────

_spark_idea_route() {
  case "${1:-list}" in
    list)    shift; _spark_idea_list "$@" ;;
    add)     shift; _spark_idea_add "$*" ;;
    show)    shift; _spark_idea_show "$1" ;;
    develop) shift; _spark_idea_develop "$1" ;;
    advance) shift; _spark_idea_advance "$1" ;;
    export)  shift; _spark_idea_export "$1" ;;
    archive) shift; _spark_idea_archive "$1" ;;
    *)       _spark_idea_list ;;
  esac
}

_spark_idea_list() {
  local filter="${1:-}"
  printf '\n  %s  IDEA PIPELINE\n' "Ideas" >&2
  _ui_hr

  local total; total="$(_tsv_count "$_FLAT_SPARK_IDEAS" '$2!="archived" && $2!="exported"')"
  if [[ "${total:-0}" -eq 0 ]]; then
    printf '  %s\n\n' "$(_ui_dim "No ideas yet. Add one: sconlx spark idea add \"Your idea\"")" >&2
    return 0
  fi

  # TSV header: ID(1) STAGE(2) TYPE(3) BODY(4) TITLE(5) CREATED_AT(6) UPDATED_AT(7)
  local stage
  for stage in captured developing refined decided; do
    local count; count="$(_tsv_count "$_FLAT_SPARK_IDEAS" "\$2==\"$stage\"")"
    [[ "${count:-0}" -eq 0 ]] && continue
    printf '\n  %s\n' "$(_ui_bold "${stage^^} ($count)")" >&2
    awk -F'\t' -v s="$stage" '
      NR>1 && $2==s {
        badge = (s=="captured") ? "○" : "→"
        printf "  %-8s  %s  %s\n", $1, badge, substr($5, 1, 48)
        if (++n >= 5) exit
      }' "$_FLAT_SPARK_IDEAS" >&2 || true
  done

  local stale; stale="$(_spark_stale_ideas_count)"
  [[ "${stale:-0}" -gt 0 ]] && \
    printf '\n  %s  %s idea(s) in Captured >%sd\n' \
      "$(_ui_yellow "⚠")" "$stale" "$_SPARK_IDEA_REVIEW_DAYS" >&2

  printf '\n  %s\n\n' "$(_ui_dim "sconlx spark idea add <text>  ·  develop <id>  ·  advance <id>")" >&2
}

_spark_idea_add() {
  local title="$1"
  [[ -z "$title" ]] && title="$(_ui_prompt "Idea")"
  [[ -z "$title" ]] && { _ui_warn "No idea given." >&2; return 0; }

  local id; id="$(_db_next_id "I" "$_FLAT_SPARK_IDEAS")"
  local now; now="$(_db_today)"
  # Header: ID STAGE TYPE BODY TITLE CREATED_AT UPDATED_AT
  printf '%s\tcaptured\tgeneral\t\t%s\t%s\t%s\n' \
    "$id" "$(_tsv_safe "$title")" "$now" "$now" \
    >> "$_FLAT_SPARK_IDEAS"

  _ui_cap "Idea $id captured: $title"
  _ui_info "Develop it: sconlx spark idea develop $id" >&2
}

_spark_idea_show() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark idea show <id>" >&2; return 1; }
  awk -F'\t' -v id="$id" 'NR>1 && $1==id {
    printf "\n  ID:       %s\n", $1
    printf "  Title:    %s\n", $5
    printf "  Stage:    %s\n", $2
    printf "  Type:     %s\n", $3
    printf "  Body:     %s\n", substr($4,1,80)
    printf "  Created:  %s\n\n", $6
  }' "$_FLAT_SPARK_IDEAS" >&2 || true
}

_spark_idea_develop() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark idea develop <id>" >&2; return 1; }
  if ! _tsv_exists "$_FLAT_SPARK_IDEAS" "$id"; then
    _ui_err "Idea $id not found." >&2; return 1
  fi
  local title; title="$(_tsv_get "$_FLAT_SPARK_IDEAS" "$id" 5)"

  printf '\n  DEVELOP: %s\n' "$(_ui_bold "$title")" >&2
  _ui_hr
  printf '  %s\n\n' "$(_ui_dim "Answer these to clarify your thinking.")" >&2

  printf '  %s\n' "$(_ui_bold "1. What problem does this solve?")" >&2
  local a1; a1="$(_ui_prompt "  >")"

  printf '\n  %s\n' "$(_ui_bold "2. Who is it for?")" >&2
  local a2; a2="$(_ui_prompt "  >")"

  printf '\n  %s\n' "$(_ui_bold "3. What's the simplest version of this?")" >&2
  local a3; a3="$(_ui_prompt "  >")"

  # Store development notes as a file alongside the ideas TSV
  local dev_file="$_FLAT_SPARK_DIR/idea_${id}_dev.md"
  cat > "$dev_file" <<DEV
# Idea Development: $title ($id)
*Updated: $(_db_today)*

## Problem it solves
$a1

## Who it's for
$a2

## Simplest version
$a3
DEV

  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 2 "developing"
  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 7 "$(_db_today)"

  _ui_cap "Development notes saved. Idea advanced to 'developing' stage."
  _ui_info "Next: sconlx spark idea advance $id  when ready to refine" >&2
}

_spark_idea_advance() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark idea advance <id>" >&2; return 1; }

  local current_stage; current_stage="$(_tsv_get "$_FLAT_SPARK_IDEAS" "$id" 2)"
  local title; title="$(_tsv_get "$_FLAT_SPARK_IDEAS" "$id" 5)"

  # Determine next stage
  local next_stage=""
  case "$current_stage" in
    captured)   next_stage="developing" ;;
    developing) next_stage="refined" ;;
    refined)    next_stage="decided" ;;
    decided)    next_stage="exported" ;;
    *)          _ui_warn "Idea is already at stage: $current_stage" >&2; return 0 ;;
  esac

  _ui_confirm "Advance '$(_ui_truncate "$title" 40)' from $current_stage → $next_stage?" "y" || return 0
  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 2 "$next_stage"
  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 7 "$(_db_today)"
  _ui_cap "$id: $current_stage → $next_stage"
}

_spark_idea_export() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark idea export <id>" >&2; return 1; }
  local title; title="$(_tsv_get "$_FLAT_SPARK_IDEAS" "$id" 5)"

  printf '\n  EXPORT IDEA: %s\n' "$title" >&2
  local dest
  dest="$(_ui_menu "Export to" "Scope (create goal)" "Space (create project)")"

  case "$dest" in
    *Scope*)
      _ev_write "spark.idea.promoted_to_scope" \
        "{\"idea_id\":\"$id\",\"idea_title\":\"$title\"}"
      _ui_info "Creating goal from idea..." >&2
      _scope_goal_add_from_inbox "$id" "$title"
      ;;
    *Space*)
      _ev_write "spark.idea.promoted_to_space" \
        "{\"idea_id\":\"$id\",\"idea_title\":\"$title\"}"
      _ui_info "Add to a space project: sconlx space project add <space>" >&2
      ;;
  esac

  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 2 "exported"
  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 7 "$(_db_today)"
  _ui_cap "Idea $id exported."
}

_spark_idea_archive() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark idea archive <id>" >&2; return 1; }
  local title; title="$(_tsv_get "$_FLAT_SPARK_IDEAS" "$id" 5)"
  local reason; reason="$(_ui_prompt "Why archiving? (required)")"
  [[ -z "$reason" ]] && { _ui_warn "Reason required to archive an idea." >&2; return 0; }

  _tsv_update_field "$_FLAT_SPARK_IDEAS" "$id" 2 "archived"
  _ui_ok "Idea archived: $title ($reason)" >&2
}

_spark_stale_ideas_count() {
  [[ -f "$_FLAT_SPARK_IDEAS" ]] || { printf '0'; return 0; }
  local today; today="$(_db_today)"
  awk -F'\t' -v today="$today" -v warn="$_SPARK_IDEA_REVIEW_DAYS" '
    NR>1 && $2=="captured" {
      cmd="python3 -c \"from datetime import date; print((date.fromisoformat('"'"'"today"'"'"') - date.fromisoformat('"'"'"$6"'"'"')).days)\" 2>/dev/null"
      cmd | getline d; close(cmd)
      if (d+0 > warn) count++
    }
    END {print count+0}
  ' "$_FLAT_SPARK_IDEAS" 2>/dev/null || printf '0'
}

# ─────────────────────────────────────────────────────────────────────────────
# LEARNING
# ─────────────────────────────────────────────────────────────────────────────

_spark_learn_route() {
  case "${1:-list}" in
    list)        shift; _spark_learn_list "$@" ;;
    add)         _spark_learn_add ;;
    show)        shift; _spark_learn_show "$1" ;;
    progress)    shift; _spark_learn_progress "$1" "$2" ;;
    highlight)   shift; _spark_learn_highlight "$1" ;;
    done)        shift; _spark_learn_done "$1" ;;
    synthesise|synthesize) shift; _spark_learn_synthesise "$1" ;;
    *)           _spark_learn_list ;;
  esac
}

_spark_learn_list() {
  local filter="${1:-}"
  printf '\n  %s  LEARNING LIBRARY\n' "Learning" >&2
  _ui_hr

  local active_count; active_count="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$3=="active"')"
  [[ "$active_count" -gt 0 ]] && {
    printf '\n  %s\n' "$(_ui_bold "ACTIVE ($active_count)")" >&2
    awk -F'\t' 'NR>1 && $3=="active" {
      bar=""
      pct=$5+0
      for(i=1;i<=12;i++) bar=bar (i<=int(pct/100*12)?"█":"░")
      printf "  %-8s  %-30s  %s  %d%%\n", $1, substr($2,1,30), bar, pct
    }' "$_FLAT_SPARK_LEARNING" >&2 || true
  }

  local backlog_count; backlog_count="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$3=="backlog"')"
  [[ "$backlog_count" -gt 0 ]] && \
    printf '\n  %s\n' "$(_ui_dim "BACKLOG ($backlog_count)  — sconlx spark learn list --all")" >&2

  local done_count; done_count="$(_tsv_count "$_FLAT_SPARK_LEARNING" '$3=="completed" || $3=="synthesised"')"
  [[ "$done_count" -gt 0 ]] && \
    printf '  %s\n' "$(_ui_dim "COMPLETED/SYNTHESISED: $done_count")" >&2

  printf '\n  %s\n\n' "$(_ui_dim "sconlx spark learn add  ·  progress <id> <pct>  ·  done <id>")" >&2
}

_spark_learn_add() {
  printf '\n  ADD RESOURCE\n' >&2
  _ui_hr

  local title; title="$(_ui_prompt "Title")"
  [[ -z "$title" ]] && { _ui_warn "No title." >&2; return 0; }
  local author; author="$(_ui_prompt "Author/source (optional)" "")"
  local type
  type="$(_ui_menu "Type" "book" "course" "article" "video" "podcast" "other")"

  local id; id="$(_db_next_id "L" "$_FLAT_SPARK_LEARNING")"
  printf '%s\t%s\t%s\tbacklog\t0\t%s\t%s\t%s\n' \
    "$id" "$(_tsv_safe "$title")" "$type" "$(_tsv_safe "$author")" \
    "$(_db_today)" "$(_db_today)" \
    >> "$_FLAT_SPARK_LEARNING"

  _ui_cap "Resource $id: $title"
  _ui_confirm "Mark as active (start now)?" "n" && {
    _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 4 "active"
    _ui_ok "Started: $title" >&2
  } || true
}

_spark_learn_show() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark learn show <id>" >&2; return 1; }
  awk -F'\t' -v id="$id" 'NR>1 && $1==id {
    printf "\n  %-12s  %s\n", "ID:", $1
    printf "  %-12s  %s\n", "Title:", $2
    printf "  %-12s  %s\n", "Type:", $3
    printf "  %-12s  %s\n", "Status:", $4
    printf "  %-12s  %d%%\n", "Progress:", $5+0
    printf "  %-12s  %s\n", "Author:", $6
    printf "  %-12s  %s\n\n", "Added:", $7
  }' "$_FLAT_SPARK_LEARNING" >&2 || true

  # Show highlights file if it exists
  local hl_file="$_FLAT_SPARK_DIR/learn_${id}_highlights.md"
  [[ -f "$hl_file" ]] && {
    printf '  %s\n' "$(_ui_bold "Highlights:")" >&2
    cat "$hl_file" >&2
  }
}

_spark_learn_progress() {
  local id="$1" pct="$2"
  [[ -z "$id" || -z "$pct" ]] && {
    _ui_err "Usage: sconlx spark learn progress <id> <percentage>" >&2; return 1
  }
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 5 "$pct"
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 4 "active"
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 8 "$(_db_today)"
  local title; title="$(_tsv_get "$_FLAT_SPARK_LEARNING" "$id" 2)"
  _ui_cap "$title: $pct%"
}

_spark_learn_highlight() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark learn highlight <id>" >&2; return 1; }
  local hl_file="$_FLAT_SPARK_DIR/learn_${id}_highlights.md"
  [[ ! -f "$hl_file" ]] && printf '# Highlights\n\n' > "$hl_file"
  local quote; quote="$(_ui_prompt "Quote or highlight")"
  [[ -z "$quote" ]] && return 0
  local note; note="$(_ui_prompt "Personal note (optional)" "")"
  printf '> %s\n' "$quote" >> "$hl_file"
  [[ -n "$note" ]] && printf '_%s_\n' "$note" >> "$hl_file"
  printf '\n' >> "$hl_file"
  _ui_cap "Highlight saved."
}

_spark_learn_done() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark learn done <id>" >&2; return 1; }
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 4 "completed"
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 5 "100"
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 8 "$(_db_today)"
  local title; title="$(_tsv_get "$_FLAT_SPARK_LEARNING" "$id" 2)"
  _ui_cap "Completed: $title"
  _ev_write "spark.learning.completed" "{\"id\":\"$id\",\"title\":\"$title\"}"
  _ui_info "Consider synthesising: sconlx spark learn synthesise $id" >&2
}

_spark_learn_synthesise() {
  local id="$1"
  [[ -z "$id" ]] && { _ui_err "Usage: sconlx spark learn synthesise <id>" >&2; return 1; }
  local title; title="$(_tsv_get "$_FLAT_SPARK_LEARNING" "$id" 2)"
  local editor="${EDITOR:-${VISUAL:-nano}}"
  local syn_file="$_FLAT_SPARK_DIR/learn_${id}_synthesis.md"

  if [[ ! -f "$syn_file" ]]; then
    cat > "$syn_file" <<SYN
# Synthesis: $title
*Date: $(_db_today)*

## Core ideas
_What are the 3 most important things you learned?_


## How I'll apply this
_What will you actually do differently?_


## Key quote or passage
_The line that stuck with you most._


SYN
  fi

  "$editor" "$syn_file"
  _tsv_update_field "$_FLAT_SPARK_LEARNING" "$id" 4 "synthesised"
  _ui_cap "Synthesis saved: $title"
}

# ─────────────────────────────────────────────────────────────────────────────
# DIA — Deep Intelligence Archive
# CLI shows only unencrypted fields: name, role, type, last contact.
# All encrypted content is ONLY accessible through the Spark Flutter app.
# This is by design — the terminal is not a secure environment for DIA content.
# ─────────────────────────────────────────────────────────────────────────────

_spark_dia_route() {
  case "${1:-list}" in
    list)    _spark_dia_list ;;
    show)    shift; _spark_dia_show "$1" ;;
    overdue) _spark_dia_overdue ;;
    add)     _spark_dia_add ;;
    log)     shift; _spark_dia_log "$1" ;;
    *)       _spark_dia_list ;;
  esac
}

_spark_dia_list() {
  local total; total="$(_tsv_count "$_FLAT_SPARK_DIA")"
  printf '\n  %s  DIA PROFILES  (%s)\n' "DIA" "$total" >&2
  printf '  %s\n' "$(_ui_dim "(Names and contact metadata only — full profiles in Spark app)")" >&2
  _ui_hr

  if [[ "$total" -eq 0 ]]; then
    _ui_info "No DIA profiles yet. Add one: sconlx spark dia add" >&2
    printf '\n' >&2; return 0
  fi

  awk -F'\t' 'NR>1 {
    printf "  %-10s  %-20s  %-15s  %-12s  %s\n",
      $1, substr($2,1,20), $4, $3, $6
  }' "$_FLAT_SPARK_DIA" >&2 || true

  local overdue; overdue="$(_spark_dia_overdue_count)"
  [[ "$overdue" -gt 0 ]] && \
    printf '\n  %s  %s overdue for interaction\n' "$(_ui_yellow "⚠")" "$overdue" >&2

  printf '\n  %s\n\n' "$(_ui_dim "sconlx spark dia overdue  ·  sconlx spark dia log <name>")" >&2
}

_spark_dia_show() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx spark dia show <name|id>" >&2; return 1; }
  awk -F'\t' -v q="${query,,}" '
    NR>1 && (tolower($1)==q || tolower($2)~q) {
      printf "\n  ID:            %s\n", $1
      printf "  Name:          %s\n", $2
      printf "  Role:          %s\n", $3
      printf "  Type:          %s\n", $4
      printf "  Depth:         %s\n", $5
      printf "  Last contact:  %s\n", $6
      printf "  Trajectory:    %s\n", $7
      printf "  Added:         %s\n", $8
      printf "\n  Full profile available in Spark app (encrypted).\n\n"
      exit
    }' "$_FLAT_SPARK_DIA" >&2 || true
}

_spark_dia_overdue() {
  printf '\n  DIA OVERDUE\n' >&2
  _ui_hr
  local today; today="$(_db_today)"
  awk -F'\t' -v today="$today" -v warn="$_SPARK_DIA_OVERDUE_DAYS" '
    NR>1 && $6!="-" && $6!="" {
      cmd="python3 -c \"from datetime import date; print((date.fromisoformat('"'"'"today"'"'"') - date.fromisoformat('"'"'"$6"'"'"')).days)\" 2>/dev/null"
      cmd | getline d; close(cmd)
      if (d+0 > warn)
        printf "  %-10s  %-20s  %-15s  %dd ago\n", $1, substr($2,1,20), $4, d+0
    }' "$_FLAT_SPARK_DIA" >&2 || true
  printf '\n' >&2
}

_spark_dia_add() {
  printf '\n  ADD DIA PROFILE\n' >&2
  _ui_hr
  printf '  %s\n\n' "$(_ui_dim "Only name, role, and relationship type stored in CLI. Full profile in Spark app.")" >&2

  local name; name="$(_ui_prompt "Name")"
  [[ -z "$name" ]] && { _ui_warn "No name." >&2; return 0; }
  local role; role="$(_ui_prompt "Role / position" "")"
  local type
  type="$(_ui_menu "Relationship type" "mentor" "peer" "client" "partner" "collaborator" "friend" "advisor")"
  local depth
  depth="$(_ui_menu "Relationship depth" "strategic" "working" "acquaintance")"

  local id; id="$(_db_next_id "D" "$_FLAT_SPARK_DIA")"
  printf '%s\t%s\t%s\t%s\t%s\t-\tnew\t%s\n' \
    "$id" "$(_tsv_safe "$name")" "$(_tsv_safe "$role")" \
    "$type" "$depth" "$(_db_today)" \
    >> "$_FLAT_SPARK_DIA"

  _ui_cap "DIA profile $id: $name"
  _ui_info "For full profile management, use the Spark app." >&2
}

_spark_dia_log() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx spark dia log <name|id>" >&2; return 1; }

  local row
  row="$(awk -F'\t' -v q="${query,,}" \
    'NR>1 && (tolower($1)==q || tolower($2)~q) {print; exit}' \
    "$_FLAT_SPARK_DIA" 2>/dev/null || true)"
  [[ -z "$row" ]] && { _ui_err "Profile not found: $query" >&2; return 1; }

  local id name
  IFS=$'\t' read -r id name _ _ _ _ _ _ <<< "$row"

  printf '\n  LOG INTERACTION: %s\n' "$name" >&2
  _ui_hr

  local channel
  channel="$(_ui_menu "Channel" "video" "phone" "message" "email" "in_person")"
  local brief_note; brief_note="$(_ui_prompt "Brief note (1 line — NOT stored in CLI)")"

  # Update last contact date
  _tsv_update_field "$_FLAT_SPARK_DIA" "$id" 6 "$(_db_today)"

  # Queue the note to the event bus for Spark app to encrypt
  _ev_write "sconlx.dia.interaction_queued" \
    "{\"dia_profile_id\":\"$id\",\"subject_name\":\"$name\",\"interaction_date\":\"$(_db_today)\",\"channel\":\"$channel\",\"brief_note\":\"$(_tsv_safe "$brief_note")\"}"

  _ui_cap "Interaction logged: $name"
  _ui_info "Full details queued for Spark app to encrypt." >&2
}

_spark_dia_overdue_count() {
  [[ -f "$_FLAT_SPARK_DIA" ]] || { printf '0'; return 0; }
  local today; today="$(_db_today)"
  awk -F'\t' -v today="$today" -v warn="$_SPARK_DIA_OVERDUE_DAYS" '
    NR>1 && $6!="-" && $6!="" {
      cmd="python3 -c \"from datetime import date; print((date.fromisoformat('"'"'"today"'"'"') - date.fromisoformat('"'"'"$6"'"'"')).days)\" 2>/dev/null"
      cmd | getline d; close(cmd)
      if (d+0 > warn) count++
    }
    END {print count+0}
  ' "$_FLAT_SPARK_DIA" 2>/dev/null || printf '0'
}