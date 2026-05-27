#!/usr/bin/env bats
# Tests for lib/desktop/instance-management.zsh — add/list/remove/rename
# of Claude Desktop instances in ~/.ckipper/desktop.json.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Install a fake /Applications/Claude.app under the per-test $TMP_HOME and
# point the desktop module at it via the documented env override. Required
# before any `desktop add` test because the real add flow refuses when the
# system Claude.app is missing.
_install_fake_claude_app() {
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    export _CKIPPER_DESKTOP_SYSTEM_APP="$TMP_HOME/FakeClaude.app"
    export _CKIPPER_TEST_CLAUDE_APP="$TMP_HOME/FakeClaude.app"
    mkdir -p "$_CKIPPER_DESKTOP_SYSTEM_APP/Contents/MacOS"
    mkdir -p "$_CKIPPER_DESKTOP_SYSTEM_APP/Contents/Resources"
}

# ── desktop add ──────────────────────────────────────────────────────────

@test "desktop add registers a new instance and writes registry entry" {
    _install_fake_claude_app

    run_ckipper desktop add work

    [ "$status" -eq 0 ]
    [ -f "$CKIPPER_DIR/desktop.json" ]
    local recorded_dir
    recorded_dir=$(jq -r '.instances.work.user_data_dir' "$CKIPPER_DIR/desktop.json")
    [ "$recorded_dir" = "$HOME/.claude-desktop-work" ]
    local recorded_bundle
    recorded_bundle=$(jq -r '.instances.work.app_bundle_path' "$CKIPPER_DIR/desktop.json")
    [ "$recorded_bundle" = "$HOME/Applications/Claude-Work.app" ]
    [ -d "$HOME/.claude-desktop-work" ]
    [ -d "$HOME/Applications/Claude-Work.app/Contents/MacOS" ]
}

@test "desktop add refuses an invalid name" {
    _install_fake_claude_app

    run_ckipper desktop add "Bad Name"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "desktop add refuses an empty name with a usage hint" {
    _install_fake_claude_app

    run_ckipper desktop add

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "desktop add refuses a duplicate name" {
    _install_fake_claude_app

    run_ckipper desktop add work
    run_ckipper desktop add work

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already registered" ]]
}

@test "desktop add refuses when /Applications/Claude.app is absent" {
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    export _CKIPPER_DESKTOP_SYSTEM_APP="$TMP_HOME/NoSuchApp.app"

    run_ckipper desktop add work

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Claude.app" ]]
}

@test "desktop add refuses when bundle path already exists" {
    _install_fake_claude_app
    mkdir -p "$HOME/Applications/Claude-Work.app"

    run_ckipper desktop add work

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already exists" ]]
}

@test "desktop add prints deep-link tip on the second add" {
    _install_fake_claude_app

    run_ckipper desktop add work
    run_ckipper desktop add personal

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper desktop login" ]]
}
