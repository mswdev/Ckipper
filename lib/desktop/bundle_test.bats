#!/usr/bin/env bats
# Tests for lib/desktop/bundle.zsh — the .app bundle generator.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export DESKTOP_BUNDLE_DIR="$TMP_HOME/Applications"
    mkdir -p "$DESKTOP_BUNDLE_DIR"
}

teardown() {
    teardown_isolated_env
}

# Helper that sources bundle.zsh in a clean zsh subshell and runs the cmd.
_run_bundle() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" PATH="$PATH" \
        _CKIPPER_TEST_CLAUDE_APP="${_CKIPPER_TEST_CLAUDE_APP:-}" \
        _CKIPPER_TEST_LSREGISTER="${_CKIPPER_TEST_LSREGISTER:-}" \
        zsh -c "source \"$REPO_ROOT/lib/desktop/bundle.zsh\"; $zsh_cmd"
}

@test "bundle_write creates Contents/MacOS/launcher with correct shebang and --user-data-dir" {
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-Work.app"
    local data_dir="$TMP_HOME/.claude-desktop-work"
    _run_bundle "_ckipper_desktop_bundle_write work \"$bundle\" \"$data_dir\""

    [ "$status" -eq 0 ]
    [ -x "$bundle/Contents/MacOS/launcher" ]
    head -1 "$bundle/Contents/MacOS/launcher" | grep -q '^#!/bin/zsh'
    grep -q -- "--user-data-dir=\"$data_dir\"" "$bundle/Contents/MacOS/launcher"
}

@test "bundle_write creates Info.plist with required CFBundle keys" {
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-Work.app"
    _run_bundle "_ckipper_desktop_bundle_write work \"$bundle\" \"$TMP_HOME/.claude-desktop-work\""

    [ -f "$bundle/Contents/Info.plist" ]
    grep -q "<string>launcher</string>" "$bundle/Contents/Info.plist"
    grep -q "<string>dev.ckipper.claude.desktop.work</string>" "$bundle/Contents/Info.plist"
    grep -q "<string>Claude-Work</string>" "$bundle/Contents/Info.plist"
}

@test "bundle_write title-cases multi-segment names" {
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-Foo-Bar.app"
    _run_bundle "_ckipper_desktop_bundle_write foo-bar \"$bundle\" \"$TMP_HOME/.claude-desktop-foo-bar\""

    grep -q "<string>Claude-Foo-Bar</string>" "$bundle/Contents/Info.plist"
}

@test "bundle_write skips icon when Claude.app source is absent" {
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-X.app"
    export _CKIPPER_TEST_CLAUDE_APP="/nonexistent/Claude.app"
    _run_bundle "_ckipper_desktop_bundle_write x \"$bundle\" \"$TMP_HOME/.claude-desktop-x\""

    [ "$status" -eq 0 ]
    [ ! -f "$bundle/Contents/Resources/AppIcon.icns" ]
    ! grep -q "CFBundleIconFile" "$bundle/Contents/Info.plist"
}

@test "bundle_write copies icon and writes CFBundleIconFile when source exists" {
    # Fake a Claude.app icon source.
    local fake_app="$TMP_HOME/FakeClaude.app"
    mkdir -p "$fake_app/Contents/Resources"
    : > "$fake_app/Contents/Resources/AppIcon.icns"
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-Y.app"
    export _CKIPPER_TEST_CLAUDE_APP="$fake_app"
    _run_bundle "_ckipper_desktop_bundle_write y \"$bundle\" \"$TMP_HOME/.claude-desktop-y\""

    [ "$status" -eq 0 ]
    [ -f "$bundle/Contents/Resources/AppIcon.icns" ]
    grep -q "CFBundleIconFile" "$bundle/Contents/Info.plist"
}

@test "bundle_write tolerates missing lsregister" {
    local bundle="$DESKTOP_BUNDLE_DIR/Claude-Z.app"
    export _CKIPPER_TEST_LSREGISTER="/nonexistent/lsregister"
    _run_bundle "_ckipper_desktop_bundle_write z \"$bundle\" \"$TMP_HOME/.claude-desktop-z\""

    [ "$status" -eq 0 ]
}

@test "bundle_write creates the parent directory if missing" {
    local bundle="$TMP_HOME/nested/deeper/Applications/Claude-A.app"
    _run_bundle "_ckipper_desktop_bundle_write a \"$bundle\" \"$TMP_HOME/.claude-desktop-a\""

    [ "$status" -eq 0 ]
    [ -d "$bundle/Contents/MacOS" ]
}
