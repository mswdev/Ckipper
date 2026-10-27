#!/usr/bin/env bats
# Tests for lib/account/doctor-groups.zsh — the doctor's "Sync groups" section.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Run the group checks and print the WARN/FAIL counters after them.
run_group_checks() {
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="linux" \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
            _ckipper_doctor_groups; echo \"fail=\$_CKIPPER_DOCTOR_FAIL warn=\$_CKIPPER_DOCTOR_WARN\""
}

# Write a registry from "<name>:<group>:<memory dir>" triples. An empty group
# leaves the account ungrouped; the first account named in a group is its
# master. An empty memory dir leaves env unset.
seed_grouped_accounts() {
    local registry='{"version":4,"default":null,"groups":{},"accounts":{}}' spec name group memory_dir
    for spec in "$@"; do
        IFS=: read -r name group memory_dir <<<"$spec"
        local dir="$TMP_HOME/.claude-$name"
        mkdir -p "$dir"
        if [[ -n "$memory_dir" ]]; then
            jq -n --arg m "$memory_dir" '{env: {CLAUDE_CODE_REMOTE_MEMORY_DIR: $m}}' > "$dir/settings.json"
        else
            echo '{}' > "$dir/settings.json"
        fi
        registry=$(jq --arg n "$name" --arg d "$dir" --arg g "$group" '
            .accounts[$n] = {config_dir: $d, registered_at: "t"}
            | if $g == "" then . else .accounts[$n].group = $g
                | (if .groups[$g] == null then .groups[$g] = {master: $n} else . end) end
        ' <<<"$registry")
    done
    echo "$registry" > "$CKIPPER_REGISTRY"
}

@test "doctor passes two groups that each have their own memory dir" {
    seed_grouped_accounts personal:personal:/mem personal-2:personal:/mem aff:aff:/mem-work aff-2:aff:/mem-work

    run_group_checks

    [[ "$output" =~ "group personal: master personal, memory dir /mem" ]]
    [[ "$output" =~ "group aff: master aff, memory dir /mem-work" ]]
    [[ "$output" =~ "fail=0 warn=0" ]]
}

@test "doctor fails when two groups share a memory dir" {
    seed_grouped_accounts personal:personal:/mem aff:aff:/mem

    run_group_checks

    [[ "$output" =~ "FAIL" ]]
    [[ "$output" =~ "share memory dir /mem" ]]
    [[ "$output" =~ "fail=1" ]]
}

@test "doctor warns when a member's memory dir differs from its master's" {
    seed_grouped_accounts personal:personal:/mem personal-2:personal:/mem-work

    run_group_checks

    [[ "$output" =~ "group personal: personal-2 use a different CLAUDE_CODE_REMOTE_MEMORY_DIR than master personal (/mem)" ]]
    [[ "$output" =~ "warn=1" ]]
}

@test "doctor warns about ungrouped accounts" {
    seed_grouped_accounts personal:personal:/mem stray::

    run_group_checks

    [[ "$output" =~ "sync is disabled for: stray" ]]
}

@test "doctor warns when a group has no master" {
    seed_grouped_accounts personal:personal:/mem
    jq '.groups.personal.master = null' "$CKIPPER_REGISTRY" > "$CKIPPER_REGISTRY.tmp" && mv "$CKIPPER_REGISTRY.tmp" "$CKIPPER_REGISTRY"

    run_group_checks

    [[ "$output" =~ "group personal has no master" ]]
}
