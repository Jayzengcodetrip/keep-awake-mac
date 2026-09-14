#!/bin/bash
# Produce an ad-hoc signed universal app for local testing. Does not launch it.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ $# == 0 ]] || fail 'Usage: scripts/build.sh'
require_macos_tools
umask 077
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/keep-awake-build.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
staged_app="$work_dir/$KEEP_AWAKE_APP_NAME"
build_app "$staged_app" "$work_dir"
/usr/bin/codesign --force --sign - "$staged_app" >"$work_dir/sign.log" 2>&1
verify_signature "$staged_app" "$work_dir" local

# Replace only this script's documented build output, never an installed app.
mkdir -p "$KEEP_AWAKE_ROOT/build/local"
local_app="$KEEP_AWAKE_ROOT/build/local/$KEEP_AWAKE_APP_NAME"
if [[ -e $local_app ]]; then
    rm -rf "$local_app"
fi
mv "$staged_app" "$local_app"
printf 'Local test app created: build/local/%s\n' "$KEEP_AWAKE_APP_NAME"
printf 'Universal arm64 + x86_64; macOS 13+. Ad-hoc signed, not notarized.\n'
