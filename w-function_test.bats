#!/usr/bin/env bats
# Characterization tests for the w() function in w-function.zsh.
#
# Purpose: regression net for Phases 2-4 (modularization + refactoring).
# These tests document ACTUAL current behavior.
#
# Important: w-function.zsh is zsh-only and sources ckipper.zsh at the
# bottom. Bats runs under bash, so every test spawns a zsh subprocess
# via `run env ... zsh -c "source w-function.zsh; w ..."`.

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export DOCKER_STUB_LOG="$TMP_HOME/docker.log"
    : > "$DOCKER_STUB_LOG"
    mkdir -p "$CKIPPER_DIR/docker"
    echo 'CKIPPER_PORTS=(3000 3030)' > "$CKIPPER_DIR/docker/w-config.zsh"
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
}

teardown() {
    teardown_isolated_env
}

# ── w with no args / usage ───────────────────────────────────────────

@test "w with no args prints usage and exits 1" {
    run_w
    # Note: w() returns 1 when called with no args (falls into the empty
    # project/worktree branch which prints usage and returns 1).
    [ "$status" -eq 1 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "w --list prints worktree header and exits 0" {
    run_w --list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Worktrees" || "$output" =~ "worktrees" || "$output" =~ "===" ]]
}

@test "w --help falls through to usage output and exits 1" {
    # Note: w has no --help flag. Passing --help is treated as a project name,
    # falls into the missing project/worktree check, prints usage, and exits 1.
    run_w --help
    [ "$status" -eq 1 ]
    [[ "$output" =~ [Uu]sage || "$output" =~ "Usage" ]]
}

# ── w with missing project ───────────────────────────────────────────

@test "w errors when no account is registered and a project is specified" {
    # With no default account set and no accounts in the registry, w() errors
    # before it even gets to the project-existence check.
    run_w nonexistent feature-x
    [ "$status" -ne 0 ]
    [[ "$output" =~ "account" || "$output" =~ "Account" ]]
}

@test "w errors when project dir does not exist under Developer" {
    # Register a default account so we get past the account check.
    echo '{"version":1,"default":"test","accounts":{"test":{"config_dir":"'"$TMP_HOME"'/.claude-test","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-test"
    run_w nonexistent feature-x
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Project" ]]
}

# ── w with valid project args ────────────────────────────────────────

@test "w with valid project and account reaches worktree-creation logic" {
    # Register a default account and create a real git repo.
    echo '{"version":1,"default":"test","accounts":{"test":{"config_dir":"'"$TMP_HOME"'/.claude-test","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-test" "$TMP_HOME/Developer/myapp"
    (cd "$TMP_HOME/Developer/myapp" && git init -q && git commit --allow-empty -q -m "init")
    # w() will fail at "git fetch origin develop" (no remote) but that's expected.
    # The key characterization: it gets into the worktree-creation flow and
    # prints "Creating worktree:" before failing on the fetch.
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/w-function.zsh\"; w myapp test-branch"
    [[ "$output" =~ "Creating worktree" || "$output" =~ "fetch" || "$output" =~ "origin" ]]
}

# ── w --rm ───────────────────────────────────────────────────────────

@test "w --rm with no args prints usage and exits 1" {
    run_w --rm
    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage || "$output" =~ "Usage" ]]
}

@test "w --rm errors when worktree path does not exist" {
    echo '{"version":1,"default":"test","accounts":{"test":{"config_dir":"'"$TMP_HOME"'/.claude-test","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    run_w --rm myapp nonexistent-branch
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Worktree" || "$output" =~ "worktree" ]]
}

# ── w --firewall validation ──────────────────────────────────────────

@test "w errors when --firewall is passed without --docker" {
    echo '{"version":1,"default":"test","accounts":{"test":{"config_dir":"'"$TMP_HOME"'/.claude-test","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-test" "$TMP_HOME/Developer/myapp"
    run_w myapp some-branch --firewall
    [ "$status" -ne 0 ]
    [[ "$output" =~ "--firewall" || "$output" =~ "firewall" ]]
}

# ── tab completion version sentinel ──────────────────────────────────

# The completion-file regeneration mechanism relies on the literal
# "# w-completion-version=N" sentinel inside the single-quoted heredoc
# matching the CKIPPER_COMPLETION_VERSION variable referenced in the grep
# check immediately above. If a future bump only updates one side,
# existing installs silently fail to regenerate. This test guards
# against that drift.
@test "w-function.zsh: completion version sentinel matches outer variable" {
    local outer inner
    outer=$(grep -E '^CKIPPER_COMPLETION_VERSION=' "$REPO_ROOT/w-function.zsh" | head -1 | cut -d= -f2)
    inner=$(grep -E '^# w-completion-version=' "$REPO_ROOT/w-function.zsh" | head -1 | cut -d= -f2)
    [ -n "$outer" ]
    [ -n "$inner" ]
    [ "$outer" = "$inner" ]
}
