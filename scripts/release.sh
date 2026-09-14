#!/bin/bash
# Deliberately contacts Apple's notary service only when a maintainer runs it.
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf '%s\n' 'Usage: scripts/release.sh' \
        'Required environment: KEEP_AWAKE_SIGNING_IDENTITY, KEEP_AWAKE_NOTARY_PROFILE' \
        'Optional environment: KEEP_AWAKE_NOTARY_TIMEOUT (default: 30m)' \
        'Signs with Developer ID, submits to Apple, and creates a verified public ZIP.'
    exit 0
fi
[[ $# == 0 ]] || fail 'Usage: scripts/release.sh'
[[ -n ${KEEP_AWAKE_SIGNING_IDENTITY:-} ]] || fail 'Set KEEP_AWAKE_SIGNING_IDENTITY to your Developer ID Application identity.'
[[ ${KEEP_AWAKE_SIGNING_IDENTITY} != - ]] || fail 'Ad-hoc signing cannot create a public release.'
[[ -n ${KEEP_AWAKE_NOTARY_PROFILE:-} ]] || fail 'Set KEEP_AWAKE_NOTARY_PROFILE to an existing Keychain profile.'
require_macos_tools
xcrun --find notarytool >/dev/null 2>&1 || fail 'Select Apple developer tools with notarytool.'
xcrun --find stapler >/dev/null 2>&1 || fail 'Select Apple developer tools with stapler.'

version=$(app_version)
release_name="KeepAwake-$version-universal"
output_dir="$KEEP_AWAKE_ROOT/dist/$release_name"
[[ ! -e $output_dir ]] || fail 'This version already has a release output; bump the version or move it aside.'
umask 077
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/keep-awake-release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
staged_app="$work_dir/$KEEP_AWAKE_APP_NAME"
build_app "$staged_app" "$work_dir"

printf 'Signing the new universal app with Developer ID…\n'
if ! /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$KEEP_AWAKE_SIGNING_IDENTITY" "$staged_app" >"$work_dir/sign.log" 2>&1; then
    fail 'Developer ID signing failed. Check the selected identity and local Keychain access.'
fi
verify_signature "$staged_app" "$work_dir" release

# ZIP is a transport container. Staple the ticket to the .app, then create a new ZIP.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$work_dir/notary-upload.zip"
printf 'Submitting to Apple and waiting for notarization…\n'
if ! xcrun notarytool submit "$work_dir/notary-upload.zip" \
    --keychain-profile "$KEEP_AWAKE_NOTARY_PROFILE" --wait \
    --timeout "${KEEP_AWAKE_NOTARY_TIMEOUT:-30m}" --output-format json \
    >"$work_dir/notary-result.json" 2>"$work_dir/notary-error.log"; then
    fail 'Notarization submission or wait failed. No public package was created; inspect Apple notary history locally before retrying.'
fi
status=$(/usr/bin/plutil -extract status raw -o - "$work_dir/notary-result.json" 2>/dev/null) \
    || fail 'Apple returned no readable notarization status.'
[[ $status == Accepted ]] || fail 'Apple did not accept this build. No public package was created.'
xcrun stapler staple "$staged_app" >"$work_dir/stapler.log" 2>&1 \
    || fail 'Attaching the notarization ticket failed. No public package was created.'
verify_notarized_app "$staged_app" "$work_dir"

mkdir "$work_dir/public-output" "$work_dir/extracted"
zip_name="$release_name.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$work_dir/public-output/$zip_name"
# Validate what recipients actually extract, including its stapled ticket.
/usr/bin/ditto -x -k "$work_dir/public-output/$zip_name" "$work_dir/extracted"
verify_notarized_app "$work_dir/extracted/$KEEP_AWAKE_APP_NAME" "$work_dir"
(
    cd "$work_dir/public-output"
    /usr/bin/shasum -a 256 "$zip_name" >SHA256SUMS.txt
)
cat >"$work_dir/public-output/release-checks.txt" <<EOF
KeepAwake $version
Minimum macOS: 13.0
Architectures: arm64, x86_64
Developer ID Application signature: PASS
Hardened Runtime and secure timestamp: PASS
Apple notarization: Accepted
Stapled ticket: PASS
Gatekeeper assessment: Notarized Developer ID
Extracted ZIP app signature and ticket: PASS
EOF

# Nothing is placed in dist until all the preceding gates have passed.
mkdir -p "$KEEP_AWAKE_ROOT/dist"
[[ ! -e $output_dir ]] || fail 'Another release created this version while notarization was running.'
mv "$work_dir/public-output" "$output_dir"
printf 'Verified public package: dist/%s/%s\n' "$release_name" "$zip_name"
printf 'Only the ZIP, SHA256SUMS.txt, and release-checks.txt are public release assets.\n'
