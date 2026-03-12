#!/usr/bin/env bash
# update.sh - update BashSpace repo and reinstall scripts
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/systems-engineer/Systems/XSpace/bash-space}"
cd "$REPO_DIR"

# Pull latest changes
git pull --ff-only origin main || git pull origin main

# Make all bin scripts executable
chmod +x bin/* 2>/dev/null || true

# Re-run install.sh for hands-free symlinks
./install.sh

echo "bashspace updated. Run 'refreshx' to reload your shell environment."