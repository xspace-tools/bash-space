# sconl-space/lib/events.sh
# Cross-system event bus for sconlx.
# In flat-file mode: reads/writes data/events.tsv
# In SQLite mode: reads/writes ~/.local/share/isconl/isconl_events.db
#
# The event bus is how the three systems (Scope, Space, Spark) communicate.
# sconlx both produces events (e.g. sconlx.capture) and consumes them
# (e.g. processing a spark.idea.promoted_to_scope event to show a prompt).
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Event write, pending read, consume, process-all loop.
#             Both flat-file (TSV) and SQLite modes.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_EVENTS_LOADED:-}" ]] && return 0
_EVENTS_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

_EV_SOURCE="sconlx"          # our identity on the event bus
_EV_MAX_PENDING=50           # max events to process in one session

# ─────────────────────────────────────────────────────────────────────────────
# WRITE AN EVENT
# ─────────────────────────────────────────────────────────────────────────────

# Write an event to the bus.
# Usage: _ev_write "event.type" '{"key":"value"}'
_ev_write() {
  local event_type="$1" payload="${2:-{}}"
  local id; id="$(_db_uuid)"
  local now; now="$(_db_now)"

  if [[ "$_DATA_MODE" == "sqlite" ]]; then
    local safe_payload; safe_payload="$(printf '%s' "$payload" | sed "s/'/''/g")"
    sqlite3 "$_EVENTS_DB" \
      "INSERT INTO isconl_events (id, source_app, event_type, payload, created_at, consumed_by)
       VALUES ('$id', '$_EV_SOURCE', '$event_type', '$safe_payload', '$now', '');" \
      2>/dev/null || true
  else
    # Flat-file mode: append to events.tsv
    local safe_payload; safe_payload="$(printf '%s' "$payload" | tr '\t\n' '  ')"
    printf '%s\t%s\t%s\t%s\t%s\t\n' \
      "$id" "$_EV_SOURCE" "$event_type" "$safe_payload" "$now" \
      >> "$_FLAT_EVENTS" 2>/dev/null || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# READ PENDING EVENTS
# ─────────────────────────────────────────────────────────────────────────────

# Print pending events for sconlx (not yet consumed by us).
# Output: one TSV row per event (id, type, payload)
_ev_pending() {
  if [[ "$_DATA_MODE" == "sqlite" ]]; then
    sqlite3 -separator $'\t' "$_EVENTS_DB" \
      "SELECT id, event_type, payload FROM isconl_events
       WHERE consumed_by NOT LIKE '%sconlx%'
       ORDER BY created_at ASC LIMIT $_EV_MAX_PENDING;" \
      2>/dev/null || true
  else
    [[ -f "$_FLAT_EVENTS" ]] || return 0
    # Field 6 is CONSUMED_BY — show rows where sconlx isn't listed
    awk -F'\t' 'NR>1 && $6 !~ /sconlx/ {print $1 "\t" $3 "\t" $4}' \
      "$_FLAT_EVENTS" | head -n "$_EV_MAX_PENDING"
  fi
}

# Count pending events
_ev_pending_count() {
  local result; result="$(_ev_pending)"
  [[ -z "$result" ]] && { printf '0'; return 0; }
  printf '%s\n' "$result" | wc -l | tr -d ' '
}

# ─────────────────────────────────────────────────────────────────────────────
# CONSUME AN EVENT
# ─────────────────────────────────────────────────────────────────────────────

# Mark an event as consumed by sconlx.
_ev_consume() {
  local event_id="$1"

  if [[ "$_DATA_MODE" == "sqlite" ]]; then
    sqlite3 "$_EVENTS_DB" \
      "UPDATE isconl_events
       SET consumed_by = consumed_by || ',sconlx'
       WHERE id = '$event_id';" \
      2>/dev/null || true
  else
    [[ -f "$_FLAT_EVENTS" ]] || return 0
    local tmp; tmp="$(mktemp)"
    awk -F'\t' -v OFS='\t' -v id="$event_id" \
      'NR==1 {print; next}
       $1==id {$6=$6 (length($6)>0 ? "," : "") "sconlx"; print; next}
       {print}' \
      "$_FLAT_EVENTS" > "$tmp"
    mv "$tmp" "$_FLAT_EVENTS"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS PENDING EVENTS
# Processes events and offers the user relevant actions.
# Called at startup and via: sconlx x events process
# ─────────────────────────────────────────────────────────────────────────────

_ev_process_all() {
  local pending; pending="$(_ev_pending)"
  [[ -z "$pending" ]] && return 0

  local count; count="$(printf '%s\n' "$pending" | wc -l | tr -d ' ')"
  [[ "${count:-0}" -eq 0 ]] && return 0

  _ui_section "Pending Events ($count)"

  local processed=0
  while IFS=$'\t' read -r ev_id ev_type ev_payload; do
    [[ -z "$ev_id" ]] && continue
    _ev_handle_event "$ev_id" "$ev_type" "$ev_payload"
    _ev_consume "$ev_id"
    (( ++processed ))
  done <<< "$pending"

  [[ $processed -gt 0 ]] && _ui_ok "Processed $processed event(s)" >&2
}

_ev_handle_event() {
  local ev_id="$1" ev_type="$2" ev_payload="$3"

  case "$ev_type" in
    spark.idea.promoted_to_scope)
      # An idea was promoted — ask if we should create a goal from it
      local idea_title; idea_title="$(printf '%s' "$ev_payload" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('idea_title','?'))" \
        2>/dev/null || printf '?')"
      _ui_info "Idea promoted to Scope: \"$(_ui_truncate "$idea_title" 40)\""
      _ui_info "→ Review with: sconlx scope goal add"
      ;;

    space.task.created)
      # A task was created in Space and needs to appear in Scope
      _ui_info "New task from Space → Scope inbox"
      ;;

    scope.reflection.saved)
      _ui_info "Scope reflection saved → available for Spark journal expansion"
      ;;

    spark.learning.completed)
      _ui_info "Learning item completed → consider adding a Scope goal"
      ;;

    space.contact.created)
      _ui_info "New contact in Space → consider creating a DIA profile in Spark"
      ;;

    *)
      # Unknown event — consume silently
      : ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# EVENT BUS STATUS
# ─────────────────────────────────────────────────────────────────────────────

_ev_status() {
  local count; count="$(_ev_pending_count)"
  printf '%d' "$count"
}