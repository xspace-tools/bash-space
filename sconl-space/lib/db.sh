# sconl-space/lib/db.sh
# Data access layer for sconlx.
# Handles mode detection, path setup, ID generation, Equicycle helpers,
# context loading (all date/age vars in one Python call), and TSV CRUD.
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v2.0.0 — Added _ctx_load() — calls equicycle.py --all-formats once and
#             exports all date/cycle/age vars into the calling scope. This
#             is the single source of truth for dashboard context. Fixed all
#             grep -c portability issues (now uses wc -l). AI_CONTEXT hook
#             scaffolded: _ctx_to_json() for future AI integration.
#   v1.0.0 — Initial. Mode detection, TSV CRUD, UUID, Equicycle helpers.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_DB_LOADED:-}" ]] && return 0
_DB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

# iSconl SQLite DB paths (SQLite mode — when Flutter apps are installed)
_ISCONL_DATA_DIR="${ISCONL_DATA_DIR:-$HOME/.local/share/isconl}"
_SCOPE_DB="$_ISCONL_DATA_DIR/scope.db"
_SPACE_DB="$_ISCONL_DATA_DIR/space.db"
_SPARK_DB="$_ISCONL_DATA_DIR/spark.db"
_DIA_DB="$_ISCONL_DATA_DIR/dia_encrypted.db"
_EVENTS_DB="$_ISCONL_DATA_DIR/isconl_events.db"

# Flat-file data directory (set by sconlx after sourcing conf)
_FLAT_DIR="${_SCONLSPACE_DATA_DIR:-}"

# Data mode (flat or sqlite) — set by _db_init
_DATA_MODE="flat"

# Equicycle Python helper path
_EQUICYCLE_PY="${_SCONLSPACE_LIB_DIR:-}/equicycle.py"

# ─────────────────────────────────────────────────────────────────────────────
# INIT — called once at sconlx startup
# ─────────────────────────────────────────────────────────────────────────────

_db_init() {
  # Detect SQLite mode: scope.db exists and sqlite3 is available
  if [[ -f "$_SCOPE_DB" ]] && command -v sqlite3 &>/dev/null; then
    _DATA_MODE="sqlite"
  else
    _DATA_MODE="flat"
  fi

  _db_init_flat_paths
  [[ "$_DATA_MODE" == "flat" ]] && _db_ensure_flat_structure || true
}

_db_init_flat_paths() {
  # All flat-file paths derived from _FLAT_DIR
  _FLAT_SCOPE_DIR="$_FLAT_DIR/scope"
  _FLAT_SCOPE_IDENTITY="$_FLAT_SCOPE_DIR/identity.sh"
  _FLAT_SCOPE_INBOX="$_FLAT_SCOPE_DIR/inbox.tsv"
  _FLAT_SCOPE_TASKS="$_FLAT_SCOPE_DIR/tasks.tsv"
  _FLAT_SCOPE_GOALS="$_FLAT_SCOPE_DIR/goals.tsv"
  _FLAT_SCOPE_PROJECTS="$_FLAT_SCOPE_DIR/projects.tsv"
  _FLAT_SCOPE_CYCLES="$_FLAT_SCOPE_DIR/cycles.tsv"
  _FLAT_SCOPE_REFLECTIONS_DIR="$_FLAT_SCOPE_DIR/reflections"
  _FLAT_SCOPE_REFLECTIONS_TSV="$_FLAT_SCOPE_DIR/reflections.tsv"

  _FLAT_SPACE_DIR="$_FLAT_DIR/space"
  _FLAT_SPACE_SPACES="$_FLAT_SPACE_DIR/spaces.tsv"
  _FLAT_SPACE_PROJECTS="$_FLAT_SPACE_DIR/projects.tsv"
  _FLAT_SPACE_CONTACTS="$_FLAT_SPACE_DIR/contacts.tsv"
  _FLAT_SPACE_KPI_DEFS="$_FLAT_SPACE_DIR/kpi_defs.tsv"
  _FLAT_SPACE_KPI_LOG="$_FLAT_SPACE_DIR/kpi_log.tsv"
  _FLAT_SPACE_EVENTS="$_FLAT_SPACE_DIR/events.tsv"

  _FLAT_SPARK_DIR="$_FLAT_DIR/spark"
  _FLAT_SPARK_IDEAS="$_FLAT_SPARK_DIR/ideas.tsv"
  _FLAT_SPARK_LEARNING="$_FLAT_SPARK_DIR/learning.tsv"
  _FLAT_SPARK_DIA="$_FLAT_SPARK_DIR/dia.tsv"

  _FLAT_JOURNAL_DIR="$_FLAT_DIR/journal"
  _FLAT_NOTES_DIR="$_FLAT_DIR/notes"
  _FLAT_EVENTS="$_FLAT_DIR/events.tsv"
}

_db_ensure_flat_structure() {
  mkdir -p \
    "$_FLAT_SCOPE_DIR" \
    "$_FLAT_SCOPE_REFLECTIONS_DIR" \
    "$_FLAT_SPACE_DIR" \
    "$_FLAT_SPARK_DIR" \
    "$_FLAT_JOURNAL_DIR" \
    "$_FLAT_NOTES_DIR" 2>/dev/null || true

  _db_init_tsv "$_FLAT_SCOPE_INBOX"    "ID\tTITLE\tBODY\tSTATUS\tSOURCE\tCAPTURED_AT\tEQ_YEAR\tEQ_CYCLE\tEQ_DAY"
  _db_init_tsv "$_FLAT_SCOPE_TASKS"    "ID\tTITLE\tSTATUS\tPRIORITY\tPROJECT_ID\tCARRY_FWD\tDUE_DATE\tENERGY\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_GOALS"    "ID\tTITLE\tKPI\tTARGET\tCURRENT\tLEVEL\tSTATUS\tWEIGHT\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_PROJECTS" "ID\tGOAL_ID\tTITLE\tSTATUS\tDOD\tCREATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_CYCLES"   "ID\tEQ_YEAR\tCYCLE_NUM\tTHEME\tSTART_DATE\tEND_DATE\tSTATUS\tOBJ1\tOBJ2\tOBJ3"
  _db_init_tsv "$_FLAT_SCOPE_REFLECTIONS_TSV" "DATE\tMOOD\tENERGY\tHAS_CONTENT"
  _db_init_tsv "$_FLAT_SPACE_SPACES"   "ID\tNAME\tTYPE\tSTATUS\tHEALTH\tDESCRIPTION\tEMOJI\tCREATED_AT\tLAST_REVIEWED"
  _db_init_tsv "$_FLAT_SPACE_PROJECTS" "ID\tSPACE_ID\tTITLE\tSTATUS\tCREATED_AT"
  _db_init_tsv "$_FLAT_SPACE_CONTACTS" "ID\tSPACE_ID\tNAME\tROLE\tLAST_CONTACT\tCREATED_AT"
  _db_init_tsv "$_FLAT_SPACE_KPI_DEFS" "ID\tSPACE_ID\tNAME\tUNIT\tTARGET"
  _db_init_tsv "$_FLAT_SPACE_KPI_LOG"  "ID\tKPI_ID\tSPACE_ID\tNAME\tVALUE\tUNIT\tMEASURED_AT"
  _db_init_tsv "$_FLAT_SPACE_EVENTS"   "ID\tSPACE_ID\tTYPE\tTITLE\tEVENT_DATE"
  _db_init_tsv "$_FLAT_SPARK_IDEAS"    "ID\tSTAGE\tTYPE\tBODY\tTITLE\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SPARK_LEARNING" "ID\tTITLE\tTYPE\tSTATUS\tPROGRESS\tAUTHOR\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SPARK_DIA"      "ID\tNAME\tROLE\tTYPE\tDEPTH\tLAST_CONTACT\tTRAJECTORY\tCREATED_AT"
  _db_init_tsv "$_FLAT_EVENTS"         "ID\tSOURCE\tTYPE\tPAYLOAD\tCREATED_AT\tCONSUMED_BY"
}

_db_init_tsv() {
  local f="$1" h="$2"
  [[ -f "$f" ]] && return 0
  printf '%b\n' "$h" > "$f"
}

# ─────────────────────────────────────────────────────────────────────────────
# CONTEXT LOADER
# Calls equicycle.py --all-formats once and exports all date/cycle/age vars.
# This is the single Python call per session — everything reads from these vars.
# After calling _ctx_load, the following globals are available:
#
#   CTX_GREGORIAN       "Monday, April 13, 2026"
#   CTX_GREGORIAN_SHORT "Mon 13 Apr 2026"
#   CTX_EQ_YEAR / CYCLE / DAY / THEME / SHORT
#   CTX_CYCLE_BAR / PCT / START / END
#   CTX_SPRINT / SPRINT_DAY / SPRINT_SHORT / SPRINT_START / SPRINT_END
#   CTX_YEAR_DAY / TOTAL / WEEK / PCT / BAR
#   CTX_AGE_SHORT       "25y 10m 17d"  (if birthday set)
#   CTX_AGE_HOURS       total hours alive
#   CTX_NEXT_BDAY       "May 27, 2026"
#   CTX_DAYS_TO_BDAY    44
#   CTX_TURNING         26
# ─────────────────────────────────────────────────────────────────────────────

_CTX_LOADED=0

_ctx_load() {
  [[ $_CTX_LOADED -eq 1 ]] && return 0

  # Build birthday arg as an array — critical because sconlx sets IFS=$'\n\t'
  # which means unquoted string vars do NOT split on spaces. An array bypasses
  # IFS entirely and passes two clean arguments to Python.
  local -a bday_arr=()
  if _db_identity_exists; then
    _db_identity_load 2>/dev/null || true
    [[ -n "${BIRTHDAY:-}" ]] && bday_arr=(--birthday "$BIRTHDAY")
  fi

  # One Python call gets everything.
  # </dev/null prevents the subprocess inheriting sconlx's stdin pipe.
  local raw
  raw="$(python3 "$_EQUICYCLE_PY" --all-formats "${bday_arr[@]}" </dev/null 2>/dev/null)" || raw=""

  # Parse KEY=VALUE lines into CTX_* globals.
  # Using eval here (not declare -g) for bash 3.x/4.x compatibility and
  # to ensure vars are truly global even when called through function chains.
  # The input is our own Python output — not user-supplied — so eval is safe.
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    # Only accept clean variable name characters to be safe
    [[ "$k" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    eval "CTX_${k}=\"\${v}\""
  done <<< "$raw"

  # Defaults for required fields if Python failed
  CTX_GREGORIAN="${CTX_GREGORIAN:-$(date '+%A, %B %d, %Y')}"
  CTX_EQ_CYCLE="${CTX_EQ_CYCLE:-?}"
  CTX_EQ_DAY="${CTX_EQ_DAY:-?}"
  CTX_EQ_THEME="${CTX_EQ_THEME:-}"
  CTX_EQ_SHORT="${CTX_EQ_SHORT:-Cycle ?  ·  Day ?}"
  CTX_CYCLE_BAR="${CTX_CYCLE_BAR:-[░░░░░░░░░░░░░░░░░░░░]}"
  CTX_CYCLE_PCT="${CTX_CYCLE_PCT:-0}"
  CTX_SPRINT_SHORT="${CTX_SPRINT_SHORT:-Sprint ?}"
  CTX_YEAR_PCT="${CTX_YEAR_PCT:-0}"
  CTX_YEAR_BAR="${CTX_YEAR_BAR:-[░░░░░░░░░░░░░░░░░░░░]}"
  CTX_YEAR_DAY="${CTX_YEAR_DAY:-?}"
  CTX_YEAR_TOTAL="${CTX_YEAR_TOTAL:-365}"
  CTX_AGE_SHORT="${CTX_AGE_SHORT:-}"
  CTX_DAYS_TO_BDAY="${CTX_DAYS_TO_BDAY:-}"
  CTX_NEXT_BDAY="${CTX_NEXT_BDAY:-}"
  CTX_TURNING="${CTX_TURNING:-}"

  _CTX_LOADED=1
}

# Export the current context as JSON — hook point for future AI integration
_ctx_to_json() {
  _ctx_load || true
  python3 -c "
import json, sys
ctx = {
  'gregorian':      '${CTX_GREGORIAN:-}',
  'eq_cycle':       '${CTX_EQ_CYCLE:-}',
  'eq_day':         '${CTX_EQ_DAY:-}',
  'eq_theme':       '${CTX_EQ_THEME:-}',
  'sprint':         '${CTX_SPRINT_SHORT:-}',
  'year_pct':       '${CTX_YEAR_PCT:-}',
  'age':            '${CTX_AGE_SHORT:-}',
  'days_to_bday':   '${CTX_DAYS_TO_BDAY:-}',
}
print(json.dumps(ctx, indent=2))
" 2>/dev/null || printf '{}'
}

# ─────────────────────────────────────────────────────────────────────────────
# ID GENERATION
# ─────────────────────────────────────────────────────────────────────────────

_db_next_id() {
  local prefix="$1" file="$2" pad="${3:-3}"
  local count=0
  if [[ -f "$file" ]]; then
    count="$(tail -n +2 "$file" 2>/dev/null | wc -l | tr -d ' ')"
    count="${count:-0}"
  fi
  printf '%s%0*d' "$prefix" "$pad" "$(( count + 1 ))"
}

_db_uuid() {
  command -v uuidgen &>/dev/null && uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' && return 0
  python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# TIMESTAMPS
# ─────────────────────────────────────────────────────────────────────────────

_db_now()   { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_db_today() { date +"%Y-%m-%d"; }

# ─────────────────────────────────────────────────────────────────────────────
# LEGACY EQUICYCLE HELPERS (still used internally)
# These call Python — prefer _ctx_load for the dashboard where efficiency matters
# ─────────────────────────────────────────────────────────────────────────────

_eq_today_short() {
  python3 "$_EQUICYCLE_PY" --format short 2>/dev/null || printf 'Cycle ?  ·  Day ?'
}

_eq_today_fields() {
  python3 "$_EQUICYCLE_PY" --format fields 2>/dev/null || printf '2026\t1\t1\tGenesis'
}

_eq_for_date() {
  python3 "$_EQUICYCLE_PY" --date "$1" --format fields 2>/dev/null || printf '2026\t1\t1\tGenesis'
}

_eq_cycle_range() {
  python3 "$_EQUICYCLE_PY" --cycle-range "$1" "$2" 2>/dev/null || printf '%s\t%s' "$(_db_today)" "$(_db_today)"
}

_eq_progress() {
  python3 "$_EQUICYCLE_PY" --format progress 2>/dev/null || printf '[░░░░░░░░░░░░░░░░░░░░] 0%%'
}

# ─────────────────────────────────────────────────────────────────────────────
# TSV HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_tsv_count() {
  local file="$1" filter="${2:-}"
  [[ -f "$file" ]] || { printf '0'; return 0; }
  if [[ -n "$filter" ]]; then
    tail -n +2 "$file" | awk -F'\t' "$filter" | wc -l | tr -d ' '
  else
    tail -n +2 "$file" 2>/dev/null | wc -l | tr -d ' '
  fi
}

_tsv_where() {
  local file="$1" field="$2" value="$3"
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v f="$field" -v v="$value" 'NR>1 && $f==v {print}' "$file"
}

_tsv_get() {
  local file="$1" id="$2" field="$3"
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v id="$id" -v f="$field" 'NR>1 && $1==id {print $f; exit}' "$file"
}

_tsv_exists() {
  local file="$1" id="$2"
  [[ -f "$file" ]] || return 1
  awk -F'\t' -v id="$id" 'NR>1 && $1==id {found=1; exit} END {exit !found}' "$file"
}

_tsv_update_field() {
  local file="$1" id="$2" field="$3" value="$4"
  [[ -f "$file" ]] || return 1
  local tmp; tmp="$(mktemp)"
  awk -F'\t' -v OFS='\t' -v id="$id" -v f="$field" -v v="$value" \
    'NR==1{print;next} $1==id{$f=v;print;next} {print}' \
    "$file" > "$tmp"
  mv "$tmp" "$file"
}

_tsv_safe() { printf '%s' "$*" | tr '\t' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# ─────────────────────────────────────────────────────────────────────────────
# IDENTITY HELPERS
# Identity stored as a sourceable bash file: sconl-space/data/scope/identity.sh
# ─────────────────────────────────────────────────────────────────────────────

_db_identity_exists() {
  [[ -f "$_FLAT_SCOPE_IDENTITY" ]] && \
  grep -q 'NORTH_STAR=' "$_FLAT_SCOPE_IDENTITY" 2>/dev/null
}

_db_identity_load() {
  [[ -f "$_FLAT_SCOPE_IDENTITY" ]] && source "$_FLAT_SCOPE_IDENTITY" 2>/dev/null || true
}

# Write all identity fields atomically
_db_identity_write() {
  local north_star="$1" decade="$2" values="$3"
  local season_name="$4" season_word="$5" season_theme="$6"
  local season_year="$7" intentions="$8" birthday="${9:-}"

  mkdir -p "$_FLAT_SCOPE_DIR"
  cat > "$_FLAT_SCOPE_IDENTITY" <<IDENTITY
# sconl-space/data/scope/identity.sh
# Identity layer — sourced by sconlx. Edit here or via: sconlx scope identity edit
# Do NOT add logic here — values only.

NORTH_STAR="$(printf '%s' "$north_star" | sed 's/"/\\"/g')"
DECADE_VISION="$(printf '%s' "$decade" | sed 's/"/\\"/g')"
CORE_VALUES="$(printf '%s' "$values" | sed 's/"/\\"/g')"
SEASON_NAME="$(printf '%s' "$season_name" | sed 's/"/\\"/g')"
SEASON_WORD="$(printf '%s' "$season_word" | sed 's/"/\\"/g')"
SEASON_THEME="$(printf '%s' "$season_theme" | sed 's/"/\\"/g')"
SEASON_YEAR="$(printf '%s' "$season_year")"
ANNUAL_INTENTIONS="$(printf '%s' "$intentions" | sed 's/"/\\"/g')"
BIRTHDAY="$(printf '%s' "$birthday")"
IDENTITY
}

# ─────────────────────────────────────────────────────────────────────────────
# SQLITE MODE STUBS (active when Flutter apps are installed)
# ─────────────────────────────────────────────────────────────────────────────

_db_scope_query() { [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SCOPE_DB" "$1"; }

_db_space_query() { [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SPACE_DB" "$1"; }

_db_spark_query() { [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SPARK_DB" "$1"; }

_db_scope_write() { [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 "$_SCOPE_DB" "BEGIN; $1; COMMIT;"; }

# ─────────────────────────────────────────────────────────────────────────────
# AI HOOK DISPATCHER
# Called after every significant data write. When AI_ENABLED=0 this is a no-op.
# Pattern: _db_hook "event.name" '{"key":"value"}'
# Adding a new action? Call _db_hook at the end of its write function.
# ─────────────────────────────────────────────────────────────────────────────

_db_hook() {
  local hook_name="$1" payload="${2:-{}}"
  # Delegate to ai.sh if loaded and enabled
  command -v _ai_hook &>/dev/null && _ai_hook "$hook_name" "$payload" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# DAY THEMES + FOCUS BLOCKS
# Your weekly operating rhythm. Surfaced in the dashboard and task planning.
# ─────────────────────────────────────────────────────────────────────────────

# ── Day themes (0=Sunday … 6=Saturday) ──
declare -a _DAY_THEMES=(
  "Setup Day"          # Sunday  — iSconl build, laundry, backups, updates
  "Healthcare + XSpace"  # Monday  — biomedical tools, XSpace improvements
  "Articles + QSpace"  # Tuesday — publish articles, QSpace build
  "Midweek Reset"      # Wednesday — review, recalibrate, admin
  "Client Projects"    # Thursday — client work, delivery
  "Documentation + Articles" # Friday — docs, compile + schedule articles
  "Adventure Day"      # Saturday — explore, rest, social
)

# ── Day focus areas (what to pull tasks from) ──
declare -A _DAY_FOCUS_AREAS=(
  [0]="isconl|xspace|setup|backup|cleaning"
  [1]="healthcare|biomedical|wellpath|xspace"
  [2]="articles|qspace|writing|publish"
  [3]="review|reset|admin|planning"
  [4]="client|acexoft|projects|delivery"
  [5]="docs|documentation|articles|scheduling"
  [6]="personal|health|adventure|rest"
)

# ── Focus blocks (time-based) ──
# Format: "START_HOUR:END_HOUR:NAME:DESCRIPTION"
declare -a _FOCUS_BLOCKS=(
  "8:10:Innovator:Deep work — build, create, solve"
  "11:13:Visionary:Strategic — plan, design, think"
  "14:16:Creator:Output — write, ship, publish"
)

# Get today's theme
_db_day_theme() {
  local dow; dow="$(date +%w)"  # 0=Sun … 6=Sat
  printf '%s' "${_DAY_THEMES[$dow]}"
}

# Get today's focus area keywords (pipe-separated)
_db_day_focus() {
  local dow; dow="$(date +%w)"
  printf '%s' "${_DAY_FOCUS_AREAS[$dow]}"
}

# Get the current focus block name (empty if outside blocks)
_db_current_block() {
  # Force base-10 — date +%-H can return "09" which bash treats as octal
  local hour=$(( 10#$(date +%H) ))
  local block
  for block in "${_FOCUS_BLOCKS[@]}"; do
    local start="${block%%:*}"; local rest="${block#*:}"
    local end="${rest%%:*}";   local rest2="${rest#*:}"
    local name="${rest2%%:*}"
    if [[ "$hour" -ge "$start" && "$hour" -lt "$end" ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  printf ''
}

# Get time until next focus block (or time remaining in current)
_db_block_status() {
  # Force base-10 on both hour and minute — leading zeros cause octal errors
  local hour=$(( 10#$(date +%H) ))
  local min=$(( 10#$(date +%M) ))
  local now_mins=$(( hour * 60 + min ))

  for block in "${_FOCUS_BLOCKS[@]}"; do
    local start="${block%%:*}"; local rest="${block#*:}"
    local end="${rest%%:*}";   local rest2="${rest#*:}"
    local name="${rest2%%:*}"; local desc="${rest2#*:}"

    local start_m=$(( start * 60 ))
    local end_m=$(( end * 60 ))

    if [[ "$now_mins" -ge "$start_m" && "$now_mins" -lt "$end_m" ]]; then
      local rem=$(( end_m - now_mins ))
      printf 'IN:%s:%dmin remaining (%s)' "$name" "$rem" "$desc"
      return 0
    elif [[ "$now_mins" -lt "$start_m" ]]; then
      local until=$(( start_m - now_mins ))
      printf 'NEXT:%s:%s — starts in %dmin' "$name" "$desc" "$until"
      return 0
    fi
  done
  printf 'DONE:—:All focus blocks complete for today'
}

# ─────────────────────────────────────────────────────────────────────────────
# EDITOR DETECTION
# Priority: VS Code → $VISUAL → $EDITOR → gedit/kate → nano
# Windows: code.exe → notepad
# ─────────────────────────────────────────────────────────────────────────────

_db_editor() {
  # VS Code — preferred everywhere
  if command -v code &>/dev/null; then
    printf 'code --wait'
    return 0
  fi
  # code-insiders fallback
  if command -v code-insiders &>/dev/null; then
    printf 'code-insiders --wait'
    return 0
  fi
  # Windows notepad (Git Bash)
  if command -v notepad.exe &>/dev/null; then
    printf 'notepad.exe'
    return 0
  fi
  # $VISUAL / $EDITOR env vars
  if [[ -n "${VISUAL:-}" ]]; then
    printf '%s' "$VISUAL"
    return 0
  fi
  if [[ -n "${EDITOR:-}" ]]; then
    printf '%s' "$EDITOR"
    return 0
  fi
  # Linux GUI editors
  if command -v gedit &>/dev/null; then printf 'gedit'; return 0; fi
  if command -v kate &>/dev/null;  then printf 'kate';  return 0; fi
  if command -v xdg-open &>/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    printf 'xdg-open'; return 0
  fi
  # Terminal fallback
  if command -v nano &>/dev/null; then printf 'nano'; return 0; fi
  if command -v vim  &>/dev/null; then printf 'vim';  return 0; fi
  printf 'nano'  # last resort
}