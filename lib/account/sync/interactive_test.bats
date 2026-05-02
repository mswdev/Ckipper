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

@test "_core_account_sync_list_accounts returns all account names" {
    run_in_zsh "_core_account_sync_list_accounts | sort | tr '\n' ','"
    [[ "$output" == *"client1,personal,work,"* ]]
}

@test "_core_account_sync_list_accounts_except filters source" {
    run_in_zsh "_core_account_sync_list_accounts_except personal | sort | tr '\n' ','"
    [[ "$output" == *"client1,work,"* ]]
    [[ "$output" != *"personal"* ]]
}
