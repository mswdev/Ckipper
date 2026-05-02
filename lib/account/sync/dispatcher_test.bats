#!/usr/bin/env bats
# Unit tests for lib/account/sync/dispatcher.zsh — arg parsing skeleton.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env CKIPPER_DIR="$CKIPPER_DIR" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/dispatcher.zsh\"; $*"
}

@test "parse_args identifies --dry-run flag" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --dry-run
        echo "from=$_SYNC_FROM"
        echo "targets=${_SYNC_TARGETS[*]}"
        echo "dry_run=$_SYNC_DRY_RUN"'
    [[ "$output" == *"from=personal"* ]]
    [[ "$output" == *"targets=work"* ]]
    [[ "$output" == *"dry_run=true"* ]]
}

@test "parse_args identifies --yes flag" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --yes
        echo "yes=$_SYNC_YES"'
    [[ "$output" == *"yes=true"* ]]
}

@test "parse_args identifies multiple targets" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work client1 client2
        echo "targets=${(j:,:)_SYNC_TARGETS}"'
    [[ "$output" == *"targets=work,client1,client2"* ]]
}

@test "parse_args identifies --include with comma list" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --include mcp,settings
        echo "include=$_SYNC_INCLUDE"'
    [[ "$output" == *"include=mcp,settings"* ]]
}

@test "parse_args identifies --exclude with comma list" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --include all --exclude prefs
        echo "include=$_SYNC_INCLUDE"
        echo "exclude=$_SYNC_EXCLUDE"'
    [[ "$output" == *"include=all"* ]]
    [[ "$output" == *"exclude=prefs"* ]]
}

@test "parse_args identifies --force" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --force
        echo "force=$_SYNC_FORCE"'
    [[ "$output" == *"force=true"* ]]
}

@test "parse_args returns 1 on unknown flag" {
    run_in_zsh '_ckipper_account_sync_parse_args personal work --bogus'
    [ "$status" -ne 0 ]
}

@test "parse_args allows empty positionals (drop-to-picker)" {
    run_in_zsh '
        _ckipper_account_sync_parse_args
        echo "from=${_SYNC_FROM:-EMPTY}"
        echo "n_targets=${#_SYNC_TARGETS[@]}"'
    [[ "$output" == *"from=EMPTY"* ]]
    [[ "$output" == *"n_targets=0"* ]]
}
