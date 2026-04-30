#!/usr/bin/env bats
# Module-level tests for lib/worktree/resolve-account.zsh.
# Covers env-override, registry lookup, registry default fallback, and error path.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source all required modules and call _ckipper_worktree_resolve_account; print a
# specific global var from the resolved state.  Propagates _ckipper_worktree_resolve_account's
# exit code so failure tests can assert status != 0.
_resolve_and_print() {
    local var_name="$1"
    local extra_env="${2:-}"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        PATH="$PATH" \
        $extra_env \
        zsh -c "
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/worktree/resolve-account.zsh\"
            _ckipper_worktree_resolve_account || exit \$?
            print -r -- \"\$$var_name\"
        "
}

@test "_ckipper_worktree_resolve_account populates CKIPPER_WT_ACTIVE_ACCOUNT from registry default" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"'"$TMP_HOME"'/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-work"

    _resolve_and_print "CKIPPER_WT_ACTIVE_ACCOUNT"

    [ "$status" -eq 0 ]
    [ "$output" = "work" ]
}

@test "_ckipper_worktree_resolve_account populates CKIPPER_WT_ACTIVE_CONFIG_DIR from registry" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"'"$TMP_HOME"'/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-work"

    _resolve_and_print "CKIPPER_WT_ACTIVE_CONFIG_DIR"

    [ "$status" -eq 0 ]
    [ "$output" = "$TMP_HOME/.claude-work" ]
}

@test "_ckipper_worktree_resolve_account picks account by CLAUDE_CONFIG_DIR env match" {
    echo '{"version":1,"default":null,"accounts":{"personal":{"config_dir":"'"$TMP_HOME"'/.claude-personal","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-personal"

    _resolve_and_print "CKIPPER_WT_ACTIVE_ACCOUNT" "CLAUDE_CONFIG_DIR=$TMP_HOME/.claude-personal"

    [ "$status" -eq 0 ]
    [ "$output" = "personal" ]
}

@test "_ckipper_worktree_resolve_account fails when no account can be resolved" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    _resolve_and_print "CKIPPER_WT_ACTIVE_ACCOUNT"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "no account" || "$output" =~ "no default" ]]
}
