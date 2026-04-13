# sconl-space/lib/db.sh
# Data access layer for sconlx.
# Handles mode detection (flat-file vs SQLite), path setup, ID generation,
# and all low-level read/write helpers used by scope/space/spark libs.
#
# Flat-file mode:   reads/writes TSV + Markdown files in sconl-space/data/
# SQLite mode:      reads/writes ~/.local/share/isconl/*.db via sqlite3
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.0.0 — Initial. Mode detection, all path vars, UUID/short-ID generation,
#             Equicycle helpers, TSV CRUD primitives, SQLite wrappers,
#             flat-file structure initialization.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_DB_LOADED:-}" ]] && return 0
_DB_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — paths derived from SCONLSPACE_DIR (set by sconlx entry point)
# ─────────────────────────────────────────────────────────────────────────────

# ── iSconl SQLite DB paths (when Flutter apps are installed) ──
_ISCONL_DATA_DIR="${ISCONL_DATA_DIR:-$HOME/.local/share/isconl}"
_SCOPE_DB="$_ISCONL_DATA_DIR/scope.db"
_SPACE_DB="$_ISCONL_DATA_DIR/space.db"
_SPARK_DB="$_ISCONL_DATA_DIR/spark.db"
_DIA_DB="$_ISCONL_DATA_DIR/dia_encrypted.db"
_EVENTS_DB="$_ISCONL_DATA_DIR/isconl_events.db"

# ── Flat-file data directory (CLI-only, no Flutter) ──
_FLAT_DIR="${_SCONLSPACE_DATA_DIR:-}"      # set by sconlx after sourcing conf

# ── Data mode — detected at init time ──
_DATA_MODE="flat"

# ── Equicycle python helper ──
_EQUICYCLE_PY="${_SCONLSPACE_LIB_DIR:-}/equicycle.py"

# ─────────────────────────────────────────────────────────────────────────────
# INIT — called once at startup by sconlx
# ─────────────────────────────────────────────────────────────────────────────

_db_init() {
  # Detect whether Flutter apps have been installed (SQLite mode)
  if [[ -f "$_SCOPE_DB" ]] && command -v sqlite3 &>/dev/null; then
    _DATA_MODE="sqlite"
  else
    _DATA_MODE="flat"
  fi

  # Set up flat-file path vars — always needed (fallback + data dir refs)
  _db_init_flat_paths

  # In flat mode, ensure directory structure exists
  if [[ "$_DATA_MODE" == "flat" ]]; then
    _db_ensure_flat_structure
  fi
}

_db_init_flat_paths() {
  # All flat-file paths derived from _FLAT_DIR
  # Scope
  _FLAT_SCOPE_DIR="$_FLAT_DIR/scope"
  _FLAT_SCOPE_IDENTITY="$_FLAT_SCOPE_DIR/identity.sh"
  _FLAT_SCOPE_INBOX="$_FLAT_SCOPE_DIR/inbox.tsv"
  _FLAT_SCOPE_TASKS="$_FLAT_SCOPE_DIR/tasks.tsv"
  _FLAT_SCOPE_GOALS="$_FLAT_SCOPE_DIR/goals.tsv"
  _FLAT_SCOPE_PROJECTS="$_FLAT_SCOPE_DIR/projects.tsv"
  _FLAT_SCOPE_CYCLES="$_FLAT_SCOPE_DIR/cycles.tsv"
  _FLAT_SCOPE_REFLECTIONS_DIR="$_FLAT_SCOPE_DIR/reflections"

  # Space
  _FLAT_SPACE_DIR="$_FLAT_DIR/space"
  _FLAT_SPACE_SPACES="$_FLAT_SPACE_DIR/spaces.tsv"
  _FLAT_SPACE_PROJECTS="$_FLAT_SPACE_DIR/projects.tsv"
  _FLAT_SPACE_CONTACTS="$_FLAT_SPACE_DIR/contacts.tsv"
  _FLAT_SPACE_KPI_DEFS="$_FLAT_SPACE_DIR/kpi_defs.tsv"
  _FLAT_SPACE_KPI_LOG="$_FLAT_SPACE_DIR/kpi_log.tsv"
  _FLAT_SPACE_EVENTS="$_FLAT_SPACE_DIR/events.tsv"

  # Spark
  _FLAT_SPARK_DIR="$_FLAT_DIR/spark"
  _FLAT_SPARK_IDEAS="$_FLAT_SPARK_DIR/ideas.tsv"
  _FLAT_SPARK_LEARNING="$_FLAT_SPARK_DIR/learning.tsv"
  _FLAT_SPARK_DIA="$_FLAT_SPARK_DIR/dia.tsv"

  # Shared
  _FLAT_JOURNAL_DIR="$_FLAT_DIR/journal"
  _FLAT_NOTES_DIR="$_FLAT_DIR/notes"
  _FLAT_EVENTS="$_FLAT_DIR/events.tsv"
}

_db_ensure_flat_structure() {
  # Create all dirs silently — idempotent
  mkdir -p \
    "$_FLAT_SCOPE_DIR" \
    "$_FLAT_SCOPE_REFLECTIONS_DIR" \
    "$_FLAT_SPACE_DIR" \
    "$_FLAT_SPARK_DIR" \
    "$_FLAT_JOURNAL_DIR" \
    "$_FLAT_NOTES_DIR" 2>/dev/null || true

  # Initialize TSV files with headers if they don't exist
  _db_init_tsv "$_FLAT_SCOPE_INBOX"    "ID\tTITLE\tBODY\tSTATUS\tSOURCE\tCAPTURED_AT\tEQ_YEAR\tEQ_CYCLE\tEQ_DAY"
  _db_init_tsv "$_FLAT_SCOPE_TASKS"    "ID\tTITLE\tSTATUS\tPRIORITY\tPROJECT_ID\tCARRY_FWD\tDUE_DATE\tENERGY\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_GOALS"    "ID\tTITLE\tKPI\tTARGET\tCURRENT\tLEVEL\tSTATUS\tWEIGHT\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_PROJECTS" "ID\tGOAL_ID\tTITLE\tSTATUS\tDOD\tCREATED_AT"
  _db_init_tsv "$_FLAT_SCOPE_CYCLES"   "ID\tEQ_YEAR\tCYCLE_NUM\tTHEME\tSTART_DATE\tEND_DATE\tSTATUS\tOBJ1\tOBJ2\tOBJ3"
  _db_init_tsv "$_FLAT_SPACE_SPACES"   "ID\tNAME\tTYPE\tSTATUS\tHEALTH\tDESCRIPTION\tEMOJI\tCREATED_AT\tLAST_REVIEWED"
  _db_init_tsv "$_FLAT_SPACE_PROJECTS" "ID\tSPACE_ID\tTITLE\tSTATUS\tCREATED_AT"
  _db_init_tsv "$_FLAT_SPACE_CONTACTS" "ID\tSPACE_ID\tNAME\tROLE\tLAST_CONTACT\tCREATED_AT"
  _db_init_tsv "$_FLAT_SPACE_KPI_DEFS" "ID\tSPACE_ID\tNAME\tUNIT\tTARGET"
  _db_init_tsv "$_FLAT_SPACE_KPI_LOG"  "ID\tKPI_ID\tSPACE_ID\tNAME\tVALUE\tUNIT\tMEASURED_AT"
  _db_init_tsv "$_FLAT_SPACE_EVENTS"   "ID\tSPACE_ID\tTYPE\tTITLE\tEVENT_DATE"
  _db_init_tsv "$_FLAT_SPARK_IDEAS"    "ID\tTITLE\tSTAGE\tTYPE\tBODY\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SPARK_LEARNING" "ID\tTITLE\tTYPE\tSTATUS\tPROGRESS\tAUTHOR\tCREATED_AT\tUPDATED_AT"
  _db_init_tsv "$_FLAT_SPARK_DIA"      "ID\tNAME\tROLE\tTYPE\tDEPTH\tLAST_CONTACT\tTRAJECTORY\tCREATED_AT"
  _db_init_tsv "$_FLAT_EVENTS"         "ID\tSOURCE\tTYPE\tPAYLOAD\tCREATED_AT\tCONSUMED_BY"
}

_db_init_tsv() {
  local file="$1" header="$2"
  [[ -f "$file" ]] && return 0
  printf '%b\n' "$header" > "$file"
}

# ─────────────────────────────────────────────────────────────────────────────
# ID GENERATION
# ─────────────────────────────────────────────────────────────────────────────

# Short human-readable IDs — readable in the terminal
# Format: T001, G004, I012, SP01 etc.
# Uses line count to determine next ID — simple and fast for flat files.
_db_next_id() {
  local prefix="$1" file="$2" pad="${3:-3}"
  local count=0
  if [[ -f "$file" ]]; then
    # wc -l is reliable and never exits non-zero on empty input
    count="$(tail -n +2 "$file" 2>/dev/null | wc -l | tr -d ' ')"
    count="${count:-0}"
  fi
  printf '%s%0*d' "$prefix" "$pad" "$(( count + 1 ))"
}

# UUIDv4 — used for event bus IDs and SQLite mode
_db_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]'
  else
    python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
      printf '%s-%s-%s-%s-%s' \
        "$(head -c4 /dev/urandom | xxd -p)" \
        "$(head -c2 /dev/urandom | xxd -p)" \
        "$(head -c2 /dev/urandom | xxd -p)" \
        "$(head -c2 /dev/urandom | xxd -p)" \
        "$(head -c6 /dev/urandom | xxd -p)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# TIMESTAMP HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_db_now()   { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_db_today() { date +"%Y-%m-%d"; }

# ─────────────────────────────────────────────────────────────────────────────
# EQUICYCLE HELPERS
# Calls equicycle.py as a subprocess — all date logic lives there.
# ─────────────────────────────────────────────────────────────────────────────

_eq_today_short() {
  # "Cycle 3 · Day 7 · Renewal · Apr 18"
  python3 "$_EQUICYCLE_PY" --format short 2>/dev/null || printf 'Cycle ? · Day ?'
}

_eq_today_full() {
  python3 "$_EQUICYCLE_PY" --format full 2>/dev/null || printf 'Cycle ? · Day ?'
}

# Returns: EQ_YEAR EQ_CYCLE EQ_DAY EQ_THEME (tab-separated, for read)
_eq_today_fields() {
  python3 "$_EQUICYCLE_PY" --format fields 2>/dev/null || printf '2026\t1\t1\tGenesis'
}

_eq_for_date() {
  # Returns fields for a specific date
  python3 "$_EQUICYCLE_PY" --date "$1" --format fields 2>/dev/null || printf '2026\t1\t1\tGenesis'
}

_eq_cycle_range() {
  # Returns "start_date\tend_date" for year/cycle
  python3 "$_EQUICYCLE_PY" --cycle-range "$1" "$2" 2>/dev/null || printf '%s\t%s' "$(_db_today)" "$(_db_today)"
}

_eq_progress() {
  python3 "$_EQUICYCLE_PY" --format progress 2>/dev/null || printf '[░░░░░░░░░░░░░░░░] 0%%'
}

# ─────────────────────────────────────────────────────────────────────────────
# TSV PARSING HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Count rows (excluding header)
_tsv_count() {
  local file="$1" filter="${2:-}"
  [[ -f "$file" ]] || { printf '0'; return 0; }
  if [[ -n "$filter" ]]; then
    tail -n +2 "$file" | awk -F'\t' "$filter" | wc -l | tr -d ' '
  else
    # wc -l doesn't exit non-zero on empty input — safe without ||
    tail -n +2 "$file" 2>/dev/null | wc -l | tr -d ' '
  fi
}

# Get all rows matching a field value
# Usage: _tsv_where FILE FIELD_NUM VALUE
_tsv_where() {
  local file="$1" field="$2" value="$3"
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v f="$field" -v v="$value" 'NR>1 && $f==v {print}' "$file"
}

# Get a single field value by row ID (field 1 is always ID)
# Usage: _tsv_get FILE ID FIELD_NUM
_tsv_get() {
  local file="$1" id="$2" field="$3"
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v id="$id" -v f="$field" 'NR>1 && $1==id {print $f; exit}' "$file"
}

# Check if a row with given ID exists
_tsv_exists() {
  local file="$1" id="$2"
  [[ -f "$file" ]] || return 1
  awk -F'\t' -v id="$id" 'NR>1 && $1==id {found=1; exit} END {exit !found}' "$file"
}

# Update a single field in a row (by ID in field 1)
# This replaces the entire row — TSV update requires rewriting the file.
# Usage: _tsv_update_field FILE ID FIELD_NUM NEW_VALUE
_tsv_update_field() {
  local file="$1" id="$2" field="$3" value="$4"
  [[ -f "$file" ]] || return 1
  local tmp; tmp="$(mktemp)"
  awk -F'\t' -v OFS='\t' -v id="$id" -v f="$field" -v v="$value" \
    'NR==1 {print; next} $1==id {$f=v; print; next} {print}' \
    "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Sanitize a string for TSV storage — remove tabs and leading/trailing spaces
_tsv_safe() {
  printf '%s' "$*" | tr '\t' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ─────────────────────────────────────────────────────────────────────────────
# IDENTITY CONFIG HELPERS
# Identity is stored as a sourceable bash file — identity.sh
# ─────────────────────────────────────────────────────────────────────────────

# Returns true if identity has been set up
_db_identity_exists() {
  [[ -f "$_FLAT_SCOPE_IDENTITY" ]] && grep -q 'NORTH_STAR=' "$_FLAT_SCOPE_IDENTITY" 2>/dev/null
}

# Source the identity file — sets NORTH_STAR, SEASON_NAME, etc. in calling scope
_db_identity_load() {
  [[ -f "$_FLAT_SCOPE_IDENTITY" ]] && source "$_FLAT_SCOPE_IDENTITY" 2>/dev/null || true
}

# Write the identity file (all values at once)
_db_identity_write() {
  local north_star="$1" decade_vision="$2" core_values="$3"
  local season_name="$4" season_word="$5" season_theme="$6"
  local season_year="$7" annual_intentions="$8"

  mkdir -p "$_FLAT_SCOPE_DIR"
  cat > "$_FLAT_SCOPE_IDENTITY" <<EOF
# sconl-space/data/scope/identity.sh
# Identity layer — North Star, Season, Core Values.
# Sourced directly by sconlx — bash-compatible key=value only.
# Edit freely, or use: sconlx scope identity

NORTH_STAR="$(printf '%s' "$north_star" | sed 's/"/\\"/g')"
DECADE_VISION="$(printf '%s' "$decade_vision" | sed 's/"/\\"/g')"
CORE_VALUES="$(printf '%s' "$core_values" | sed 's/"/\\"/g')"
SEASON_NAME="$(printf '%s' "$season_name" | sed 's/"/\\"/g')"
SEASON_WORD="$(printf '%s' "$season_word" | sed 's/"/\\"/g')"
SEASON_THEME="$(printf '%s' "$season_theme" | sed 's/"/\\"/g')"
SEASON_YEAR="$(printf '%s' "$season_year")"
ANNUAL_INTENTIONS="$(printf '%s' "$annual_intentions" | sed 's/"/\\"/g')"
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SQLITE MODE HELPERS (stubs — active when Flutter apps are installed)
# ─────────────────────────────────────────────────────────────────────────────

_db_scope_query() {
  [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SCOPE_DB" "$1"
}

_db_space_query() {
  [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SPACE_DB" "$1"
}

_db_spark_query() {
  [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 -separator $'\t' "$_SPARK_DB" "$1"
}

_db_scope_write() {
  [[ "$_DATA_MODE" == "sqlite" ]] || return 1
  sqlite3 "$_SCOPE_DB" "BEGIN; $1; COMMIT;"
}

# ─────────────────────────────────────────────────────────────────────────────
# LEGACY TASKS.TSV COMPATIBILITY
# The old sconlx v1.0.0 wrote to data/tasks.tsv with a different schema.
# We detect the old format and route reads there if no scope/tasks.tsv exists.
# ─────────────────────────────────────────────────────────────────────────────

# Returns true if we should use the legacy top-level tasks.tsv
_db_use_legacy_tasks() {
  [[ ! -f "$_FLAT_SCOPE_TASKS" || "$(_tsv_count "$_FLAT_SCOPE_TASKS")" == "0" ]] && \
  [[ -f "${_FLAT_DIR}/tasks.tsv" ]] && \
  [[ "$(_tsv_count "${_FLAT_DIR}/tasks.tsv")" -gt "0" ]]
}