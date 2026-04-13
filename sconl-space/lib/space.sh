# sconl-space/lib/space.sh
# Space command handlers — domain portfolio layer.
# Covers: portfolio view, spaces (add/show/review), projects, contacts, KPIs, events.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Portfolio overview, space CRUD, KPI logging, contact
#             management, basic review flow. Flat-file + SQLite routing.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_SPACE_LOADED:-}" ]] && return 0
_SPACE_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_SPACE_REVIEW_OVERDUE_DAYS=14    # spaces not reviewed in this many days → flagged

# Space type emojis
declare -A _SPACE_TYPE_EMOJI=(
  ["business"]="🏢"
  ["platform"]="🌐"
  ["project"]="🚀"
  ["hobby"]="🎯"
  ["relationship"]="🤝"
)

# Lifecycle statuses in display order
_SPACE_LIFECYCLES=("active" "maintenance" "dormant" "emerging" "archived")

# ─────────────────────────────────────────────────────────────────────────────
# ROUTER
# ─────────────────────────────────────────────────────────────────────────────

_space_route() {
  local cmd="${1:-dashboard}"
  shift || true
  case "$cmd" in
    ""|dashboard|list)  if [[ "$cmd" == "list" ]]; then _space_list "$@"; else _space_dashboard; fi ;;
    show)               _space_show "$@" ;;
    add)                _space_add ;;
    review)             _space_review "$@" ;;
    project)            _space_project_route "$@" ;;
    task)               _space_task_route "$@" ;;
    kpi)                _space_kpi_route "$@" ;;
    contact)            _space_contact_route "$@" ;;
    event)              _space_event_route "$@" ;;
    health)             _space_health ;;
    *)                  _ui_err "Unknown space command: $cmd" >&2
                        printf '\n  Usage: sconlx space [list|show|add|review|project|kpi|contact|health]\n\n' >&2 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# PORTFOLIO DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────

_space_dashboard() {
  local eq_str; eq_str="$(_eq_today_short)"

  printf '\n  %s  SPACE PORTFOLIO  ·  %s\n' "$_UI_BADGE_SPACE" "$eq_str" >&2
  _ui_hr

  local total; total="$(_tsv_count "$_FLAT_SPACE_SPACES" '$3!="archived"')"
  if [[ "$total" -eq 0 ]]; then
    printf '\n  %s\n' "$(_ui_dim "No spaces yet.")" >&2
    _ui_info "Create your first space: sconlx space add" >&2
    printf '\n' >&2
    return 0
  fi

  # Portfolio health score (average of active spaces)
  local health_avg; health_avg="$(_space_avg_health)"
  printf '\n  Portfolio Health: %s/10  %s\n\n' \
    "$health_avg" "$(_ui_health_dots "$health_avg" 10)" >&2

  # Display each lifecycle group
  local lifecycle
  for lifecycle in active maintenance emerging dormant; do
    local count; count="$(_tsv_count "$_FLAT_SPACE_SPACES" "\$4==\"$lifecycle\"")"
    [[ "$count" -eq 0 ]] && continue
    printf '  %s\n' "$(_ui_bold "${lifecycle^^} ($count)")" >&2
    _space_list_by_lifecycle "$lifecycle"
    printf '\n' >&2
  done

  # Signals
  _space_signals

  printf '  %s\n\n' "$(_ui_dim "sconlx space show <name>  ·  sconlx space add  ·  sconlx space health")" >&2
}

_space_list_by_lifecycle() {
  local lifecycle="$1"
  [[ -f "$_FLAT_SPACE_SPACES" ]] || return 0
  awk -F'\t' -v lc="$lifecycle" '
    NR>1 && $4==lc {
      health = ($5+0 > 0) ? $5 : "-"
      emoji = length($7) > 0 ? $7 : "•"
      printf "  %s  %-22s  %-12s  %s/10  %s\n",
        emoji, substr($2,1,22), $3, health, $9
    }' "$_FLAT_SPACE_SPACES" >&2 || true
}

_space_list() {
  local filter="$1"
  printf '\n  SPACE LIST\n' >&2
  _ui_hr
  if [[ -f "$_FLAT_SPACE_SPACES" ]]; then
    awk -F'\t' -v f="$filter" '
      NR>1 && $4!="archived" && (f=="" || $4==f || $3==f) {
        printf "  %-10s  %-22s  %-12s  %-8s  %s/10\n",
          $1, substr($2,1,22), $3, $4, $5
      }' "$_FLAT_SPACE_SPACES" >&2 || true
  fi
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# SPACE SHOW
# ─────────────────────────────────────────────────────────────────────────────

_space_show() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space show <name|id>" >&2; return 1; }

  # Match by ID or name (case-insensitive partial match)
  local row
  row="$(awk -F'\t' -v q="${query,,}" \
    'NR>1 && (tolower($1)==q || tolower($2)~q) {print; exit}' \
    "$_FLAT_SPACE_SPACES" 2>/dev/null || true)"
  [[ -z "$row" ]] && { _ui_err "Space not found: $query" >&2; return 1; }

  local id name type status health desc emoji created last_reviewed
  IFS=$'\t' read -r id name type status health desc emoji created last_reviewed <<< "$row"

  local emoji_display="${emoji:-•}"
  printf '\n  %s  %s  ·  %s  ·  %s\n' "$emoji_display" "$(_ui_bold "$name")" "$type" "$status" >&2
  _ui_hr
  [[ -n "$desc" ]] && printf '  %s\n\n' "$(_ui_italic "$desc")" >&2

  printf '  Health: %s/10  %s\n' "$health" "$(_ui_health_dots "$health" 10)" >&2
  printf '  Last reviewed: %s\n' "$(_ui_days_ago "$last_reviewed")" >&2
  printf '  Created: %s\n' "$created" >&2

  # Projects
  local proj_count
  proj_count="$(_tsv_count "$_FLAT_SPACE_PROJECTS" "\$2==\"$id\" && \$4!=\"archived\"")"
  [[ "$proj_count" -gt 0 ]] && {
    printf '\n  %s\n' "$(_ui_bold "Projects ($proj_count)")" >&2
    awk -F'\t' -v sid="$id" \
      'NR>1 && $2==sid && $4!="archived" {printf "  %-10s  %-30s  %s\n", $1, substr($3,1,30), $4}' \
      "$_FLAT_SPACE_PROJECTS" >&2 || true
  }

  # KPIs
  local kpi_count
  kpi_count="$(_tsv_count "$_FLAT_SPACE_KPI_DEFS" "\$2==\"$id\"")"
  [[ "$kpi_count" -gt 0 ]] && {
    printf '\n  %s\n' "$(_ui_bold "KPIs")" >&2
    awk -F'\t' -v sid="$id" \
      'NR>1 && $2==sid {printf "  %-10s  %-25s  target: %s %s\n", $1, $3, $5, $4}' \
      "$_FLAT_SPACE_KPI_DEFS" >&2 || true
  }

  # Contacts
  local contact_count
  contact_count="$(_tsv_count "$_FLAT_SPACE_CONTACTS" "\$2==\"$id\"")"
  [[ "$contact_count" -gt 0 ]] && {
    printf '\n  %s\n' "$(_ui_bold "Contacts ($contact_count)")" >&2
    awk -F'\t' -v sid="$id" \
      'NR>1 && $2==sid {printf "  %-10s  %-20s  %-15s  last: %s\n", $1, $3, $4, $5}' \
      "$_FLAT_SPACE_CONTACTS" >&2 || true
  }

  printf '\n  %s\n\n' "$(_ui_dim "sconlx space kpi $id  ·  sconlx space review $id  ·  sconlx space contact $id")" >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# ADD SPACE
# ─────────────────────────────────────────────────────────────────────────────

_space_add() {
  printf '\n  ADD SPACE\n' >&2
  _ui_hr
  printf '  %s\n\n' "$(_ui_dim "A Space is any domain of your life: a business, project, hobby, platform, or relationship.")" >&2

  local name; name="$(_ui_prompt "Name")"
  [[ -z "$name" ]] && { _ui_warn "No name given." >&2; return 0; }

  local type
  type="$(_ui_menu "Type" "business" "project" "platform" "hobby" "relationship")"

  local desc; desc="$(_ui_prompt "One-line description (optional)" "")"
  local health; health="$(_ui_prompt "Initial health score (1-10)" "5")"
  local emoji; emoji="${_SPACE_TYPE_EMOJI[$type]:-•}"

  local id; id="$(_db_next_id "SP" "$_FLAT_SPACE_SPACES")"
  local now; now="$(_db_today)"

  printf '%s\t%s\t%s\tactive\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$(_tsv_safe "$name")" "$type" "$health" \
    "$(_tsv_safe "$desc")" "$emoji" "$now" "$now" \
    >> "$_FLAT_SPACE_SPACES"

  _ui_cap "Space $id created: $name ($type)"

  # Prompt to add initial KPIs
  _ui_confirm "Add a KPI for this space now?" "y" && _space_kpi_add "$id" || true
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# REVIEW
# ─────────────────────────────────────────────────────────────────────────────

_space_review() {
  local query="$1"
  if [[ "$query" == "--all" ]]; then
    _space_review_all; return 0
  fi
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space review <name|id>" >&2; return 1; }

  local row
  row="$(awk -F'\t' -v q="${query,,}" \
    'NR>1 && (tolower($1)==q || tolower($2)~q) {print; exit}' \
    "$_FLAT_SPACE_SPACES" 2>/dev/null || true)"
  [[ -z "$row" ]] && { _ui_err "Space not found: $query" >&2; return 1; }

  local id name type
  IFS=$'\t' read -r id name type _ _ _ _ _ _ <<< "$row"

  printf '\n  REVIEW: %s  (%s)\n' "$(_ui_bold "$name")" "$type" >&2
  _ui_hr

  local q1; q1="$(_ui_prompt "What's going well?")"
  local q2; q2="$(_ui_prompt "What needs attention?")"
  local health; health="$(_ui_prompt "Health score (1-10)" "7")"

  _tsv_update_field "$_FLAT_SPACE_SPACES" "$id" 5 "$health"
  _tsv_update_field "$_FLAT_SPACE_SPACES" "$id" 9 "$(_db_today)"

  # Log the review event
  _db_init_tsv "$_FLAT_SPACE_EVENTS" "ID\tSPACE_ID\tTYPE\tTITLE\tEVENT_DATE"
  local ev_id; ev_id="$(_db_next_id "EV" "$_FLAT_SPACE_EVENTS")"
  printf '%s\t%s\treview\tPeriodic review\t%s\n' \
    "$ev_id" "$id" "$(_db_today)" >> "$_FLAT_SPACE_EVENTS"

  _ev_write "space.review.completed" "{\"space_id\":\"$id\",\"health\":$health}"
  _ui_cap "Review saved. Health: $health/10"
}

_space_review_all() {
  local today; today="$(_db_today)"
  printf '\n  REVIEWING ALL OVERDUE SPACES\n' >&2
  _ui_hr

  local reviewed=0
  while IFS=$'\t' read -r id name type status health desc emoji created last_reviewed; do
    [[ -z "$id" ]] && continue
    _ui_info "Reviewing: $name" >&2
    _space_review "$id"
    (( ++reviewed ))
    printf '\n' >&2
  done < <(awk -F'\t' -v today="$today" '
    NR>1 && $4!="archived" {
      # Show spaces not reviewed in 14 days
      if ($9=="" || $9=="-") print
      else {
        cmd="python3 -c \"from datetime import date; print((date.fromisoformat('" today "') - date.fromisoformat('" $9 "')).days)\" 2>/dev/null"
        cmd | getline d; close(cmd)
        if (d+0 > 14) print
      }
    }' "$_FLAT_SPACE_SPACES" 2>/dev/null)

  [[ $reviewed -eq 0 ]] && _ui_ok "All spaces are up to date." >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# PROJECTS
# ─────────────────────────────────────────────────────────────────────────────

_space_project_route() {
  case "${1:-list}" in
    list)  shift; _space_project_list "$@" ;;
    add)   shift; _space_project_add "$@" ;;
    *)     _space_project_list ;;
  esac
}

_space_project_list() {
  local query="$1"
  printf '\n  SPACE PROJECTS\n' >&2
  _ui_hr
  if [[ -n "$query" ]]; then
    local space_id; space_id="$(_space_resolve_id "$query")"
    awk -F'\t' -v sid="$space_id" \
      'NR>1 && $2==sid && $4!="archived" {printf "  %-10s  %-30s  %s\n", $1, substr($3,1,30), $4}' \
      "$_FLAT_SPACE_PROJECTS" >&2 || true
  else
    awk -F'\t' 'NR>1 && $4!="archived" {printf "  %-10s  %-30s  %-12s  %s\n", $1, substr($3,1,30), $4, $2}' \
      "$_FLAT_SPACE_PROJECTS" >&2 || true
  fi
  printf '\n' >&2
}

_space_project_add() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space project add <space-name|id>" >&2; return 1; }
  local space_id; space_id="$(_space_resolve_id "$query")"
  [[ -z "$space_id" ]] && { _ui_err "Space not found: $query" >&2; return 1; }

  local title; title="$(_ui_prompt "Project title")"
  [[ -z "$title" ]] && { _ui_warn "No title." >&2; return 0; }

  local id; id="$(_db_next_id "P" "$_FLAT_SPACE_PROJECTS")"
  printf '%s\t%s\t%s\tactive\t%s\n' \
    "$id" "$space_id" "$(_tsv_safe "$title")" "$(_db_today)" \
    >> "$_FLAT_SPACE_PROJECTS"
  _ui_cap "Project $id: $title"
}

# ─────────────────────────────────────────────────────────────────────────────
# SPACE TASKS (push to Scope)
# ─────────────────────────────────────────────────────────────────────────────

_space_task_route() {
  case "${1:-list}" in
    list) shift; _space_task_list "$@" ;;
    add)  shift; _space_task_add "$@" ;;
    *)    _ui_err "Usage: sconlx space task [list|add] <project-id>" >&2 ;;
  esac
}

_space_task_add() {
  local project_id="$1"
  [[ -z "$project_id" ]] && { _ui_err "Usage: sconlx space task add <project-id>" >&2; return 1; }

  local title; title="$(_ui_prompt "Task title")"
  [[ -z "$title" ]] && { _ui_warn "No title." >&2; return 0; }

  # Find space name for the event
  local space_id; space_id="$(_tsv_get "$_FLAT_SPACE_PROJECTS" "$project_id" 2)"
  local space_name; space_name="$(_tsv_get "$_FLAT_SPACE_SPACES" "$space_id" 2)"
  local proj_name; proj_name="$(_tsv_get "$_FLAT_SPACE_PROJECTS" "$project_id" 3)"

  # Add to Scope tasks directly
  local scope_id; scope_id="$(_db_next_id "T" "$_FLAT_SCOPE_TASKS")"
  local now; now="$(_db_today)"
  printf '%s\t%s\tbacklog\tmed\t%s\t0\t-\tmedium\t%s\t%s\n' \
    "$scope_id" "$(_tsv_safe "$title")" "$project_id" "$now" "$now" \
    >> "$_FLAT_SCOPE_TASKS"

  _ev_write "space.task.created" \
    "{\"task_title\":\"$title\",\"project_title\":\"$proj_name\",\"space_name\":\"$space_name\"}"
  _ui_cap "Task $scope_id → Scope: $title"
  _ui_info "Visible in: sconlx scope task list" >&2
}

_space_task_list() {
  local project_id="$1"
  [[ -z "$project_id" ]] && { _ui_err "Usage: sconlx space task list <project-id>" >&2; return 1; }
  printf '\n  Tasks in project %s\n' "$project_id" >&2
  _ui_hr
  awk -F'\t' -v pid="$project_id" \
    'NR>1 && $5==pid {printf "  %-8s  %-35s  %s\n", $1, substr($2,1,35), $3}' \
    "$_FLAT_SCOPE_TASKS" >&2 || true
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# KPIs
# ─────────────────────────────────────────────────────────────────────────────

_space_kpi_route() {
  case "${1:-list}" in
    log)  shift; _space_kpi_log "$@" ;;
    list) shift; _space_kpi_list "$@" ;;
    add)  shift; _space_kpi_add "$@" ;;
    *)    shift; _space_kpi_list "$@" ;;
  esac
}

_space_kpi_add() {
  local space_id="$1"
  [[ -z "$space_id" ]] && space_id="$(_space_pick_space)"
  [[ -z "$space_id" ]] && return 0

  local name; name="$(_ui_prompt "KPI name (e.g. 'Monthly Revenue')")"
  [[ -z "$name" ]] && return 0
  local unit; unit="$(_ui_prompt "Unit (e.g. KES, clients, hours)" "")"
  local target; target="$(_ui_prompt "Target value" "")"

  local id; id="$(_db_next_id "K" "$_FLAT_SPACE_KPI_DEFS")"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$space_id" "$(_tsv_safe "$name")" "$unit" "$target" \
    >> "$_FLAT_SPACE_KPI_DEFS"
  _ui_cap "KPI $id: $name"
}

_space_kpi_log() {
  local query="$1" kpi_name="$2" value="$3"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space kpi log <space> <kpi-name> <value>" >&2; return 1; }

  local space_id; space_id="$(_space_resolve_id "$query")"
  [[ -z "$space_id" ]] && { _ui_err "Space not found: $query" >&2; return 1; }

  if [[ -z "$kpi_name" || -z "$value" ]]; then
    # Interactive
    printf '\n  KPI LOG  —  %s\n' "$query" >&2
    _ui_hr
    printf '  %s\n' "$(_ui_bold "Available KPIs:")" >&2
    awk -F'\t' -v sid="$space_id" 'NR>1 && $2==sid {printf "  %s  %s (%s)\n", $1, $3, $4}' \
      "$_FLAT_SPACE_KPI_DEFS" >&2 || true
    kpi_name="$(_ui_prompt "KPI name")"
    value="$(_ui_prompt "Value")"
  fi

  # Find the KPI ID
  local kpi_id kpi_unit
  IFS=$'\t' read -r kpi_id _ _ kpi_unit _ < <(
    awk -F'\t' -v sid="$space_id" -v k="${kpi_name,,}" \
      'NR>1 && $2==sid && tolower($3)~k {print; exit}' "$_FLAT_SPACE_KPI_DEFS" 2>/dev/null || true
  )

  if [[ -z "$kpi_id" ]]; then
    # KPI doesn't exist — offer to create it
    _ui_warn "KPI '$kpi_name' not found for this space." >&2
    _ui_confirm "Create it?" "y" && {
      kpi_id="$(_db_next_id "K" "$_FLAT_SPACE_KPI_DEFS")"
      local unit; unit="$(_ui_prompt "Unit" "")"
      printf '%s\t%s\t%s\t%s\t0\n' "$kpi_id" "$space_id" "$(_tsv_safe "$kpi_name")" "$unit" \
        >> "$_FLAT_SPACE_KPI_DEFS"
    } || return 0
  fi

  # Get previous value for comparison
  local prev; prev="$(awk -F'\t' -v kid="$kpi_id" \
    'NR>1 && $2==kid {prev=$5} END {print prev+0}' "$_FLAT_SPACE_KPI_LOG" 2>/dev/null || echo 0)"

  local log_id; log_id="$(_db_next_id "KL" "$_FLAT_SPACE_KPI_LOG")"
  local space_name; space_name="$(_tsv_get "$_FLAT_SPACE_SPACES" "$space_id" 2)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$log_id" "$kpi_id" "$space_id" "$(_tsv_safe "$kpi_name")" \
    "$value" "${kpi_unit:-}" "$(_db_today)" \
    >> "$_FLAT_SPACE_KPI_LOG"

  _ui_cap "KPI logged: $kpi_name = $value ${kpi_unit:-}"
  if [[ "$prev" -gt 0 ]]; then
    local diff=$(( value - prev ))
    local sign=""; [[ $diff -gt 0 ]] && sign="+"
    printf '  Previous: %s  %s  Change: %s%s\n\n' "$prev" "→" "$sign" "$diff" >&2
  fi
}

_space_kpi_list() {
  local query="$1"
  local space_id; space_id="$(_space_resolve_id "$query")"
  printf '\n  KPIs%s\n' "${space_id:+  —  $(_tsv_get "$_FLAT_SPACE_SPACES" "$space_id" 2)}" >&2
  _ui_hr
  awk -F'\t' -v sid="${space_id}" '
    NR>1 && (sid=="" || $3==sid) {
      printf "  %-8s  %-25s  %s  %s\n", $1, substr($4,1,25), $5, $6
    }' "$_FLAT_SPACE_KPI_LOG" >&2 || true
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# CONTACTS
# ─────────────────────────────────────────────────────────────────────────────

_space_contact_route() {
  case "${1:-list}" in
    list)        shift; _space_contact_list "$@" ;;
    add)         shift; _space_contact_add "$@" ;;
    interaction) shift; _space_contact_interaction "$@" ;;
    *)           shift; _space_contact_list "$@" ;;
  esac
}

_space_contact_list() {
  local query="$1"
  local space_id=""
  [[ -n "$query" ]] && space_id="$(_space_resolve_id "$query")"
  printf '\n  CONTACTS%s\n' "${space_id:+  —  $(_tsv_get "$_FLAT_SPACE_SPACES" "$space_id" 2)}" >&2
  _ui_hr
  awk -F'\t' -v sid="$space_id" '
    NR>1 && (sid=="" || $2==sid) {
      printf "  %-10s  %-20s  %-18s  %s\n", $1, substr($3,1,20), $4, $5
    }' "$_FLAT_SPACE_CONTACTS" >&2 || true
  printf '\n' >&2
}

_space_contact_add() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space contact add <space-name|id>" >&2; return 1; }
  local space_id; space_id="$(_space_resolve_id "$query")"
  [[ -z "$space_id" ]] && { _ui_err "Space not found: $query" >&2; return 1; }

  local name; name="$(_ui_prompt "Name")"
  [[ -z "$name" ]] && { _ui_warn "No name." >&2; return 0; }
  local role; role="$(_ui_prompt "Role/relationship" "")"

  local id; id="$(_db_next_id "CO" "$_FLAT_SPACE_CONTACTS")"
  printf '%s\t%s\t%s\t%s\t-\t%s\n' \
    "$id" "$space_id" "$(_tsv_safe "$name")" "$(_tsv_safe "$role")" "$(_db_today)" \
    >> "$_FLAT_SPACE_CONTACTS"

  _ui_cap "Contact $id: $name"
  _ev_write "space.contact.created" "{\"contact_id\":\"$id\",\"name\":\"$name\",\"space_id\":\"$space_id\"}"
  _ui_info "Create a DIA profile: sconlx spark dia — then choose this contact." >&2
}

_space_contact_interaction() {
  local contact_id="$1"
  [[ -z "$contact_id" ]] && { _ui_err "Usage: sconlx space contact interaction <id>" >&2; return 1; }
  local name; name="$(_tsv_get "$_FLAT_SPACE_CONTACTS" "$contact_id" 3)"
  [[ -z "$name" ]] && { _ui_err "Contact not found." >&2; return 1; }

  printf '\n  LOG INTERACTION: %s\n' "$name" >&2
  _tsv_update_field "$_FLAT_SPACE_CONTACTS" "$contact_id" 5 "$(_db_today)"
  _ui_cap "Last interaction updated: $name — $(_db_today)"
}

# ─────────────────────────────────────────────────────────────────────────────
# EVENTS
# ─────────────────────────────────────────────────────────────────────────────

_space_event_route() {
  case "${1:-list}" in
    list) shift; _space_event_list "$@" ;;
    add)  shift; _space_event_add "$@" ;;
    *)    _ui_err "Usage: sconlx space event [list|add] <space-name|id>" >&2 ;;
  esac
}

_space_event_add() {
  local query="$1"
  [[ -z "$query" ]] && { _ui_err "Usage: sconlx space event add <space-name|id>" >&2; return 1; }
  local space_id; space_id="$(_space_resolve_id "$query")"
  [[ -z "$space_id" ]] && { _ui_err "Space not found." >&2; return 1; }

  local ev_type
  ev_type="$(_ui_menu "Event type" "milestone" "launch" "pivot" "loss" "win" "note")"
  local title; title="$(_ui_prompt "Event title")"
  [[ -z "$title" ]] && return 0

  local ev_id; ev_id="$(_db_next_id "EV" "$_FLAT_SPACE_EVENTS")"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$ev_id" "$space_id" "$ev_type" "$(_tsv_safe "$title")" "$(_db_today)" \
    >> "$_FLAT_SPACE_EVENTS"
  _ui_cap "Event logged: $title"
}

_space_event_list() {
  local query="$1"
  local space_id=""
  [[ -n "$query" ]] && space_id="$(_space_resolve_id "$query")"
  printf '\n  EVENTS\n' >&2
  _ui_hr
  awk -F'\t' -v sid="$space_id" '
    NR>1 && (sid=="" || $2==sid) {
      printf "  %-12s  %-12s  %s\n", $5, $3, $4
    }' "$_FLAT_SPACE_EVENTS" 2>/dev/null | sort -r | head -20 >&2 || true
  printf '\n' >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# PORTFOLIO HEALTH
# ─────────────────────────────────────────────────────────────────────────────

_space_health() {
  printf '\n  PORTFOLIO HEALTH\n' >&2
  _ui_hr

  local avg; avg="$(_space_avg_health)"
  printf '\n  Overall: %s/10  %s\n\n' "$avg" "$(_ui_health_dots "$avg" 10)" >&2

  awk -F'\t' '
    NR>1 && $4!="archived" {
      bar = ""
      h = ($5+0)
      for (i=1; i<=10; i++) bar = bar (i <= h ? "█" : "░")
      printf "  %-22s  %s  %s/10  %s\n", substr($2,1,22), bar, h, $9
    }' "$_FLAT_SPACE_SPACES" >&2 || true

  # Signals
  printf '\n' >&2
  _space_signals
  printf '\n' >&2
}

_space_signals() {
  local today; today="$(_db_today)"
  # Check for overdue reviews
  local overdue
  overdue="$(awk -F'\t' -v today="$today" '
    NR>1 && $4!="archived" {
      if ($9=="" || $9=="-") { print $2; next }
      cmd="python3 -c \"from datetime import date; print((date.fromisoformat('"'"'"today"'"'"') - date.fromisoformat('"'"'"$9"'"'"')).days)\" 2>/dev/null"
      cmd | getline d; close(cmd)
      if (d+0 > 14) print $2
    }' "$_FLAT_SPACE_SPACES" 2>/dev/null || true)"

  if [[ -n "$overdue" ]]; then
    while IFS= read -r space_name; do
      [[ -n "$space_name" ]] && _ui_warn "$space_name: review overdue" >&2
    done <<< "$overdue"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Resolve a space name or ID query to the space's ID
_space_resolve_id() {
  local query="${1,,}"
  [[ -z "$query" ]] && return 0
  [[ -f "$_FLAT_SPACE_SPACES" ]] || return 0
  awk -F'\t' -v q="$query" \
    'NR>1 && (tolower($1)==q || tolower($2)~q) {print $1; exit}' \
    "$_FLAT_SPACE_SPACES" 2>/dev/null || true
}

# Average health score across active/maintenance spaces
_space_avg_health() {
  [[ -f "$_FLAT_SPACE_SPACES" ]] || { printf '0'; return 0; }
  awk -F'\t' '
    NR>1 && ($4=="active" || $4=="maintenance") && $5+0 > 0 {
      sum += $5+0; count++
    }
    END { if (count > 0) printf "%.1f", sum/count; else print "0" }
  ' "$_FLAT_SPACE_SPACES" 2>/dev/null || printf '0'
}

# Interactive space picker when no space is specified
_space_pick_space() {
  printf '\n  %s\n' "$(_ui_bold "Select a space:")" >&2
  awk -F'\t' 'NR>1 && $4!="archived" {printf "  [%s]  %s\n", $1, $2}' \
    "$_FLAT_SPACE_SPACES" >&2 || true
  _ui_prompt "Space ID or name"
}