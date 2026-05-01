#!/usr/bin/env bats
# Module-level tests for lib/setup/dispatcher.zsh.
# dispatcher.zsh is zsh-only (uses typeset -A iteration over schema arrays
# and dynamic-scoped writes into a parent-frame `prefs` array), so every
# assertion spawns a zsh subshell that sources the schema, core (utils,
# registry, config, style, prompt), all setup modules, then redefines the
# heavy interactive helpers as no-ops before invoking the function under
# test (matching the pattern in apply_test.bats and prompts_test.bats).
#
# The stubs intentionally land AFTER sourcing dispatcher.zsh so they shadow
# the original definitions inside the subshell. CKIPPER_NO_GUM=1 forces the
# pure-zsh fallback path, and stdin is fed via ANSI-C `$'...'` so each `read`
# in `_core_prompt_confirm` receives a real newline.

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

# Helper: source schema + core + every setup module in zsh, install no-op
# stubs for the slow / interactive helpers, pipe stdin, run zsh_cmd.
#
# Args: $1 — stdin payload (may be empty); $2 — zsh command to execute.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_setup() {
    local stdin="$1" zsh_cmd="$2"
    run env CKIPPER_NO_GUM=1 \
            CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/prompt.zsh\"
            source \"$REPO_ROOT/lib/setup/prereqs.zsh\"
            source \"$REPO_ROOT/lib/setup/prompts.zsh\"
            source \"$REPO_ROOT/lib/setup/apply.zsh\"
            source \"$REPO_ROOT/lib/setup/dispatcher.zsh\"
            # Stubs override the heavy/interactive originals so the wizard
            # body can be exercised without brew, docker, or Claude /login.
            _ckipper_setup_prereqs() { return 0; }
            _ckipper_account_add() { echo \"STUB-ADD \$@\"; return 0; }
            _ckipper_worktree_build_image() { echo STUB-BUILD; return 0; }
            $zsh_cmd
        " <<<"$stdin"
}

@test "_ckipper_setup --help prints help text and exits 0" {
    _run_setup "" "_ckipper_setup --help"

    [ "$status" -eq 0 ]
    [[ "$output" == *"ckipper setup"* ]]
    [[ "$output" == *"interactive wizard"* ]]
}

@test "_ckipper_setup -h is equivalent to --help" {
    _run_setup "" "_ckipper_setup -h"

    [ "$status" -eq 0 ]
    [[ "$output" == *"ckipper setup"* ]]
}

@test "_ckipper_setup with all-decline answers completes successfully" {
    # Three "n" answers cover: customize? + register-account? + build-image?
    _run_setup $'n\nn\nn\n' "_ckipper_setup"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Welcome to Ckipper"* ]]
    [[ "$output" == *"Setup complete"* ]]
    [[ "$output" == *"Using current values."* ]]
}

@test "_ckipper_setup_offer_account prompts 'Add another' when accounts present" {
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":{}}}}
JSON

    _run_setup $'n\n' "_ckipper_setup_offer_account 2>&1"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Add another"* ]]
    [[ "$output" != *"Register a Claude account now"* ]]
}

@test "_ckipper_setup_offer_account prompts 'Register' when accounts empty" {
    _run_setup $'n\n' "_ckipper_setup_offer_account 2>&1"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Register a Claude account now"* ]]
    [[ "$output" != *"Add another"* ]]
}

@test "_ckipper_setup_offer_image_build skips build on decline" {
    _run_setup $'n\n' "_ckipper_setup_offer_image_build 2>&1"

    [ "$status" -eq 0 ]
    [[ "$output" != *"STUB-BUILD"* ]]
}

@test "_ckipper_setup_offer_image_build runs build on accept" {
    _run_setup $'y\n' "_ckipper_setup_offer_image_build 2>&1"

    [ "$status" -eq 0 ]
    [[ "$output" == *"STUB-BUILD"* ]]
}
