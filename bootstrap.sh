#!/usr/bin/env sh
set -eu
platform=$1
shift
kit_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
if ! command -v bash >/dev/null 2>&1; then
    printf '%s\n' 'MISSING: Bash 3.2+. Install Bash using your OS package manager and rerun.' >&2
    exit 2
fi
exec bash "$kit_dir/setup-common.sh" "$platform" "$@"
