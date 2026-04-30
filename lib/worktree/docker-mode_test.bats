#!/usr/bin/env bats
# Module-level tests for lib/worktree/docker-mode.zsh.
# Covers compute_volumes (via build_base_args), compute_envs (add_optional_args),
# and extract_credentials JSON validation.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    export DOCKER_STUB_LOG="$TMP_HOME/docker.log"
    : > "$DOCKER_STUB_LOG"
    # Provide reasonable defaults for globals docker-mode reads.
    export CKIPPER_WT_PATH="$TMP_HOME/worktrees/myapp/feature-x"
    export CKIPPER_PROJECTS_DIR="$TMP_HOME/Developer"
    export CKIPPER_WT_PROJECT="myapp"
    export CKIPPER_WT_BRANCH="feature-x"
    export CKIPPER_WT_ACTIVE_ACCOUNT="test"
    export CKIPPER_WT_ACTIVE_CONFIG_DIR="$TMP_HOME/.claude-test"
    export CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE=""
    export CKIPPER_EXTRA_VOLUMES=()
    export CKIPPER_EXTRA_ENV=()
    export CKIPPER_WT_FLAG_FIREWALL=false
    export CKIPPER_PORTS=()
    export CKIPPER_WT_COMMAND=()
    mkdir -p "$CKIPPER_WT_ACTIVE_CONFIG_DIR"
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
        CKIPPER_WT_PATH="$CKIPPER_WT_PATH" \
        CKIPPER_PROJECTS_DIR="$CKIPPER_PROJECTS_DIR" \
        CKIPPER_WT_PROJECT="$CKIPPER_WT_PROJECT" \
        CKIPPER_WT_BRANCH="$CKIPPER_WT_BRANCH" \
        CKIPPER_WT_ACTIVE_ACCOUNT="$CKIPPER_WT_ACTIVE_ACCOUNT" \
        CKIPPER_WT_ACTIVE_CONFIG_DIR="$CKIPPER_WT_ACTIVE_CONFIG_DIR" \
        CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE="$CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE" \
        CKIPPER_WT_FLAG_FIREWALL="$CKIPPER_WT_FLAG_FIREWALL" \
        PATH="$PATH" \
        zsh -c "
            typeset -a CKIPPER_WT_DOCKER_ARGS=()
            typeset -a CKIPPER_EXTRA_VOLUMES=()
            typeset -a CKIPPER_EXTRA_ENV=()
            typeset -a CKIPPER_PORTS=()
            typeset -a CKIPPER_WT_COMMAND=()
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/keychain.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/worktree/ports.zsh\"
            source \"$REPO_ROOT/lib/worktree/build-image.zsh\"
            source \"$REPO_ROOT/lib/worktree/docker-mode.zsh\"
            $zsh_cmd
        "
}

@test "_ckipper_worktree_docker_build_base_args includes the worktree volume mount" {
    _run_docker_mode "_ckipper_worktree_docker_build_base_args; print -r -- \"\${CKIPPER_WT_DOCKER_ARGS[*]}\""

    [ "$status" -eq 0 ]
    [[ "$output" =~ "-v" ]]
    [[ "$output" =~ "$CKIPPER_WT_PATH:/workspace:rw" ]]
}

@test "_ckipper_worktree_docker_add_optional_args emits a warning when no credentials are provided" {
    _run_docker_mode "_ckipper_worktree_docker_build_base_args; _ckipper_worktree_docker_add_optional_args '' ''"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning" ]]
}

@test "_ckipper_worktree_docker_extract_credentials returns empty string when no keychain service is set" {
    export CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE=""

    _run_docker_mode "result=\$(_ckipper_worktree_docker_extract_credentials); print -r -- \"result=\$result\""

    [ "$status" -eq 0 ]
    [ "$output" = "result=" ]
}
