#!/usr/bin/env bash

# GitSpace full installer — handsfree setup for commitx and scripts

# -----------------------------
# Path: ~/systems-engineer/Systems/XSpace/git-space/install.sh
# -----------------------------


set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Directories
# -----------------------------
GITSPACE_ROOT="$HOME/systems-engineer/Systems/XSpace/git-space"
BIN_DIR="$GITSPACE_ROOT/bin"
LIB_DIR="$GITSPACE_ROOT/lib"
TEMPLATES_DIR="$GITSPACE_ROOT/templates"
COMPLETION_DIR="$GITSPACE_ROOT/completion"
LOG_DIR="$HOME/.gitspace/logs"
USER_BIN="$HOME/bin"

echo "Installing GitSpace..."

# Create directories
mkdir -p "$BIN_DIR" "$LIB_DIR" "$TEMPLATES_DIR" "$COMPLETION_DIR" "$LOG_DIR" "$USER_BIN"

# Make scripts executable
chmod +x "$BIN_DIR"/* "$LIB_DIR"/* 2>/dev/null || true

# -----------------------------
# Helper functions
# -----------------------------
add_path_line() {
    local shell_rc="$1"
    local line="$2"
    mkdir -p "$(dirname "$shell_rc")" 2>/dev/null || true
    if ! grep -Fxq "$line" "$shell_rc" 2>/dev/null; then
        printf "\n# GitSpace CLI: add bin to PATH\n%s\n" "$line" >> "$shell_rc"
        echo "Added PATH line to $shell_rc"
    else
        echo "PATH line already present in $shell_rc"
    fi
}

link_scripts() {
    for f in "$BIN_DIR"/*; do
        [ -f "$f" ] || continue
        ln -sf "$f" "$USER_BIN/$(basename "$f")"
    done
    echo "Symlinked GitSpace scripts into $USER_BIN"
}

# -----------------------------
# Detect shell RC
# -----------------------------
SHELL_RC=""
if [ -n "${ZSH_VERSION-}" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION-}" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.profile"
fi

# -----------------------------
# Add ~/bin to PATH if missing
# -----------------------------
SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_path_line "$SHELL_RC" "$SAFE_ADD"

# -----------------------------
# Symlink all scripts
# -----------------------------
link_scripts

# -----------------------------
# Completion script (optional)
# -----------------------------
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

# -----------------------------
# Ensure templates dir has default PR template
# -----------------------------
TEMPLATE_PR_DIR="$TEMPLATES_DIR/pr"
mkdir -p "$TEMPLATE_PR_DIR"
if [[ ! -f "$TEMPLATE_PR_DIR/default.md" ]]; then
    cat > "$TEMPLATE_PR_DIR/default.md" <<'EOF'
## Summary

{{COMMITS}}

## What changed
Describe the changes.

## Diffstat
{{DIFFSTAT}}

## Notes
- Anything reviewers should be aware of.
EOF
    echo "Installed default PR template at $TEMPLATE_PR_DIR/default.md"
fi

# -----------------------------
# Done
# -----------------------------
mkdir -p "$GITSPACE_ROOT/.gitspace" && touch "$GITSPACE_ROOT/.gitspace/installed"
echo "GitSpace install complete. All scripts symlinked to ~/bin."
echo "Run 'source $SHELL_RC' or open a new shell to activate commitx and other commands."

exit 0