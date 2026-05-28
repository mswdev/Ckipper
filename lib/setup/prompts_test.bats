#!/usr/bin/env bats
# Module-level tests for lib/setup/prompts.zsh.
# prompts.zsh is zsh-only (uses typeset -A iteration over schema arrays), so
# every assertion spawns a zsh subshell that sources the schema, core config,
# style, prompt, and prompts.zsh files, then runs the function under test
# (matching the pattern in prereqs_test.bats).
#
# CKIPPER_NO_GUM=1 forces the pure-zsh fallback path inside _core_prompt_*
# helpers so tests are deterministic regardless of whether `gum` is installed
# on the runner. bats `run` captures both stdout and stderr — the bool/input
# tests therefore assert on `${lines[-1]}` so the description and prompt label
# (which flow to stderr) do not collide with the value emitted to stdout.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":null,"accounts":{}}
JSON
}

teardown() {
    teardown_isolated_env
}

# Helper: source schema + core/config + core/style + core/prompt + setup/prompts in zsh,
# pipe stdin, run zsh_cmd, and let stderr/stdout merge into bats $output.
#
# Args: $1 — stdin payload (may be empty); $2 — zsh command to execute.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_prompts() {
    local stdin="$1" zsh_cmd="$2"
    run env CKIPPER_NO_GUM=1 \
            CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/prompt.zsh\"
            source \"$REPO_ROOT/lib/setup/prompts.zsh\"
            $zsh_cmd
        " <<<"$stdin"
}

@test "_ckipper_setup_prompts_summary lists every global-scoped key" {
    _run_prompts "" "_ckipper_setup_prompts_summary"

    [ "$status" -eq 0 ]
    [[ "$output" == *"notify_bell"* ]]
    [[ "$output" == *"default_branch"* ]]
    [[ "$output" == *"dep_install_cmd"* ]]
    [[ "$output" == *"projects_dir"* ]]
    [[ "$output" == *"ports"* ]]
    [[ "$output" == *"aliases_auto_source"* ]]
}

@test "_ckipper_setup_prompts_summary excludes account-scoped keys" {
    _run_prompts "" "_ckipper_setup_prompts_summary"

    [ "$status" -eq 0 ]
    [[ "$output" != *"always_docker"* ]]
    [[ "$output" != *"always_firewall"* ]]
    [[ "$output" != *"ssh_forward"* ]]
}

# Regression: descriptions intentionally do NOT appear in the summary
# anymore — they live in the pick-keys-to-customize picker labels (added
# in PR #43) so the user sees them at the moment they decide what to
# change. The summary stays compact and renders cleanly through gum's
# styled table. This test pins the new contract: descriptions in picker,
# not summary.
@test "_ckipper_setup_prompts_summary does not embed descriptions inline" {
    _run_prompts "" "_ckipper_setup_prompts_summary"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Bool. true = installer auto-adds the per-account aliases source line"* ]]
    [[ "$output" != *"Comma-separated int list. Container ports to forward to the host."* ]]
}

@test "_ckipper_setup_prompts_summary points at the picker for descriptions" {
    _run_prompts "" "_ckipper_setup_prompts_summary"

    [ "$status" -eq 0 ]
    [[ "$output" == *"description"* ]] || [[ "$output" == *"Tip:"* ]]
}

@test "_ckipper_setup_prompts_summary marks set values as (your config) and unset as (default)" {
    echo 'CKIPPER_NOTIFY_BELL="false"' >"$CKIPPER_DIR/docker/ckipper-config.zsh"

    _run_prompts "" "_ckipper_setup_prompts_summary"

    [ "$status" -eq 0 ]
    # The notify_bell row contains its set value AND the (your config) marker.
    local notify_row
    notify_row=$(printf '%s\n' "${lines[@]}" | grep notify_bell)
    [[ "$notify_row" == *"(your config)"* ]]
    [[ "$notify_row" == *"false"* ]]
    # An untouched row (e.g. dep_install_cmd) still says (default).
    local dep_row
    dep_row=$(printf '%s\n' "${lines[@]}" | grep dep_install_cmd)
    [[ "$dep_row" == *"(default)"* ]]
}

@test "_ckipper_setup_prompts_pick_keys prints all global keys when user accepts customize-all" {
    _run_prompts "y" "_ckipper_setup_prompts_pick_keys"

    [ "$status" -eq 0 ]
    [[ "$output" == *"notify_bell"* ]]
    [[ "$output" == *"default_branch"* ]]
    [[ "$output" == *"dep_install_cmd"* ]]
    [[ "$output" == *"projects_dir"* ]]
    [[ "$output" == *"ports"* ]]
    [[ "$output" == *"aliases_auto_source"* ]]
    [[ "$output" == *"worktrees_dir"* ]]
}

@test "_ckipper_setup_prompts_pick_keys excludes account-scoped keys when accepted" {
    _run_prompts "y" "_ckipper_setup_prompts_pick_keys"

    [ "$status" -eq 0 ]
    [[ "$output" != *"always_docker"* ]]
    [[ "$output" != *"always_firewall"* ]]
    [[ "$output" != *"ssh_forward"* ]]
}

@test "_ckipper_setup_prompts_pick_keys emits no global keys when user declines" {
    _run_prompts "n" "_ckipper_setup_prompts_pick_keys 2>/dev/null"

    [ "$status" -eq 0 ]
    # Decline path: no key names should appear on stdout.
    [[ "$output" != *"notify_bell"* ]]
    [[ "$output" != *"default_branch"* ]]
    [[ "$output" != *"dep_install_cmd"* ]]
}

@test "_ckipper_setup_prompts_one_key for a bool returns true on y" {
    _run_prompts "y" "_ckipper_setup_prompts_one_key notify_bell"

    [ "$status" -eq 0 ]
    # bats $output merges stdout+stderr; the value is the final line.
    local last="${lines[$((${#lines[@]} - 1))]}"
    [ "$last" = "true" ]
}

@test "_ckipper_setup_prompts_one_key for a bool returns false on n" {
    _run_prompts "n" "_ckipper_setup_prompts_one_key notify_bell"

    [ "$status" -eq 0 ]
    local last="${lines[$((${#lines[@]} - 1))]}"
    [ "$last" = "false" ]
}

@test "_ckipper_setup_prompts_one_key for a string returns the user's input" {
    _run_prompts "main" "_ckipper_setup_prompts_one_key default_branch"

    [ "$status" -eq 0 ]
    local last="${lines[$((${#lines[@]} - 1))]}"
    [ "$last" = "main" ]
}
