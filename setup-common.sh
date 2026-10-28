#!/usr/bin/env bash
# Shared Bash 3.2+ installer; no Python/pip/PyYAML/jq/yq.
set -eo pipefail
platform=${1:-}; [ "$#" -gt 0 ] && shift
kit_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
bc_path=''; install_dir=''; git_config=''; lazy_config=''; temp_root=''
user_name=''; user_email=''; editor=''; check_only=false; lazy_only=false; no_trust=false
usage() {
    cat <<'HELP'
Usage: setup-<platform> [options]
  --check                   Check tools/config structure; do not modify config
  --bc-path PATH            Beyond Compare executable/CLI
  --install-dir PATH        Helper directory, default ~/.local/share/git-cli-kit
  --git-config PATH         Override global config target (isolated setup)
  --lazygit-config PATH     Override active lazygit config.yml
  --temp-root PATH          Set rv.tempRoot; otherwise preserve existing/default
  --name NAME               Override Git name; otherwise preserve existing
  --email EMAIL             Override Git email; otherwise preserve existing
  --editor COMMAND          Override core.editor, e.g. "code --wait"
  --no-trust-all            Do not import snapshot safe.directory=*
  --lazygit-only            Only configure conflict editing and merge shortcuts
HELP
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) check_only=true; shift ;;
        --lazygit-only) lazy_only=true; shift ;;
        --no-trust-all) no_trust=true; shift ;;
        --help|-h) usage; exit 0 ;;
        --bc-path|--install-dir|--git-config|--lazygit-config|--temp-root|--name|--email|--editor)
            [ "$#" -ge 2 ] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
            case "$1" in
                --bc-path) bc_path=$2 ;; --install-dir) install_dir=$2 ;;
                --git-config) git_config=$2 ;; --lazygit-config) lazy_config=$2 ;;
                --temp-root) temp_root=$2 ;; --name) user_name=$2 ;;
                --email) user_email=$2 ;; --editor) editor=$2 ;;
            esac
            shift 2 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) actual=windows ;; Darwin) actual=macos ;; Linux) actual=linux ;; *) actual=unknown ;; esac
[ "$platform" = "$actual" ] || { printf 'Use the %s entry script on this computer.\n' "$actual" >&2; exit 2; }
missing=false
for required in git lazygit awk sed cmp mktemp cp mv dirname basename date mkdir rm chmod cat grep tr; do
    if ! command -v "$required" >/dev/null 2>&1; then printf 'MISSING: %s\n' "$required" >&2; missing=true; fi
done
if "$missing"; then
    case "$platform" in
        windows) printf '%s\n' 'Install Git for Windows and lazygit, reopen the terminal, then rerun:' '  winget install --id Git.Git -e' '  winget install --id JesseDuffield.lazygit -e' >&2 ;;
        macos) printf '%s\n' 'Install Homebrew if needed, then: brew install git lazygit' >&2 ;;
        linux) printf '%s\n' 'Install Bash, Git and base utilities with your distro package manager.' 'Lazygit: https://github.com/jesseduffield/lazygit#installation' >&2 ;;
    esac
    exit 2
fi
version=$(git --version)
if [[ "$version" =~ ([0-9]+)\.([0-9]+) ]]; then
    if [ "${BASH_REMATCH[1]}" -lt 2 ] || { [ "${BASH_REMATCH[1]}" -eq 2 ] && [ "${BASH_REMATCH[2]}" -lt 28 ]; }; then
        printf '%s\n' 'Git 2.28+ is required. Upgrade Git and rerun.' >&2; exit 2
    fi
fi
native_path() { if [ "$platform" = windows ]; then cygpath -am "$1"; else printf '%s\n' "$1"; fi; }
absolute_path() {
    local value=$1
    case "$value" in '~/'*) value="$HOME/${value:2}" ;; esac
    if [ "$platform" = windows ]; then cygpath -au "$value"
    else case "$value" in /*) printf '%s\n' "$value" ;; *) printf '%s/%s\n' "$(pwd -P)" "$value" ;; esac; fi
}
shell_quote() { printf "'"; printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf "'"; }
if [ -z "$bc_path" ]; then
    if [ "$platform" = windows ]; then names=(BComp.exe BCompare.exe); else names=(bcomp bcompare); fi
    for candidate in "${names[@]}"; do
        found=$(command -v "$candidate" || true)
        if [ -n "$found" ]; then bc_path=$found; break; fi
    done
    if [ -z "$bc_path" ] && [ "$platform" = windows ]; then
        for base in "${PROGRAMFILES:-C:/Program Files}" 'C:/Program Files (x86)'; do
            for directory in 'Beyond Compare 5' 'Beyond Compare 4' 'Beyond Compare 3' 'Beyond Compare'; do
                for executable in BComp.exe BCompare.exe; do
                    candidate="$base/$directory/$executable"
                    if [ -f "$candidate" ]; then bc_path=$candidate; break 3; fi
                done
            done
        done
    elif [ -z "$bc_path" ] && [ "$platform" = macos ]; then
        for candidate in '/usr/local/bin/bcomp' '/opt/homebrew/bin/bcomp' '/Applications/Beyond Compare.app/Contents/MacOS/bcomp' '/Applications/Beyond Compare.app/Contents/MacOS/bcompare'; do
            if [ -f "$candidate" ]; then bc_path=$candidate; break; fi
        done
    fi
fi
if [ -z "$bc_path" ] || [ ! -f "$bc_path" ]; then
    printf '%s\n' 'MISSING: Beyond Compare (or invalid --bc-path).' >&2
    case "$platform" in
        macos) printf '%s\n' '  brew install --cask beyond-compare' '  Then: Beyond Compare > Install Command Line Tools' >&2 ;;
        *) printf '%s\n' '  Install from https://www.scootersoftware.com/download' >&2 ;;
    esac
    printf '%s\n' 'Rerun with --bc-path PATH for a custom installation. No config was changed.' >&2
    exit 2
fi
bc_path=$(native_path "$bc_path")
if [ -z "$git_config" ]; then
    if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then git_config=$GIT_CONFIG_GLOBAL
    elif [ -f "$HOME/.gitconfig" ]; then git_config="$HOME/.gitconfig"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" ]; then git_config="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
    else git_config="$HOME/.gitconfig"; fi
fi
git_config=$(absolute_path "$git_config")
get_original() { git config --file "$git_config" --includes --get "$1" 2>/dev/null || true; }
if [ -z "$install_dir" ]; then install_dir=$(get_original gitkit.installDir); fi
install_dir=$(absolute_path "${install_dir:-$HOME/.local/share/git-cli-kit}")
if [ -z "$lazy_config" ]; then
    if [ -n "${LG_CONFIG_FILE:-}" ]; then lazy_config=${LG_CONFIG_FILE##*,}
    else lazy_config="$(lazygit --print-config-dir | tr -d '\r')/config.yml"; fi
fi
lazy_config=$(absolute_path "$lazy_config")
printf 'Platform: %s\nBCompare: %s\nGit config: %s\nLazygit config: %s\nHelpers: %s\n' "$platform" "$bc_path" "$git_config" "$lazy_config" "$install_dir"
work=$(mktemp -d "${TMPDIR:-/tmp}/git-cli-setup.XXXXXXXX")
work=$(CDPATH= cd "$work" && pwd -P); work_parent=${work%/*}
git_stage=''; write_stage=''; backup_dir=''; applying=false
targets=(); existed=(); backups=()
finish() {
    result=$?; trap - EXIT
    if [ "$result" -ne 0 ] && "$applying"; then
        printf '%s\n' 'Setup failed; restoring files from this run.' >&2
        for ((i=${#targets[@]}-1;i>=0;i--)); do
            if [ "${existed[$i]}" = yes ]; then cp -p "${backups[$i]}" "${targets[$i]}" || true
            else rm -f -- "${targets[$i]}" || true; fi
        done
    fi
    [ -z "$git_stage" ] || rm -f -- "$git_stage"
    [ -z "$write_stage" ] || rm -f -- "$write_stage"
    if [ "${work%/*}" = "$work_parent" ] && [[ "${work##*/}" == git-cli-setup.* ]]; then rm -rf -- "$work"; fi
    exit "$result"
}
trap finish EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
input=/dev/null; [ ! -f "$lazy_config" ] || input=$lazy_config
awk -v body="$kit_dir/lazygit-commands.yml" -f "$kit_dir/merge-lazygit.awk" "$input" > "$work/config.yml"
if "$check_only"; then
    printf '%s\n' 'Dependencies and supported block-YAML structure are valid. Check only; no configuration written.'; exit 0
fi
mkdir -p "$(dirname "$git_config")"
git_stage=$(mktemp "$(dirname "$git_config")/.git-cli-stage.XXXXXXXX")
if [ -f "$git_config" ]; then cp -p "$git_config" "$git_stage"; fi
get_setting() { git config --file "$git_stage" --includes --get "$1" 2>/dev/null || true; }
set_setting() { git config --file "$git_stage" --replace-all "$1" "$2"; }
while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in ''|\#*) continue ;; esac
    if "$lazy_only"; then continue; fi
    case "$key" in
        user.name|user.email) [ -z "$(get_setting "$key")" ] || continue ;;
        safe.directory)
            "$no_trust" && continue
            if ! git config --file "$git_stage" --includes --get-all safe.directory 2>/dev/null | grep -Fx -- "$value" >/dev/null; then
                git config --file "$git_stage" --add safe.directory "$value"
            fi
            continue ;;
    esac
    set_setting "$key" "$value"
done < "$kit_dir/profile.conf"
bash_path=$(native_path "$BASH")
make_alias() {
    local script=$1 operation=${2:-} command
    command="$(shell_quote "$bash_path") $(shell_quote "$(native_path "$install_dir/$script")")"
    [ -z "$operation" ] || command="$command $(shell_quote "$operation")"
    printf '!f() { cd -- "${GIT_PREFIX:-.}" && %s "$@"; }; f' "$command"
}
set_setting alias.lgedit "$(make_alias git-tools.sh edit)"
set_setting alias.mt 'mergetool --tool=bc'
set_setting gitkit.installDir "$(native_path "$install_dir")"
set_setting merge.tool bc
set_setting mergetool.bc.path "$bc_path"
set_setting mergetool.bc.cmd '"$merge_tool_path" -solo "$LOCAL" "$REMOTE" "$BASE" "$MERGED"'
set_setting mergetool.bc.trustExitCode false
set_setting mergetool.keepBackup true
if ! "$lazy_only"; then
    set_setting diff.tool bc
    set_setting difftool.bc.path "$bc_path"
    set_setting difftool.bc.cmd '"$merge_tool_path" -solo "$LOCAL" "$REMOTE"'
    set_setting alias.rv "$(make_alias git-rv.sh)"
    set_setting alias.graph "$(make_alias git-tools.sh graph)"
    set_setting alias.fh "$(make_alias git-tools.sh fh)"
    if [ "$platform" = windows ]; then set_setting core.longpaths true; fi
    [ -z "$user_name" ] || set_setting user.name "$user_name"
    [ -z "$user_email" ] || set_setting user.email "$user_email"
    [ -z "$temp_root" ] || set_setting rv.tempRoot "$(native_path "$(absolute_path "$temp_root")")"
    if [ -n "$editor" ]; then set_setting core.editor "$editor"
    elif [ -z "$(get_setting core.editor)" ]; then
        for candidate in code cursor vim nano vi; do
            if command -v "$candidate" >/dev/null 2>&1; then
                case "$candidate" in code|cursor) set_setting core.editor "$candidate --wait" ;; *) set_setting core.editor "$candidate" ;; esac
                break
            fi
        done
    fi
    if [ -z "$(get_setting credential.helper)" ]; then
        if [ "$platform" = windows ]; then
            for candidate in manager manager-core; do
                if git "credential-$candidate" --version >/dev/null 2>&1; then set_setting credential.helper "$candidate"; break; fi
            done
        elif [ "$platform" = macos ] && [ -f "$(git --exec-path)/git-credential-osxkeychain" ]; then set_setting credential.helper osxkeychain; fi
    fi
fi
git config --file "$git_stage" --list >/dev/null
apply_file() {
    local source=$1 target=$2 staging index old
    if [ -f "$target" ] && cmp -s "$source" "$target"; then return; fi
    if [ -z "$backup_dir" ]; then backup_dir="$install_dir/backups/$(date +%Y%m%d-%H%M%S)-$$"; mkdir -p "$backup_dir"; fi
    index=${#targets[@]}; old="$backup_dir/$index-$(basename "$target").bak"
    targets+=("$target")
    if [ -f "$target" ]; then cp -p "$target" "$old"; existed+=(yes); else existed+=(no); fi
    backups+=("$old")
    printf '%s\t%s\t%s\n' "$target" "${existed[$index]}" "$old" >> "$backup_dir/manifest.tsv"
    mkdir -p "$(dirname "$target")"
    staging=$(mktemp "$(dirname "$target")/.git-cli-write.XXXXXXXX"); write_stage=$staging
    if [ -f "$target" ]; then cp -p "$target" "$staging"; else chmod 600 "$staging"; fi
    cat "$source" > "$staging"; mv -f "$staging" "$target"; write_stage=''; cmp -s "$source" "$target"
}
applying=true
apply_file "$kit_dir/git-rv.sh" "$install_dir/git-rv.sh"
apply_file "$kit_dir/git-tools.sh" "$install_dir/git-tools.sh"
apply_file "$work/config.yml" "$lazy_config"
apply_file "$git_stage" "$git_config"
applying=false
if [ -z "$backup_dir" ]; then printf '%s\n' 'Already configured. No files changed; no duplicate shortcuts were added.'
else printf 'Updated %s files. Backup: %s\n' "${#targets[@]}" "$backup_dir"; fi
printf '%s\n' 'Ready: git rv / git mt / git ui. Lazygit Files: e, Ctrl+B, F7. Restart lazygit to reload.'
