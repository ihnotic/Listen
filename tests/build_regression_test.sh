#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/listen-build-test.XXXXXX")"

cleanup() {
    case "$TEST_ROOT" in
        "${TMPDIR:-/tmp}"/listen-build-test.*) rm -rf -- "$TEST_ROOT" ;;
        *) echo "Refusing to clean unexpected test directory: $TEST_ROOT" >&2 ;;
    esac
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

make_fixture() {
    local name="$1"
    local fixture="$TEST_ROOT/$name"

    mkdir -p "$fixture/bin" "$fixture/Listen/Resources"
    cp "$PROJECT_ROOT/build.sh" "$fixture/build.sh"
    chmod +x "$fixture/build.sh"

    printf 'plist\n' > "$fixture/Listen/Resources/Info.plist"
    printf 'icon\n' > "$fixture/Listen/Resources/AppIcon.icns"
    printf 'menu\n' > "$fixture/Listen/Resources/MenuBarIconTemplate.png"
    printf 'menu2x\n' > "$fixture/Listen/Resources/MenuBarIconTemplate@2x.png"
    printf 'entitlements\n' > "$fixture/Listen/Resources/Listen.entitlements"

    printf '%s\n' \
        '#!/bin/bash' \
        'mkdir -p .build/release' \
        'printf executable > .build/release/Listen' \
        > "$fixture/bin/swift"
    printf '%s\n' \
        '#!/bin/bash' \
        'printf "%s\n" "$SECURITY_OUTPUT"' \
        > "$fixture/bin/security"
    printf '%s\n' \
        '#!/bin/bash' \
        'printf "%s\n" "$@" > "$CODESIGN_LOG"' \
        > "$fixture/bin/codesign"
    chmod +x "$fixture/bin/swift" "$fixture/bin/security" "$fixture/bin/codesign"

    printf '%s\n' "$fixture"
}

assert_signing_identity() {
    local name="$1"
    local security_output="$2"
    local expected_identity="$3"
    local fixture
    local actual_identity

    fixture="$(make_fixture "$name")"
    SECURITY_OUTPUT="$security_output" \
    CODESIGN_LOG="$fixture/codesign.log" \
    PATH="$fixture/bin:/usr/bin:/bin" \
        "$fixture/build.sh" >/dev/null

    actual_identity="$(awk '$0 == "--sign" { getline; print; exit }' "$fixture/codesign.log")"
    [ "$actual_identity" = "$expected_identity" ] || \
        fail "$name used signing identity '$actual_identity'; expected '$expected_identity'"
}

assert_signing_identity \
    "ad-hoc" \
    "     0 valid identities found" \
    "-"

assert_signing_identity \
    "certificate" \
    "  1) E79D13CED0563C45F13F68CE3C135BBC04BAE742 \"Listen Dev\"" \
    "Listen Dev"

grep -Fq 'exact: "0.15.5"' "$PROJECT_ROOT/Package.swift" || \
    fail "FluidAudio must be pinned to the release validated with Listen 1.1 model backends"

if grep -Fq 'Listen Dev' "$PROJECT_ROOT/reinstall.sh"; then
    fail "reinstall.sh must not require a machine-specific signing identity"
fi

echo "PASS: build and dependency regressions"
