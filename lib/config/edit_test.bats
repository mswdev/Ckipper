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

# I-1 regression: writeback must route through _core_registry_update so
# concurrent writers can't lose updates. Stubbing _core_registry_update to
# drop a marker proves the routing — bypass paths that mktemp+mv directly
# never invoke the stub.
@test "edit --account writeback routes through _core_registry_update" {
    local marker="$CKIPPER_DIR/_registry_update_called"

    EDITOR=true _run_config_edit "
        _core_registry_update() { : > '$marker'; return 0; }
        _ckipper_config_edit --account work
    "

    [ "$status" -eq 0 ]
    [ -f "$marker" ]
}

# I-2 regression: edited account preferences must be schema-validated before
# writeback. The previous implementation only ran `jq empty`, so users could
# add unknown keys, give known keys a wrong-typed value, or sneak in a
# global-scope key — and the writeback would silently persist all of it.
#
# Each test seeds a mock editor that overwrites the dumped file with the
# specified malformed JSON, then asserts the writeback aborts and the
# registry remains untouched.

# Write a one-shot zsh `editor` that overwrites $1 with the supplied JSON.
# Returns the path to the editor on stdout; the caller chmods+exports it.
_make_editor_writing() {
    local json="$1" path="$TMP_HOME/edit-stub-$$"
    cat >"$path" <<SH
#!/usr/bin/env zsh
print -r -- '$json' >"\$1"
SH
    chmod +x "$path"
    echo "$path"
}

@test "edit --account rejects unknown key and leaves registry untouched" {
    local editor; editor=$(_make_editor_writing '{"not_a_real_key": true}')
    local before; before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR="$editor" _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not_a_real_key"* ]]
    local after; after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
}

@test "edit --account rejects wrong-typed value for known key and leaves registry untouched" {
    local editor; editor=$(_make_editor_writing '{"always_docker": "rm -rf /"}')
    local before; before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR="$editor" _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"always_docker"* ]]
    local after; after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
}

@test "edit --account rejects global-scope key in account preferences" {
    # notify_bell is a real schema key with scope=global; it must not appear in
    # an account's preferences block even though the type matches.
    local editor; editor=$(_make_editor_writing '{"notify_bell": true}')
    local before; before=$(jq -S . "$CKIPPER_REGISTRY")

    EDITOR="$editor" _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"notify_bell"* ]]
    local after; after=$(jq -S . "$CKIPPER_REGISTRY")
    [ "$before" = "$after" ]
}

@test "edit --account accepts valid edits with all schema keys" {
    local editor; editor=$(_make_editor_writing '{"always_docker": false, "always_firewall": true, "ssh_forward": false}')

    EDITOR="$editor" _run_config_edit "_ckipper_config_edit --account work"

    [ "$status" -eq 0 ]
    run jq -r '.accounts.work.preferences.always_docker' "$CKIPPER_REGISTRY"
    [ "$output" = "false" ]
    run jq -r '.accounts.work.preferences.always_firewall' "$CKIPPER_REGISTRY"
    [ "$output" = "true" ]
    run jq -r '.accounts.work.preferences.ssh_forward' "$CKIPPER_REGISTRY"
    [ "$output" = "false" ]
}
