#!/usr/bin/env bash
# bash-core/install.sh
# Pure-bash terminal prompt engine installer.
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG (newest first)
# ─────────────────────────────────────────────────────────────────────────────
#   2026-04-30  Initial standalone installer
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BIN="$_ROOT/cli/bin"
_LIB="$_ROOT/cli/lib"
_USER_BIN="${HOME}/bin"
_RC="${HOME}/.bashrc"

printf '\n  bash-core install\n  ─────────────────\n\n'

mkdir -p "$_USER_BIN"
chmod +x "$_BIN"/*

# PATH guard
if ! grep -qF "$_BIN" "$_RC" 2>/dev/null; then
    printf '\n# bash-core\nexport PATH="$PATH:%s"\n' "$_BIN" >> "$_RC"
    printf '  +  Added cli/bin to PATH\n'
else
    printf '  ✓  Already in PATH\n'
fi

# Remove Starship if present
grep -q 'starship init' "$_RC" 2>/dev/null && \
    sed -i '/starship init/d' "$_RC" && \
    printf '  ~  Removed Starship\n'

# Remove stale prompt source lines
sed -i '/bash-space.*prompt\.sh/d' "$_RC"
sed -i '/bash-core.*prompt\.sh/d'  "$_RC"

# Wire prompt engine
printf '\n# bash-core prompt engine\nsource "%s"\n' "$_LIB/prompt.sh" >> "$_RC"
printf '  +  Wired prompt engine\n'

# Symlink promptx
ln -sf "$_BIN/promptx" "$_USER_BIN/promptx"
printf '  ~  Linked: promptx\n'

printf '\n  Done.\n  Run: source ~/.bashrc\n  Then: promptx debug\n\n'
