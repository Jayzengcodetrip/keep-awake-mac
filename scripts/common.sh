#!/bin/bash
# Shared build helpers. This file is sourced by the command scripts.

set -euo pipefail

KEEP_AWAKE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KEEP_AWAKE_APP_NAME='保持清醒.app'
KEEP_AWAKE_EXECUTABLE='KeepAwake'
KEEP_AWAKE_BUNDLE_ID='org.keepawake.macos'
KEEP_AWAKE_MIN_MACOS='13.0'

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_macos_tools() {
    [[ $(uname -s) == Darwin ]] || fail 'Build and release require macOS.'
    command -v xcrun >/dev/null 2>&1 || fail 'Install Apple Xcode Command Line Tools.'
    xcrun --find swiftc >/dev/null 2>&1 || fail 'The selected Apple developer tools do not include Swift.'
    xcrun --find lipo >/dev/null 2>&1 || fail 'The selected Apple developer tools do not include lipo.'
}

app_version() {
    local version
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$KEEP_AWAKE_ROOT/Info.plist")
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use a numeric major.minor.patch version in Info.plist.'
    printf '%s' "$version"
}

# Compile only reviewed source files, never a developer's existing .app bundle.
# Private work directories and compiler logs are deleted by the calling script.
build_app() {
    local output_app=$1
    local work_dir=$2
    local sdk arch binary
    local sources=()
    require_macos_tools
    /usr/bin/plutil -lint "$KEEP_AWAKE_ROOT/Info.plist" >/dev/null
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$KEEP_AWAKE_ROOT/Info.plist") == "$KEEP_AWAKE_BUNDLE_ID" ]] || fail 'Unexpected bundle identifier.'
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$KEEP_AWAKE_ROOT/Info.plist") == "$KEEP_AWAKE_EXECUTABLE" ]] || fail 'Unexpected executable name.'
    [[ $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$KEEP_AWAKE_ROOT/Info.plist") == "$KEEP_AWAKE_MIN_MACOS" ]] || fail 'Info.plist must require macOS 13.0.'
    app_version >/dev/null
    sdk=$(xcrun --sdk macosx --show-sdk-path)

    mkdir -p "$work_dir/slices" "$work_dir/module-cache" "$output_app/Contents/MacOS" "$output_app/Contents/Resources"
    cp "$KEEP_AWAKE_ROOT/Info.plist" "$output_app/Contents/Info.plist"
    # An optional reviewed app icon is the only resource copied by this script.
    if [[ -f "$KEEP_AWAKE_ROOT/Resources/AppIcon.icns" ]]; then
        cp "$KEEP_AWAKE_ROOT/Resources/AppIcon.icns" "$output_app/Contents/Resources/AppIcon.icns"
        /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$output_app/Contents/Info.plist"
    fi

    (
        cd "$KEEP_AWAKE_ROOT"
        shopt -s nullglob
        sources=(Sources/*.swift)
        ((${#sources[@]} > 0)) || fail 'No Sources/*.swift files found.'
        for arch in arm64 x86_64; do
            printf 'Compiling %s for macOS %s or later…\n' "$arch" "$KEEP_AWAKE_MIN_MACOS"
            if ! xcrun swiftc -O -whole-module-optimization -gnone \
                -module-name KeepAwake -emit-executable \
                -target "${arch}-apple-macosx${KEEP_AWAKE_MIN_MACOS}" \
                -sdk "$sdk" -module-cache-path "$work_dir/module-cache" \
                -file-compilation-dir /KeepAwake \
                -debug-prefix-map "$KEEP_AWAKE_ROOT=/KeepAwake" \
                -file-prefix-map "$KEEP_AWAKE_ROOT=/KeepAwake" \
                -framework AppKit -framework IOKit -framework ServiceManagement \
                "${sources[@]}" -o "$work_dir/slices/$arch" \
                >"$work_dir/compiler-$arch.log" 2>&1; then
                # Compile diagnostics are useful locally; they are not packaged.
                cat "$work_dir/compiler-$arch.log" >&2
                fail "Compilation failed for $arch."
            fi
            /usr/bin/strip -S -x "$work_dir/slices/$arch"
        done
    )
    binary="$output_app/Contents/MacOS/$KEEP_AWAKE_EXECUTABLE"
    xcrun lipo -create "$work_dir/slices/arm64" "$work_dir/slices/x86_64" -output "$binary"
    chmod 755 "$binary"
    # Reject common absolute build paths before signing. Never print a match.
    /usr/bin/strings "$binary" >"$work_dir/binary-strings.txt"
    if /usr/bin/grep -Eq '/Users/|/private/var/folders/|/var/folders/|/private/tmp/' "$work_dir/binary-strings.txt"; then
        fail 'A private build path was detected in the executable; no package was produced.'
    fi
    verify_layout "$output_app" "$work_dir"
}

verify_layout() {
    local app=$1
    local work_dir=$2
    local binary="$app/Contents/MacOS/$KEEP_AWAKE_EXECUTABLE"
    local architectures
    [[ -f $binary ]] || fail 'The app executable is missing.'
    /usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$KEEP_AWAKE_BUNDLE_ID" ]] || fail 'Unexpected app bundle identifier.'
    [[ $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist") == "$KEEP_AWAKE_MIN_MACOS" ]] || fail 'Unexpected minimum system version.'
    architectures=$(xcrun lipo -archs "$binary")
    [[ $architectures == 'x86_64 arm64' || $architectures == 'arm64 x86_64' ]] || fail 'The executable must contain exactly arm64 and x86_64.'
    xcrun vtool -show-build "$binary" >"$work_dir/build-version.txt"
    /usr/bin/awk '$1 == "minos" { count++; if ($2 != "13.0") bad = 1 } END { exit (bad || count != 2) }' \
        "$work_dir/build-version.txt" || fail 'Both executable slices must target macOS 13.0.'
}

verify_signature() {
    local app=$1
    local work_dir=$2
    local mode=$3
    /usr/bin/codesign --verify --strict --all-architectures "$app" >"$work_dir/signature-check.log" 2>&1 \
        || fail 'App signature verification failed.'
    /usr/bin/codesign --display --verbose=4 "$app" >"$work_dir/signature-details.log" 2>&1 \
        || fail 'Cannot inspect the app signature.'
    if [[ $mode == release ]]; then
        /usr/bin/grep -q '^Authority=Developer ID Application:' "$work_dir/signature-details.log" \
            || fail 'A Developer ID Application signature is required for a public release.'
        /usr/bin/grep -q '^Timestamp=' "$work_dir/signature-details.log" \
            || fail 'The public release signature must include a secure timestamp.'
        /usr/bin/grep -q 'flags=.*runtime' "$work_dir/signature-details.log" \
            || fail 'The public release must enable Hardened Runtime.'
    elif [[ $mode == local ]]; then
        /usr/bin/grep -q '^Signature=adhoc$' "$work_dir/signature-details.log" \
            || fail 'The local test build must use an ad-hoc signature.'
    else
        fail 'Unknown signature verification mode.'
    fi
}

verify_notarized_app() {
    local app=$1
    local work_dir=$2
    verify_layout "$app" "$work_dir"
    verify_signature "$app" "$work_dir" release
    xcrun stapler validate "$app" >"$work_dir/stapler-validate.log" 2>&1 \
        || fail 'The app does not have a valid stapled notarization ticket.'
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app" >"$work_dir/gatekeeper.log" 2>&1 \
        || fail 'Gatekeeper did not accept the app; no public release was produced.'
    /usr/bin/grep -q 'source=Notarized Developer ID' "$work_dir/gatekeeper.log" \
        || fail 'Gatekeeper did not identify the app as Notarized Developer ID.'
}
