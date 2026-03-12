#!/usr/bin/env bash
# GitSpace formatting helpers

# Wrap text at ~72 chars
wrap_body() {
    local text="$1"
    echo "$text" | fold -s -w 72
}

# Build header: type(scope): summary
build_commit_header() {
    local type="$1"
    local scope="$2"
    local summary="$3"
    if [[ -n "$scope" ]]; then
        echo "$type($scope): $summary"
    else
        echo "$type: $summary"
    fi
}