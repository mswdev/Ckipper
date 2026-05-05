#!/usr/bin/env bats
# Unit tests for lib/account/sync/interactive.zsh — gum pickers.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    cat > "$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"personal","accounts":{
    "personal":{"config_dir":"$TMP_HOME/personal","keychain_service":null,"registered_at":"t","preferences":{}},
    "work":{"config_dir":"$TMP_HOME/work","keychain_service":null,"registered_at":"t","preferences":{}},
    "client1":{"config_dir":"$TMP_HOME/client1","keychain_service":null,"registered_at":"t","preferences":{}}
}}
JSON
    chmod 600 "$CKIPPER_REGISTRY"
}
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_NO_GUM=1 TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/core/registry.zsh\"; \
                source \"$REPO_ROOT/lib/core/prompt.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/interactive.zsh\"; $*"
}

@test "_ckipper_account_sync_list_accounts returns all account names" {
    run_in_zsh "_ckipper_account_sync_list_accounts | sort | tr '\n' ','"
    [[ "$output" == *"client1,personal,work,"* ]]
}

@test "_ckipper_account_sync_list_accounts_except filters source" {
    run_in_zsh "_ckipper_account_sync_list_accounts_except personal | sort | tr '\n' ','"
    [[ "$output" == *"client1,work,"* ]]
    [[ "$output" != *"personal"* ]]
}

# Regression: cancel from the comma-separated input prompt used to pass
# through as a 0-rc empty-output result, which the dispatcher then split
# into an empty array — masking cancel as "user submitted no targets".
# Now propagates the prompt's non-zero rc so callers can distinguish.
@test "_pick_targets_fallback returns non-zero on EOF (cancel)" {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_NO_GUM=1 TMP_HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/registry.zsh\"; \
                source \"$REPO_ROOT/lib/core/prompt.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/interactive.zsh\"; \
                _ckipper_account_sync_pick_targets_fallback work 2>/dev/null" </dev/null

    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "_pick_types fallback returns non-zero on EOF (cancel)" {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_NO_GUM=1 TMP_HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/registry.zsh\"; \
                source \"$REPO_ROOT/lib/core/prompt.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/interactive.zsh\"; \
                _ckipper_account_sync_pick_types 2>/dev/null" </dev/null

    [ "$status" -ne 0 ]
    [ -z "$output" ]
}
