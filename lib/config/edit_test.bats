#!/usr/bin/env bats
# Module-level tests for lib/config/edit.zsh.
# Verifies the round-trip flow used by `ckipper config edit --account <name>`:
# dump → edit → validate → writeback. The handler is zsh-only and depends on
# the schema, core/config, and core/registry primitives.
#
# EDITOR mocking: tests use `EDITOR=true` for a no-op edit and a one-line
# zsh script for the "overwrite-with-garbage" case. The script lives in
# $TMP_HOME and is written per-test rather than in setup so each test owns
# its mock.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    # v2 accounts.json fixture: one registered `work` account with an existing
    # always_docker preference so writeback round-trips have something to read.
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":{"always_docker":true}}}}
JSON
}

teardown() {
    teardown_isolated_env
}

# Helper: source schema + core/config + core/registry + edit, then run cmd.
# EDITOR is forwarded so each test can swap in its own mock.
_run_config_edit() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_REGISTRY_VERSION="${CKIPPER_REGISTRY_VERSION:-2}" \
        PATH="$PATH" \
        EDITOR="${EDITOR:-true}" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/config/edit.zsh\"
            $zsh_cmd
        "
}

@test "edit --account round-trips successfully when EDITOR is no-op" {
    local before
    before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR=true _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -eq 0 ]
    local after
    after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
    # Registry preferences for the account remain readable and intact.
    run jq -r '.accounts.work.preferences.always_docker' "$CKIPPER_REGISTRY"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "edit --account rejects malformed JSON and leaves registry untouched" {
    local mock_editor="$TMP_HOME/bad-editor"
    cat >"$mock_editor" <<'SH'
#!/usr/bin/env zsh
print -- "not json" >"$1"
SH
    chmod +x "$mock_editor"
    local before
    before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR="$mock_editor" _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not valid JSON"* ]]
    local after
    after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
}

@test "edit --account on unregistered account fails with registry error" {
    local before
    before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR=true _run_config_edit "_ckipper_config_edit --account ghost"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Account 'ghost' is not registered."* ]]
    local after
    after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
}

@test "edit with no flags opens the global config file" {
    # Seed the global file with a sentinel so we can detect that EDITOR
    # received it as its argument (EDITOR=cat prints the file's contents).
    local sentinel="CKIPPER_TEST_SENTINEL=42"
    echo "$sentinel" >>"$CKIPPER_DIR/docker/ckipper-config.zsh"

    EDITOR=cat _run_config_edit "_ckipper_config_edit"

    [ "$status" -eq 0 ]
    [[ "$output" == *"$sentinel"* ]]
}

@test "edit rejects positional arg with helpful suggestion" {
    EDITOR=true _run_config_edit "_ckipper_config_edit work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"takes no positional arguments"* ]]
    [[ "$output" == *"--account work"* ]]
}
