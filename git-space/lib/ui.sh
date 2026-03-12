#!/usr/bin/env bash
# GitSpace UI helpers (color + prompts)

print_info() { echo -e "[INFO] $*"; }
print_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }
print_success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }

# Simple yes/no prompt
prompt_confirm() {
    local prompt="${1:-Proceed? (y/n)}"
    while true; do
        read -r -p "$prompt " ans
        case "$ans" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}