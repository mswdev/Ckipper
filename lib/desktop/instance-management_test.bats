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

# ── desktop list ─────────────────────────────────────────────────────────

@test "desktop list shows hint when no instances are registered" {
    _install_fake_claude_app

    run_ckipper desktop list

    [ "$status" -eq 0 ]
    [[ "$output" =~ "No Desktop instances" ]]
    [[ "$output" =~ "ckipper desktop add" ]]
}

@test "desktop list prints registered instances" {
    _install_fake_claude_app
    run_ckipper desktop add work
    run_ckipper desktop add personal

    run_ckipper desktop list

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
    [[ "$output" =~ "personal" ]]
    [[ "$output" =~ "Claude-Work" ]]
    [[ "$output" =~ "Claude-Personal" ]]
}

@test "desktop list shows running status via pgrep" {
    _install_fake_claude_app
    run_ckipper desktop add work

    PGREP_STUB_MATCH=1 run_ckipper desktop list

    [ "$status" -eq 0 ]
    [[ "$output" =~ "running" ]]
}

@test "desktop list shows stopped status when pgrep finds nothing" {
    _install_fake_claude_app
    run_ckipper desktop add work

    run_ckipper desktop list

    [ "$status" -eq 0 ]
    [[ "$output" =~ "stopped" ]]
}

# ── desktop remove ───────────────────────────────────────────────────────

# Run `ckipper desktop remove <name>` with stdin prefilled for the two
# y/N prompts. Mirrors run_ckipper but pipes the answers INTO the ckipper
# command (not into the source) — that ordering matters because zsh's `|`
# binds tighter than `;`. Saves repeating the same env-list per test.
_run_remove_with_answers() {
    local answers="$1" name="$2"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" CKIPPER_FORCE="${CKIPPER_FORCE:-1}" CKIPPER_NO_GUM=1 \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        _CKIPPER_DESKTOP_SYSTEM_APP="${_CKIPPER_DESKTOP_SYSTEM_APP:-}" \
        _CKIPPER_TEST_CLAUDE_APP="${_CKIPPER_TEST_CLAUDE_APP:-}" \
        PGREP_STUB_MATCH="${PGREP_STUB_MATCH:-0}" \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; printf '$answers' | ckipper desktop remove $name"
}

@test "desktop remove unregisters and keeps dirs when prompts are declined" {
    _install_fake_claude_app
    run_ckipper desktop add work

    _run_remove_with_answers 'n\nn\n' work

    [ "$status" -eq 0 ]
    [ -d "$HOME/.claude-desktop-work" ]
    [ -d "$HOME/Applications/Claude-Work.app" ]
    ! jq -e '.instances.work' "$CKIPPER_DIR/desktop.json" >/dev/null 2>&1
}

@test "desktop remove deletes dirs when both prompts accepted" {
    _install_fake_claude_app
    run_ckipper desktop add work

    _run_remove_with_answers 'y\ny\n' work

    [ "$status" -eq 0 ]
    [ ! -d "$HOME/.claude-desktop-work" ]
    [ ! -d "$HOME/Applications/Claude-Work.app" ]
}

@test "desktop remove refuses if instance is running" {
    _install_fake_claude_app
    run_ckipper desktop add work

    PGREP_STUB_MATCH=1 _run_remove_with_answers '' work

    [ "$status" -ne 0 ]
    [[ "$output" =~ "running" ]]
    # Registry entry MUST be preserved when the refusal fires.
    jq -e '.instances.work' "$CKIPPER_DIR/desktop.json" >/dev/null
}

@test "desktop remove fails clearly when instance not registered" {
    _install_fake_claude_app

    run_ckipper desktop remove ghost

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "desktop remove fails clearly when no registry exists yet" {
    _install_fake_claude_app

    run_ckipper desktop remove ghost

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── desktop rename ───────────────────────────────────────────────────────

@test "desktop rename moves data dir, regenerates bundle, updates registry" {
    _install_fake_claude_app
    run_ckipper desktop add work

    run_ckipper desktop rename work prod

    [ "$status" -eq 0 ]
    [ -d "$HOME/.claude-desktop-prod" ]
    [ ! -d "$HOME/.claude-desktop-work" ]
    [ -d "$HOME/Applications/Claude-Prod.app" ]
    [ ! -d "$HOME/Applications/Claude-Work.app" ]
    jq -e '.instances.prod' "$CKIPPER_DIR/desktop.json" >/dev/null
    ! jq -e '.instances.work' "$CKIPPER_DIR/desktop.json" >/dev/null 2>&1
    local recorded_dir
    recorded_dir=$(jq -r '.instances.prod.user_data_dir' "$CKIPPER_DIR/desktop.json")
    [ "$recorded_dir" = "$HOME/.claude-desktop-prod" ]
}

@test "desktop rename refuses collision with another registered instance" {
    _install_fake_claude_app
    run_ckipper desktop add work
    run_ckipper desktop add personal

    run_ckipper desktop rename work personal

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already registered" ]]
    # Both originals must survive the refusal.
    jq -e '.instances.work' "$CKIPPER_DIR/desktop.json" >/dev/null
    jq -e '.instances.personal' "$CKIPPER_DIR/desktop.json" >/dev/null
}

@test "desktop rename refuses if source is running" {
    _install_fake_claude_app
    run_ckipper desktop add work

    PGREP_STUB_MATCH=1 run_ckipper desktop rename work prod

    [ "$status" -ne 0 ]
    [[ "$output" =~ "running" ]]
    # Source must survive the refusal.
    jq -e '.instances.work' "$CKIPPER_DIR/desktop.json" >/dev/null
    [ -d "$HOME/.claude-desktop-work" ]
}

@test "desktop rename refuses if source is not registered" {
    _install_fake_claude_app
    run_ckipper desktop add other

    run_ckipper desktop rename ghost prod

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "desktop rename refuses identical old/new names" {
    _install_fake_claude_app
    run_ckipper desktop add work

    run_ckipper desktop rename work work

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Nn]othing\ to\ do ]]
}

@test "desktop rename refuses invalid new name" {
    _install_fake_claude_app
    run_ckipper desktop add work

    run_ckipper desktop rename work "Bad Name"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}
