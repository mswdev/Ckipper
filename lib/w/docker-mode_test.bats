#!/usr/bin/env bats
# Module-level tests for lib/w/docker-mode.zsh.
# Covers compute_volumes (via build_base_args), compute_envs (add_optional_args),
# and extract_credentials JSON validation.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    export DOCKER_STUB_LOG="$TMP_HOME/docker.log"
    : > "$DOCKER_STUB_LOG"
    # Provide reasonable defaults for globals docker-mode reads.
    export W_WT_PATH="$TMP_HOME/worktrees/myapp/feature-x"
    export W_PROJECTS_DIR="$TMP_HOME/Developer"
    export W_PROJECT="myapp"
    export W_BRANCH="feature-x"
    export W_ACTIVE_ACCOUNT="test"
    export W_ACTIVE_CONFIG_DIR="$TMP_HOME/.claude-test"
    export W_ACTIVE_KEYCHAIN_SERVICE=""
    export W_EXTRA_VOLUMES=()
    export W_EXTRA_ENV=()
    export W_FLAG_FIREWALL=false
    export W_PORTS=()
    export W_COMMAND=()
    mkdir -p "$W_ACTIVE_CONFIG_DIR"
}

teardown() {
    teardown_isolated_env
}

# Helper: source docker-mode.zsh and all deps, then run zsh_cmd.
_run_docker_mode() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        DOCKER_STUB_LOG="$DOCKER_STUB_LOG" \
        W_WT_PATH="$W_WT_PATH" \
        W_PROJECTS_DIR="$W_PROJECTS_DIR" \
        W_PROJECT="$W_PROJECT" \
        W_BRANCH="$W_BRANCH" \
        W_ACTIVE_ACCOUNT="$W_ACTIVE_ACCOUNT" \
        W_ACTIVE_CONFIG_DIR="$W_ACTIVE_CONFIG_DIR" \
        W_ACTIVE_KEYCHAIN_SERVICE="$W_ACTIVE_KEYCHAIN_SERVICE" \
        W_FLAG_FIREWALL="$W_FLAG_FIREWALL" \
        PATH="$PATH" \
        zsh -c "
            typeset -a W_DOCKER_ARGS=()
            typeset -a W_EXTRA_VOLUMES=()
            typeset -a W_EXTRA_ENV=()
            typeset -a W_PORTS=()
            typeset -a W_COMMAND=()
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/keychain.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/w/ports.zsh\"
            source \"$REPO_ROOT/lib/w/build-image.zsh\"
            source \"$REPO_ROOT/lib/w/docker-mode.zsh\"
            $zsh_cmd
        "
}

@test "_w_docker_build_base_args includes the worktree volume mount" {
    _run_docker_mode "_w_docker_build_base_args; print -r -- \"\${W_DOCKER_ARGS[*]}\""

    [ "$status" -eq 0 ]
    [[ "$output" =~ "-v" ]]
    [[ "$output" =~ "$W_WT_PATH:/workspace:rw" ]]
}

@test "_w_docker_add_optional_args emits a warning when no credentials are provided" {
    _run_docker_mode "_w_docker_build_base_args; _w_docker_add_optional_args '' ''"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning" ]]
}

@test "_w_docker_extract_credentials returns empty string when no keychain service is set" {
    export W_ACTIVE_KEYCHAIN_SERVICE=""

    _run_docker_mode "result=\$(_w_docker_extract_credentials); print -r -- \"result=\$result\""

    [ "$status" -eq 0 ]
    [ "$output" = "result=" ]
}
