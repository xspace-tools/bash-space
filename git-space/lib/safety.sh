#!/bin/bash
# Safety helpers for GitSpace

# Prevent committing on main
prevent_commit_on_main() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$branch" == "main" ]]; then
        echo "❌ Cannot commit directly on main."
        return 1
    fi
}

# Prevent force push
prevent_force_push() {
    echo "❌ Force push is disabled in Gitspace workflow."
    return 1
}