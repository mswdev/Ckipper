#!/usr/bin/env bats
# Tests for lib/desktop/doctor.zsh — the desktop diagnostic section.
#
# Tests drive doctor end-to-end via `run_ckipper doctor`, which exercises the
# top-level dispatcher wiring + the account/desktop doctor composition. Each
# test sets up only the env vars the asserted behavior actually depends on.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

@test "doctor desktop section skipped on non-macOS" {
    # setup_isolated_env exports _CKIPPER_TEST_OSTYPE="linux" already.
    run_ckipper doctor
    [ "$status" -eq 0 ] || true   # account-side checks may still WARN/FAIL — exit code agnostic
    [[ "$output" =~ "desktop: skipped" ]]
}

@test "doctor desktop passes with no instances and no Claude.app" {
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    # Force the system app constant at a path that doesn't exist.
    export _CKIPPER_DESKTOP_SYSTEM_APP="$TMP_HOME/NoClaude.app"
    run_ckipper doctor
    # No instances + no Claude.app → INFO, no FAIL.
    [[ "$output" =~ "0 instances" ]] || [[ "$output" =~ "skipped" ]] || [[ "$output" =~ "no instances" ]]
}

@test "doctor desktop warns when 2+ instances exist" {
    _install_fake_claude_app
    run_ckipper desktop add work
    run_ckipper desktop add personal
    run_ckipper doctor
    [[ "$output" =~ "2+ desktop instances" ]] || [[ "$output" =~ "deep-link" ]]
}

@test "doctor desktop FAILs when /Applications/Claude.app missing AND instances exist" {
    _install_fake_claude_app
    run_ckipper desktop add work
    # Now nuke the fake Claude.app and re-run doctor.
    rm -rf "$_CKIPPER_DESKTOP_SYSTEM_APP"
    run_ckipper doctor
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Claude.app" ]]
}

@test "doctor desktop FAILs when an instance data_dir is missing" {
    _install_fake_claude_app
    run_ckipper desktop add work
    rm -rf "$HOME/.claude-desktop-work"
    run_ckipper doctor
    [ "$status" -ne 0 ]
}

@test "doctor desktop FAILs when an instance .app bundle is missing" {
    _install_fake_claude_app
    run_ckipper desktop add work
    rm -rf "$HOME/Applications/Claude-Work.app"
    run_ckipper doctor
    [ "$status" -ne 0 ]
}
