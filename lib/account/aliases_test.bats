#!/usr/bin/env bats
# Unit tests for lib/account/aliases.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/account/ modules).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run a zsh expression with the full ckipper environment sourced.
run_helper() {
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

# ── _ckipper_account_regenerate_aliases ───────────────────────────────────────

@test "regenerate_aliases creates aliases.zsh with mode 644" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    assert_file_mode "$out" "644"
}

@test "regenerate_aliases includes a launcher function for each registered account" {
    echo '{"version":4,"default":"dev","accounts":{"dev":{"config_dir":"/tmp/.claude-dev"}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    grep -q "claude-dev()" "$out"
}

# ── _ckipper_account_generate_account_launcher_function ───────────────────────

@test "generate_account_launcher_function emits a claude-<name> function" {
    run_helper '_ckipper_account_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude-work()" ]]
}

@test "generate_account_launcher_function sets CLAUDE_CONFIG_DIR in the emitted body" {
    run_helper '_ckipper_account_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "CLAUDE_CONFIG_DIR" ]]
    [[ "$output" =~ "/tmp/.claude-work" ]]
}

# ── bare-claude guard ─────────────────────────────────────────────────────────

# Run `claude` through a freshly generated aliases.zsh. $1 is the
# CLAUDE_CONFIG_DIR to export ("" leaves it unset).
_run_guarded_claude() {
    local config_dir="$1"
    run env -u CLAUDE_CONFIG_DIR HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" PATH="$PATH" \
        zsh -c "[[ -n '$config_dir' ]] && export CLAUDE_CONFIG_DIR='$config_dir'; source \"$CKIPPER_DIR/aliases.zsh\"; claude --version"
}

@test "bare-claude guard refuses plain claude when accounts are registered" {
    echo '{"version":4,"default":"dev","accounts":{"dev":{"config_dir":"'"$TMP_HOME"'/.claude-dev"}}}' > "$CKIPPER_REGISTRY"
    run_helper '_ckipper_account_regenerate_aliases'

    _run_guarded_claude ""

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Refusing to launch bare 'claude'" ]]
    [[ "$output" =~ "Use:  claude-dev" ]]
}

# Regression: inside a claude-<name> session CLAUDE_CONFIG_DIR is already
# set, so `claude` cannot touch ~/.claude — the guard used to refuse anyway.
@test "bare-claude guard lets claude through when CLAUDE_CONFIG_DIR is set" {
    echo '{"version":4,"default":"dev","accounts":{"dev":{"config_dir":"'"$TMP_HOME"'/.claude-dev"}}}' > "$CKIPPER_REGISTRY"
    run_helper '_ckipper_account_regenerate_aliases'

    _run_guarded_claude "$TMP_HOME/.claude-dev"

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Refusing" ]]
}
