#!/usr/bin/env bash
# bash-space/lib/prompt.sh
#
# QSPACE Prompt Engine v1.2.0
# Pure bash — zero dependencies, no Starship, no TOML
# Sourced by ~/.bashrc via installx
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGELOG
# ─────────────────────────────────────────────────────────────────────────────
#   v1.2.0 — Sentence-style formatting. user@host all green. Filler words
#             'in', 'on branch', 'at' in dim white. Timestamp in white.
#             Branch name bold + colored. Reads as natural sentence:
#             "sconl@fedora in xspace on branch dev at 00:12"
#   v1.1.0 — Branch names bold. Colors: main/master=blue, dev=green,
#             staging=yellow, fix/*|hotfix/*=red, *=purple.
#   v1.0.0 — Initial release.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG BLOCK — all tunables here
# ─────────────────────────────────────────────────────────────────────────────

_PROMPT_SHOW_USER=true
_PROMPT_SHOW_HOST=true
_PROMPT_SHOW_TIME=true

# Branch color rules — matched top-to-bottom, first match wins
# Format: "glob_pattern:ansi_color_code"
# 31=red  32=green  33=yellow  34=blue  35=purple  36=cyan
_PROMPT_BRANCH_COLORS=(
  "main:34"
  "master:34"
  "dev:32"
  "staging:33"
  "hotfix/*:31"
  "fix/*:31"
  "*:35"
)

# ─────────────────────────────────────────────────────────────────────────────
# INTERNALS — do not edit below unless extending
# ─────────────────────────────────────────────────────────────────────────────

__prompt_branch_color() {
  local branch="$1" entry pattern color
  for entry in "${_PROMPT_BRANCH_COLORS[@]}"; do
    pattern="${entry%%:*}"
    color="${entry##*:}"
    # shellcheck disable=SC2254
    case "$branch" in
      $pattern) printf "%s" "$color"; return ;;
    esac
  done
  printf "35"
}

__prompt_branch() {
  local branch color
  branch=$(git branch --show-current 2>/dev/null)
  [[ -z "$branch" ]] && return
  color=$(__prompt_branch_color "$branch")
  # dim white "on branch" + bold colored branch name
  printf "\e[2;37m on branch \e[0m\e[1;%sm%s\e[0m" "$color" "$branch"
}

__prompt_dir() {
  local root repo rel
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$root" ]]; then
    repo=$(basename "$root")
    rel="${PWD#"$root"}"
    printf "%s%s" "$repo" "$rel"
  else
    printf "%s" "$PWD"
  fi
}

__build_prompt() {
  local _exit=$?

  # ANSI — wrapped in \[ \] so bash counts them as zero-width
  local r="\[\e[0m\]"
  local bold="\[\e[1m\]"
  local grn="\[\e[32m\]"          # green     — user@host
  local blu="\[\e[34m\]"          # blue      — directory
  local dim_white="\[\e[2;37m\]"  # dim white — filler words: in, on branch, at
  local white="\[\e[37m\]"        # white     — timestamp
  local red="\[\e[31m\]"          # red       — error character

  local line1="" char

  # sconl@fedora — all bold green
  if [[ "$_PROMPT_SHOW_USER" == true && "$_PROMPT_SHOW_HOST" == true ]]; then
    line1+="${bold}${grn}\u@\h${r}"
  elif [[ "$_PROMPT_SHOW_USER" == true ]]; then
    line1+="${bold}${grn}\u${r}"
  elif [[ "$_PROMPT_SHOW_HOST" == true ]]; then
    line1+="${bold}${grn}\h${r}"
  fi

  # "in" dim white + directory bold blue
  line1+=" ${dim_white}in${r} ${bold}${blu}\$(__prompt_dir)${r}"

  # "on branch dev" — only inside a git repo, injected by __prompt_branch
  line1+="\$(__prompt_branch)"

  # "at" dim white + timestamp white
  if [[ "$_PROMPT_SHOW_TIME" == true ]]; then
    line1+=" ${dim_white}at${r} ${white}\$(date +%H:%M)${r}"
  fi

  # Prompt character — green on success, red on error
  if [[ $_exit -eq 0 ]]; then
    char="${bold}${grn}❯${r}"
  else
    char="${bold}${red}❯${r}"
  fi

  PS1="${line1}\n${char} "
}

PROMPT_COMMAND='__build_prompt'