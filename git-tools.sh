#!/usr/bin/env bash
set -eo pipefail
operation=${1:-}
if [ "$#" -gt 0 ]; then shift; fi
if [ "${1:-}" = -- ]; then shift; fi
native_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}
case "$operation" in
    edit)
        [ "$#" -eq 1 ] && [ ! -d "$1" ] || { printf '%s\n' 'Usage: git lgedit -- <selected-file>' >&2; exit 2; }
        name=$1
        if [ -n "$(git --literal-pathspecs ls-files --unmerged -- "$name")" ]; then
            exec git --literal-pathspecs mergetool --tool=bc --no-prompt -- "$name"
        fi
        editor=$(git var GIT_EDITOR)
        # The filename is positional, never interpolated into the editor command.
        exec sh -c "$editor \"\$@\"" git-lgedit "$name"
        ;;
    graph|fh)
        tortoise=$(git config --path --get gitkit.tortoisegitPath || true)
        if [ -z "$tortoise" ] && command -v cygpath >/dev/null 2>&1; then
            program_files=${PROGRAMFILES:-C:/Program Files}
            tortoise="$program_files/TortoiseGit/bin/TortoiseGitProc.exe"
        fi
        if [ -n "$tortoise" ] && [ -f "$tortoise" ]; then
            if [ "$operation" = graph ]; then
                name=$(git rev-parse --show-toplevel)
                command_name=/command:revisiongraph
            else
                [ "$#" -ge 1 ] || { printf '%s\n' 'Usage: git fh <file-or-directory>' >&2; exit 2; }
                name=$1
                if command -v cygpath >/dev/null 2>&1; then
                    name=$(cygpath -am "$name")
                else
                    name="$(pwd -P)/$name"
                fi
                command_name=/command:log
            fi
            MSYS2_ARG_CONV_EXCL='*' "$tortoise" "$command_name" "/path:$(native_path "$name")"
        elif [ "$operation" = graph ]; then
            exec git log --graph --oneline --decorate --all "$@"
        else
            [ "$#" -ge 1 ] || { printf '%s\n' 'Usage: git fh <file-or-directory>' >&2; exit 2; }
            exec git --literal-pathspecs log -- "$@"
        fi
        ;;
    *) printf '%s\n' 'Expected edit, graph, or fh.' >&2; exit 2 ;;
esac
