#!/usr/bin/env bash
# Requires Bash 3.2+ and Git; no Python or language package manager.
set -eo pipefail

native_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

temp_root=$(git config --path --get rv.tempRoot || true)
case "$temp_root" in
    '') temp_root="$HOME/.git-rv/temp" ;;
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) temp_root="$HOME/$temp_root" ;;
esac
mkdir -p "$temp_root"
temp_root=$(CDPATH= cd "$temp_root" && pwd -P)

filtered=false
for arg in "$@"; do
    case "$arg" in
        --) break ;;
        --author|--author=*|--committer|--committer=*|--grep|--grep=*) filtered=true ;;
    esac
done
if ! "$filtered"; then
    export TMPDIR="$(native_path "$temp_root")"
    exec git difftool -d -y "$@"
fi

log_args=()
paths=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --) shift; paths=("$@"); break ;;
        --author|--committer|--grep|--since|--until|--after|--before|--max-count|-n)
            [ "$#" -ge 2 ] || { printf 'git rv: %s requires a value.\n' "$1" >&2; exit 2; }
            log_args+=("$1" "$2"); shift 2 ;;
        --author=*|--committer=*|--grep=*|--since=*|--until=*|--after=*|--before=*|--max-count=*|--branches=*|--tags=*|--remotes=*)
            log_args+=("$1"); shift ;;
        --all-match|--invert-grep|--regexp-ignore-case|-i|--fixed-strings|-F|--extended-regexp|-E|--basic-regexp|--perl-regexp|-P|--first-parent|--no-merges|--merges|--all|--branches|--tags|--remotes|--not|-n[0-9]*)
            log_args+=("$1"); shift ;;
        -*) printf 'git rv: unsupported filtered-review option: %s\n' "$1" >&2; exit 2 ;;
        *) log_args+=("$1"); shift ;;
    esac
done

review_root=$(mktemp -d "$temp_root/git-rv-filtered-XXXXXXXX")
review_root=$(CDPATH= cd "$review_root" && pwd -P)
cleanup() {
    result=$?
    trap - EXIT
    # Only this invocation's canonical, uniquely-created child can be removed.
    if [ "${review_root%/*}" = "$temp_root" ] && [[ "${review_root##*/}" == git-rv-filtered-* ]]; then
        rm -rf -- "$review_root"
    else
        printf 'git rv: refusing cleanup of unexpected path: %s\n' "$review_root" >&2
        result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git log "${log_args[@]}" --topo-order --reverse --no-color --no-decorate \
    --date=short '--format=%H%x00%P%x00%an%x00%ad%x00%s' -z -- > "$review_root/log.bin"
if [ ! -s "$review_root/log.bin" ]; then
    printf '%s\n' 'git rv: no matching commits in the selected history.'
    exit 0
fi
mkdir "$review_root/before" "$review_root/after"
count=0
file_count=0
merge_count=0

export_blob() {
    local mode=$1 oid=$2 destination=$3 side=$4
    mkdir -p "$(dirname "$destination")"
    if [ "$mode" = 160000 ]; then
        printf 'Subproject commit %s\n' "$oid" > "$destination"
    else
        git cat-file blob "$oid" > "$destination"
    fi
    # Snapshot mtimes are artificial: Git does not store file mtimes. Distinct
    # times make same-size edits visible in size+date folder comparison mode.
    if [ "$side" = before ]; then
        touch -t 200001010000.00 "$destination"
    else
        touch -t 200001020000.00 "$destination"
    fi
}

while IFS= read -r -d '' sha; do
    IFS= read -r -d '' parents
    IFS= read -r -d '' author
    IFS= read -r -d '' commit_date
    IFS= read -r -d '' subject
    if [ -n "$parents" ]; then
        first_parent=${parents%% *}
        git diff-tree --no-commit-id --raw --no-abbrev -r -z --no-renames --no-relative \
            "$first_parent" "$sha" -- "${paths[@]}" > "$review_root/changes.bin"
    else
        git diff-tree --no-commit-id --raw --no-abbrev -r -z --no-renames --no-relative \
            --root "$sha" -- "${paths[@]}" > "$review_root/changes.bin"
    fi
    [ -s "$review_root/changes.bin" ] || continue
    count=$((count + 1))
    printf -v folder '%05d_%s_%.12s' "$count" "$commit_date" "$sha"
    before="$review_root/before/$folder"
    after="$review_root/after/$folder"
    mkdir "$before" "$after"
    while IFS= read -r -d '' header && IFS= read -r -d '' name; do
        case "$name" in
            /*|../*|*/../*|*/..) printf 'git rv: invalid Git path: %s\n' "$name" >&2; exit 2 ;;
        esac
        IFS=' ' read -r old_mode new_mode old_oid new_oid status <<< "$header"
        old_mode=${old_mode#:}
        if [ "$old_mode" != 000000 ]; then export_blob "$old_mode" "$old_oid" "$before/$name" before; fi
        if [ "$new_mode" != 000000 ]; then export_blob "$new_mode" "$new_oid" "$after/$name" after; fi
        file_count=$((file_count + 1))
    done < "$review_root/changes.bin"
    printf '%s | %s | %s\n' "$folder" "$author" "$subject"
    printf '%s | %s | %s\n' "$sha" "$author" "$subject" >> "$review_root/commits.txt"
    case "$parents" in *' '*) merge_count=$((merge_count + 1)) ;; esac
done < "$review_root/log.bin"

if [ "$count" -eq 0 ]; then
    printf '%s\n' 'git rv: matching commits contain no changes in the selected paths.'
    exit 0
fi
tool=$(git config --path --get difftool.bc.path || true)
[ -n "$tool" ] || tool=$(command -v bcomp || command -v bcompare || true)
[ -n "$tool" ] || { printf '%s\n' 'git rv: Beyond Compare is missing. Rerun setup or configure difftool.bc.path.' >&2; exit 2; }
printf 'git rv: %s commits, %s changed-file entries; opening ONE read-only directory comparison.\n' "$count" "$file_count"
if [ "$merge_count" -gt 0 ]; then printf '%s\n' 'Merge commits are compared with their first parent.'; fi
MSYS2_ARG_CONV_EXCL='*' "$tool" -solo -readonly \
    "$(native_path "$review_root/before")" "$(native_path "$review_root/after")"
