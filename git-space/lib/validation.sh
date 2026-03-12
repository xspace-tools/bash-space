#!/usr/bin/env bash
# GitSpace validation helpers (enhanced)
# Path: lib/validation.sh

set -euo pipefail
IFS=$'\n\t'

# Validate conventional commit type
validate_commit_type() {
    local type="$1"
    case "$type" in
        feat|fix|docs|style|refactor|test|chore) return 0 ;;
        *) echo "❌ Invalid commit type: $type" >&2; return 1 ;;
    esac
}

# Validate staged changes exist
validate_staged_changes() {
    if [[ -z "$(git diff --cached --name-only)" ]]; then
        echo "❌ No staged changes. Stage files before committing." >&2
        return 1
    fi
    return 0
}

# Prevent committing directly to main/master
prevent_commit_on_main() {
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
        echo "❌ Cannot commit directly on $branch branch." >&2
        return 1
    fi
    return 0
}

# Validate branch name pattern: type/scope/short-desc (scope optional but recommended)
validate_branch_name() {
    local branch="$1"
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
        echo "❌ Branch name cannot be 'main' or 'master'." >&2
        return 1
    fi
    if [[ "$branch" =~ ^(feature|fix|refactor|docs|chore|test|experiment|breaking)\/[^\/]+\/?.+$ ]]; then
        return 0
    fi
    # Allow shorter like feature/scope if needed
    if [[ "$branch" =~ ^(feature|fix|refactor|docs|chore|test|experiment|breaking)\/[^\/]+$ ]]; then
        return 0
    fi
    echo "❌ Branch name does not match convention: <type>/<scope>/<desc>." >&2
    return 1
}

# Check for accidental secrets in staged files (basic heuristics)
detect_secrets_in_staged() {
    local suspicious
    suspicious="$(git diff --cached --name-only | xargs -r grep -nE 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|PRIVATE_KEY|BEGIN RSA PRIVATE KEY|ssh-rsa|SECRET=|PASSWORD=' || true)"
    if [[ -n "$suspicious" ]]; then
        echo "⚠️ Suspicious strings found in staged files:" >&2
        echo "$suspicious" >&2
        return 1
    fi
    return 0
}

# Suggest reviewers:
# 1) If CODEOWNERS present, pick owners for changed files
# 2) Else, use `gh api` to list repository collaborators (requires gh auth)
suggest_reviewers() {
    # arguments: list of changed files or empty -> use staged files
    local files=("$@")
    if [[ ${#files[@]} -eq 0 ]]; then
        mapfile -t files < <(git diff --cached --name-only)
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    local suggest=""
    # 1) CODEOWNERS parsing
    if [[ -f "$repo_root/.github/CODEOWNERS" || -f "$repo_root/CODEOWNERS" ]]; then
        local codeowners_file
        if [[ -f "$repo_root/.github/CODEOWNERS" ]]; then codeowners_file="$repo_root/.github/CODEOWNERS"; else codeowners_file="$repo_root/CODEOWNERS"; fi
        # For each file, find matching owners (simple approach)
        for f in "${files[@]}"; do
            # Use grep to find last matching pattern (CODEOWNERS matches last rule)
            local owner_line
            owner_line="$(awk -v file="$f" '{
                # naive pattern: check if last token is owner and pattern matches at end
                for(i=1;i<=NF-1;i++){
                    pattern=$i
                    # convert simple wildcard to regex
                    gsub(/\*/, ".*", pattern)
                    if (file ~ pattern) { last=$0 }
                }
            } END { if (last) print last }' "$codeowners_file" 2>/dev/null || true)"
            if [[ -n "$owner_line" ]]; then
                # extract owners (last fields)
                local owners
                owners="$(echo "$owner_line" | awk '{for(i=NF-1;i<=NF;i++) printf $i \" \";}' 2>/dev/null || true)"
                suggest="$suggest $owners"
            fi
        done
    fi

    # 2) fallback: use gh to list collaborators (owner must have gh)
    if [[ -z "$suggest" && -n "$(command -v gh 2>/dev/null)" ]]; then
        # List top collaborators: people with push permission
        local repo
        repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
        if [[ -n "$repo" ]]; then
            # Using gh api to list collaborators (limit to first 6)
            local cols
            cols="$(gh api repos/"$repo"/collaborators --jq '.[].login' 2>/dev/null | head -n 6 || true)"
            suggest="$cols"
        fi
    fi

    # Normalize suggestions (unique, comma separated)
    if [[ -n "$suggest" ]]; then
        # remove duplicates and empty
        echo "$suggest" | tr ' ' '\n' | awk 'NF' | awk '!seen[$0]++' | paste -s -d, - || true
        return 0
    fi

    # No suggestion
    echo ""
    return 0
}