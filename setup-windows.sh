#!/usr/bin/env sh
set -eu
kit_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
exec sh "$kit_dir/bootstrap.sh" windows "$@"
