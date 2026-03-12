#!/usr/bin/env bash
# install.sh - hands-free installer for BashSpace
set -euo pipefail
IFS=$'\n\t'

# Repo location and paths
REPO_DIR="${REPO_DIR:-$HOME/systems-engineer/Systems/XSpace/bash-space}"
BIN_DIR="$REPO_DIR/bin"
USER_BIN="$HOME/bin"

# Ensure folders exist
mkdir -p "$REPO_DIR" "$BIN_DIR" "$USER_BIN"

# Make all scripts executable
chmod +x "$BIN_DIR"/* 2>/dev/null || true

# Function to safely add a line to shell rc
add_path_line() {
    local shell_rc="$1"
    local line="$2"
    mkdir -p "$(dirname "$shell_rc")" 2>/dev/null || true
    if ! grep -Fxq "$line" "$shell_rc" 2>/dev/null; then
        printf "\n# bashspace: add repo bin to PATH\n%s\n" "$line" >> "$shell_rc"
        echo "Added PATH line to $shell_rc"
    else
        echo "PATH line already present in $shell_rc"
    fi
}

# Symlink all bin scripts to ~/bin
link_scripts() {
    for f in "$BIN_DIR"/*; do
        [ -f "$f" ] || continue
        ln -sf "$f" "$USER_BIN/$(basename "$f")"
    done
    echo "Symlinked bashspace scripts into $USER_BIN"
}

# Detect shell RC file
SHELL_RC=""
if [ -n "${ZSH_VERSION-}" ]; then SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"
else SHELL_RC="$HOME/.profile"
fi

# Add ~/bin to PATH if missing
SAFE_ADD='[[ ":$PATH:" != *":$HOME/bin:"* ]] && PATH="$HOME/bin:$PATH"'
add_path_line "$SHELL_RC" "$SAFE_ADD"

# Hands-free symlink of all scripts in bin/
link_scripts

# Ensure refreshx exists
REFRESHX="$BIN_DIR/refreshx"
if [ ! -f "$REFRESHX" ]; then
    cat > "$REFRESHX" <<'EOF'
#!/usr/bin/env bash
# refreshx - reload shell and clear command cache
source ~/.bashrc
hash -r
echo "Shell environment refreshed and command cache cleared."
EOF
    chmod +x "$REFRESHX"
fi

# Touch an installed marker
mkdir -p "$REPO_DIR/.bashspace" && touch "$REPO_DIR/.bashspace/installed"

echo "Install complete. Run 'refreshx' or restart your shell to activate bashspace."