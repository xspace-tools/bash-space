# gitspace completion (bash / zsh)
_gitspace_common() {
    local cur prev cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmds="git-commitx git-prx"

    case "${COMP_WORDS[0]}" in
        git-commitx)
            local opts="--type --scope --summary --body-file --footer-file --amend --signoff --gpg --yes --editor --non-interactive --help"
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
        git-prx)
            local opts="--template --create-branch --from --base --title --body-file --reviewers --assignees --labels --draft --push --open --auto-merge --yes --non-interactive --help"
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
    esac
}
# bash
if [[ -n "${BASH_VERSION:-}" ]]; then
    complete -F _gitspace_common git-commitx
    complete -F _gitspace_common git-prx
fi

# zsh (compat)
if [[ -n "${ZSH_VERSION:-}" ]]; then
    compdef _gitspace_common git-commitx git-prx >/dev/null 2>&1 || true
fi