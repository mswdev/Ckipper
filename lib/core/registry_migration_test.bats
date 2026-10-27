#!/usr/bin/env bats
# Module-level tests for the accounts.json auto-migration in
# lib/core/registry.zsh. Any older version is upgraded to the current one
# through _CORE_REGISTRY_UPGRADE_FILTER, with a backup written first.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_REGISTRY_VERSION=3
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source registry (and its utils dep) then run zsh_cmd.
_run_registry() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_REGISTRY_VERSION="${CKIPPER_REGISTRY_VERSION:-3}" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/utils.zsh\"; source \"$REPO_ROOT/lib/core/registry.zsh\"; $zsh_cmd"
}

# Seed a v2 registry fixture: one account with the Docker preferences block.
_seed_v2_registry() {
    cat > "$CKIPPER_REGISTRY" <<'EOF'
{
  "version": 2,
  "default": "personal",
  "accounts": {
    "personal": {
      "config_dir": "/tmp/.claude-personal",
      "keychain_service": "Claude Code-credentials-abc123",
      "registered_at": "2026-04-30T12:00:00Z",
      "preferences": {"always_docker": false, "always_firewall": false, "ssh_forward": true}
    }
  }
}
EOF
    chmod 600 "$CKIPPER_REGISTRY"
}

@test "v2 registry migrates to the current version on _core_registry_check_version" {
    _seed_v2_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' "$CKIPPER_REGISTRY")" = "3" ]
    [[ "$output" =~ "Migrating accounts.json v2 → v3" ]]
}

@test "migration drops the Docker preferences block" {
    _seed_v2_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.accounts.personal | has("preferences")' "$CKIPPER_REGISTRY")" = "false" ]
}

@test "migration preserves the other account fields" {
    _seed_v2_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.default' "$CKIPPER_REGISTRY")" = "personal" ]
    [ "$(jq -r '.accounts.personal.config_dir' "$CKIPPER_REGISTRY")" = "/tmp/.claude-personal" ]
    [ "$(jq -r '.accounts.personal.registered_at' "$CKIPPER_REGISTRY")" = "2026-04-30T12:00:00Z" ]
}

@test "v1 registry (no preferences block) also migrates to the current version" {
    echo '{"version":1,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work"}}}' > "$CKIPPER_REGISTRY"
    chmod 600 "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' "$CKIPPER_REGISTRY")" = "3" ]
    [ "$(jq -r '.accounts.work.config_dir' "$CKIPPER_REGISTRY")" = "/tmp/.claude-work" ]
}

@test "migration writes a backup containing the pre-migration JSON" {
    _seed_v2_registry
    local pre_contents; pre_contents=$(cat "$CKIPPER_REGISTRY")

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local -a backups
    backups=( "$CKIPPER_REGISTRY".v2.bak.* )
    [ -f "${backups[0]}" ]
    [ "$(cat "${backups[0]}")" = "$pre_contents" ]
    assert_file_mode "${backups[0]}" "600"
}

@test "migration is idempotent (no-op on an already-current registry)" {
    _seed_v2_registry
    _run_registry "_core_registry_check_version"
    [ "$status" -eq 0 ]
    local after_first; after_first=$(cat "$CKIPPER_REGISTRY")

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    [ "$(cat "$CKIPPER_REGISTRY")" = "$after_first" ]
    [ "$(ls -1 "$CKIPPER_REGISTRY".v*.bak.* | wc -l | tr -d ' ')" = "1" ]
}

@test "a newer registry version is refused, not downgraded" {
    echo '{"version":9,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_check_version"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "registry version 9 not supported" ]]
    [ "$(jq -r '.version' "$CKIPPER_REGISTRY")" = "9" ]
}

@test "ckipper account list on a v2 registry triggers migration" {
    _seed_v2_registry

    run_ckipper account list

    [ "$status" -eq 0 ]
    [ "$(jq -r '.version' "$CKIPPER_REGISTRY")" = "3" ]
}
