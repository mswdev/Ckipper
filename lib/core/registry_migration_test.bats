#!/usr/bin/env bats
# Module-level tests for the v1 -> v2 auto-migration in lib/core/registry.zsh.
# Covers detect, mutate, defaults, backup, idempotency, and existing-prefs merge.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_REGISTRY_VERSION=2
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source registry (and its utils dep) then run zsh_cmd.
# Mirrors the helper in registry_test.bats, but defaults the version env var to 2
# so the migration path under test is exercised.
_run_registry() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_REGISTRY_VERSION="${CKIPPER_REGISTRY_VERSION:-2}" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/utils.zsh\"; source \"$REPO_ROOT/lib/core/registry.zsh\"; $zsh_cmd"
}

# Seed a v1 registry fixture with a single account.
_seed_v1_registry() {
    cat > "$CKIPPER_REGISTRY" <<'EOF'
{
  "version": 1,
  "default": "personal",
  "accounts": {
    "personal": {
      "config_dir": "/tmp/.claude-personal",
      "keychain_service": "Claude Code-credentials",
      "registered_at": "2026-04-30T12:00:00Z"
    }
  }
}
EOF
    chmod 600 "$CKIPPER_REGISTRY"
}

@test "v1 registry migrates to v2 on _core_registry_check_version" {
    _seed_v1_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local v; v=$(jq -r '.version' "$CKIPPER_REGISTRY")
    [ "$v" = "2" ]
}

@test "v2 migration adds preferences with safe defaults" {
    _seed_v1_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local always_docker always_firewall ssh_forward
    always_docker=$(jq -r '.accounts.personal.preferences.always_docker' "$CKIPPER_REGISTRY")
    always_firewall=$(jq -r '.accounts.personal.preferences.always_firewall' "$CKIPPER_REGISTRY")
    ssh_forward=$(jq -r '.accounts.personal.preferences.ssh_forward' "$CKIPPER_REGISTRY")
    [ "$always_docker" = "false" ]
    [ "$always_firewall" = "false" ]
    [ "$ssh_forward" = "true" ]
}

@test "v2 migration preserves existing fields" {
    _seed_v1_registry

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local default config_dir keychain registered_at
    default=$(jq -r '.default' "$CKIPPER_REGISTRY")
    config_dir=$(jq -r '.accounts.personal.config_dir' "$CKIPPER_REGISTRY")
    keychain=$(jq -r '.accounts.personal.keychain_service' "$CKIPPER_REGISTRY")
    registered_at=$(jq -r '.accounts.personal.registered_at' "$CKIPPER_REGISTRY")
    [ "$default" = "personal" ]
    [ "$config_dir" = "/tmp/.claude-personal" ]
    [ "$keychain" = "Claude Code-credentials" ]
    [ "$registered_at" = "2026-04-30T12:00:00Z" ]
}

@test "v2 migration writes a backup file containing the pre-migration JSON" {
    _seed_v1_registry
    local pre_contents; pre_contents=$(cat "$CKIPPER_REGISTRY")

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local -a backups
    backups=( "$CKIPPER_REGISTRY".v1.bak.* )
    [ -f "${backups[0]}" ]
    local backup_contents; backup_contents=$(cat "${backups[0]}")
    [ "$backup_contents" = "$pre_contents" ]
}

@test "v2 migration is idempotent (no-op on already-v2)" {
    _seed_v1_registry

    # First call performs the migration.
    _run_registry "_core_registry_check_version"
    [ "$status" -eq 0 ]
    local after_first; after_first=$(cat "$CKIPPER_REGISTRY")
    local first_backup_count; first_backup_count=$(ls -1 "$CKIPPER_REGISTRY".v1.bak.* 2>/dev/null | wc -l | tr -d ' ')

    # Second call should observe v2 and do nothing further.
    sleep 1   # ensure any second backup would land in a distinct timestamp slot
    _run_registry "_core_registry_check_version"
    [ "$status" -eq 0 ]
    local after_second; after_second=$(cat "$CKIPPER_REGISTRY")
    local second_backup_count; second_backup_count=$(ls -1 "$CKIPPER_REGISTRY".v1.bak.* 2>/dev/null | wc -l | tr -d ' ')

    [ "$after_first" = "$after_second" ]
    [ "$first_backup_count" = "$second_backup_count" ]
}

@test "v2 migration preserves existing preferences (defaults merge under existing values)" {
    cat > "$CKIPPER_REGISTRY" <<'EOF'
{
  "version": 1,
  "default": "personal",
  "accounts": {
    "personal": {
      "config_dir": "/tmp/.claude-personal",
      "keychain_service": null,
      "preferences": {"ssh_forward": false}
    }
  }
}
EOF
    chmod 600 "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
    local ssh_forward always_docker always_firewall
    ssh_forward=$(jq -r '.accounts.personal.preferences.ssh_forward' "$CKIPPER_REGISTRY")
    always_docker=$(jq -r '.accounts.personal.preferences.always_docker' "$CKIPPER_REGISTRY")
    always_firewall=$(jq -r '.accounts.personal.preferences.always_firewall' "$CKIPPER_REGISTRY")
    [ "$ssh_forward" = "false" ]
    [ "$always_docker" = "false" ]
    [ "$always_firewall" = "false" ]
}
