#!/usr/bin/env bats
# Module-level tests for lib/config/schema.zsh.
# Verifies the four schema arrays (TYPE, DEFAULT, SCOPE, DESCRIPTION) declare
# the expected keys with the expected values. Schema is data-only zsh; bats
# runs in bash, so each assertion spawns a zsh subshell that sources the file
# and prints the value under test.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

# Helper: source schema.zsh in zsh and print the array entry $1[$2].
_schema_lookup() {
    local array_name="$1" key="$2"
    run zsh -c "source \"$REPO_ROOT/lib/config/schema.zsh\"; print -- \"\${${array_name}[${key}]}\""
    [ "$status" -eq 0 ]
}

@test "schema declares known global keys" {
    _schema_lookup _CKIPPER_SCHEMA_TYPE default_branch
    [ "$output" = "string" ]

    _schema_lookup _CKIPPER_SCHEMA_TYPE dep_install_cmd
    [ "$output" = "string" ]

    _schema_lookup _CKIPPER_SCHEMA_TYPE notify_bell
    [ "$output" = "bool" ]

    _schema_lookup _CKIPPER_SCHEMA_TYPE aliases_auto_source
    [ "$output" = "bool" ]
}

@test "schema declares known per-account keys" {
    _schema_lookup _CKIPPER_SCHEMA_SCOPE always_docker
    [ "$output" = "account" ]

    _schema_lookup _CKIPPER_SCHEMA_SCOPE always_firewall
    [ "$output" = "account" ]

    _schema_lookup _CKIPPER_SCHEMA_SCOPE ssh_forward
    [ "$output" = "account" ]
}

@test "schema defaults preserve current behavior" {
    _schema_lookup _CKIPPER_SCHEMA_DEFAULT notify_bell
    [ "$output" = "true" ]

    _schema_lookup _CKIPPER_SCHEMA_DEFAULT aliases_auto_source
    [ "$output" = "true" ]

    _schema_lookup _CKIPPER_SCHEMA_DEFAULT dep_install_cmd
    [ "$output" = "npm install" ]

    _schema_lookup _CKIPPER_SCHEMA_DEFAULT always_docker
    [ "$output" = "false" ]

    _schema_lookup _CKIPPER_SCHEMA_DEFAULT always_firewall
    [ "$output" = "false" ]

    _schema_lookup _CKIPPER_SCHEMA_DEFAULT ssh_forward
    [ "$output" = "true" ]
}

@test "schema description present for every key" {
    # Walk every key in _CKIPPER_SCHEMA_TYPE and require a non-empty
    # _CKIPPER_SCHEMA_DESCRIPTION entry. Any missing key is printed by name.
    run zsh -c "
        source \"$REPO_ROOT/lib/config/schema.zsh\"
        for key in \"\${(@k)_CKIPPER_SCHEMA_TYPE}\"; do
            if [[ -z \"\${_CKIPPER_SCHEMA_DESCRIPTION[\$key]}\" ]]; then
                print -- \"missing description for \$key\"
                exit 1
            fi
        done
        exit 0
    "
    [ "$status" -eq 0 ]
}
