#!/bin/bash
# Read-only checks of an existing app bundle; never signs, uploads, or launches it.
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $# == 2 ]] || fail 'Usage: scripts/verify-app.sh --local|--release /path/to/保持清醒.app'
mode=$1
app=$2
[[ $mode == --local || $mode == --release ]] || fail 'Choose --local or --release.'
[[ -d $app ]] || fail 'App bundle not found.'
require_macos_tools
umask 077
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/keep-awake-verify.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
if [[ $mode == --release ]]; then
    verify_notarized_app "$app" "$work_dir"
    printf 'PASS: universal macOS 13+ app; Developer ID, notarization ticket, and Gatekeeper checks.\n'
else
    verify_layout "$app" "$work_dir"
    verify_signature "$app" "$work_dir" local
    printf 'PASS: universal macOS 13+ local build, with a valid ad-hoc signature.\n'
fi
