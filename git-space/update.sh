#!/usr/bin/env bash
# GitSpace updater — handsfree
# Path: ~/systems-engineer/Systems/XSpace/gitspace/update.sh

set -euo pipefail
IFS=$'\n\t'

REPO_DIR="${REPO_DIR:-$HOME/systems-engineer/Systems/XSpace/gitspace}"
BIN_DIR="$REPO_DIR/bin"
USER_BIN="$HOME/bin"

# -----------------------------
# Pull latest changes
# -----------------------------
cd "$REPO_DIR"
echo "Pulling latest changes from Git..."
git fetch origin main
git pull --ff-only origin main || git pull origin main

# -----------------------------
# Ensure all scripts executable
# -----------------------------
chmod +x "$BIN_DIR"/* 2>/dev/null || true

# -----------------------------
# Symlink scripts to ~/bin
# -----------------------------
mkdir -p "$USER_BIN"
for f in "$BIN_DIR"/*; do
    [ -f "$f" ] || continue
    ln -sf "$f" "$USER_BIN/$(basename "$f")"
done
echo "All GitSpace scripts symlinked to $USER_BIN"

# -----------------------------
# Ensure ~/bin is in PATH in shell RC
# -----------------------------
SHELL_RC=""
if [ -n "${ZSH_VERSION-}" ]; then SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"
else SHELL_RC="$HOME/.profile"
fi

SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
if ! grep -Fxq "$SAFE_ADD" "$SHELL_RC" 2>/dev/null; then
    printf "\n# GitSpace CLI: ensure ~/bin in PATH\n%s\n" "$SAFE_ADD" >> "$SHELL_RC"
    echo "Added ~/bin to PATH in $SHELL_RC"
else
    echo "~/bin already in PATH in $SHELL_RC"
fi

# -----------------------------
# Completion script (optional)
# -----------------------------
COMPLETION_DIR="$REPO_DIR/completion"
if [[ -f "$COMPLETION_DIR/gitspace-completion.sh" ]]; then
    COMPLETION_LINE="# GitSpace completion"
    if ! grep -Fq "$COMPLETION_LINE" "$SHELL_RC"; then
        if [[ -n "${BASH_VERSION-}" ]]; then
            echo -e "\n$COMPLETION_LINE\nsource \"$COMPLETION_DIR/gitspace-completion.sh\"" >> "$SHELL_RC"
        elif [[ -n "${ZSH_VERSION-}" ]]; then
            echo -e "\n$COMPLETION_LINE\nautoload -U compinit && compinit\nsource \"$COMPLETION_DIR/gitspace-completion.sh\"" >> "$SHELL_RC"
        fi
        echo "Installed completion loader into $SHELL_RC"
    fi
fi

echo "GitSpace update complete. All scripts ready. Run 'source $SHELL_RC' or open a new shell to activate."

exit 0