#!/usr/bin/env bats
# Module-level tests for lib/core/registry.zsh.
# Covers init, check_version, account_dir, registry_read, and update.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_REGISTRY_VERSION=1
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
        CKIPPER_REGISTRY_VERSION="${CKIPPER_REGISTRY_VERSION:-1}" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/utils.zsh\"; source \"$REPO_ROOT/lib/core/registry.zsh\"; $zsh_cmd"
}

@test "_core_registry_init creates a fresh registry with mode 600" {
    _run_registry "_core_registry_init"

    [ "$status" -eq 0 ]
    assert_file_exists "$CKIPPER_REGISTRY"
    assert_file_mode "$CKIPPER_REGISTRY" "600"
}

@test "_core_registry_init produces valid JSON with version 1" {
    _run_registry "_core_registry_init"

    [ "$status" -eq 0 ]
    local version
    version=$(jq -r '.version' "$CKIPPER_REGISTRY")
    [ "$version" = "1" ]
}

@test "_core_registry_init is idempotent (does not overwrite existing registry)" {
    echo '{"version":1,"default":"preserved","accounts":{}}' > "$CKIPPER_REGISTRY"
    chmod 600 "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_init"

    [ "$status" -eq 0 ]
    local default
    default=$(jq -r '.default' "$CKIPPER_REGISTRY")
    [ "$default" = "preserved" ]
}

@test "_core_registry_init rejects non-integer version" {
    export CKIPPER_REGISTRY_VERSION="not-a-number"

    _run_registry "_core_registry_init"

    [ "$status" -ne 0 ]
}

@test "_core_registry_check_version passes on matching version" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_check_version"

    [ "$status" -eq 0 ]
}

@test "_core_registry_check_version fails on version mismatch" {
    echo '{"version":99,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    _run_registry "_core_registry_check_version"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "version" ]]
}

@test "_core_account_dir returns config_dir for a known account" {
    echo '{"version":1,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    _run_registry "_core_account_dir work"

    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/.claude-work" ]
}

@test "_core_account_dir fails for an unknown account" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    _run_registry "_core_account_dir nobody"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# Regression: in zsh, an EXIT trap set inside a function fires when that
# function returns, regardless of `local_traps` in the caller. The previous
# implementation set the trap inside _core_registry_acquire_mkdir_lock, so
# the lockdir was removed before the caller's jq write — a concurrent writer
# could grab the lock and clobber the in-flight update. The trap must live
# in _core_registry_update_mkdir_fallback (the function that owns the
# critical section).
@test "_core_registry_acquire_mkdir_lock leaves lockdir intact for caller after acquire returns" {
    # Caller mimics the production pattern in _core_registry_update_mkdir_fallback:
    # declares its own `local lockdir` (so any stray trap referencing $lockdir resolves
    # in caller scope) and asserts the lockdir is still present when acquire returns.
    _run_registry '
        caller() {
            setopt local_options local_traps
            local lockdir="$CKIPPER_DIR/.registry.lock.d"
            _core_registry_acquire_mkdir_lock "$lockdir" || return 1
            [[ -d "$lockdir" ]] || {
                echo "BUG: lockdir was removed before caller could use it" >&2
                return 2
            }
            rmdir "$lockdir"
        }
        caller
    '

    [ "$status" -eq 0 ]
}

@test "_core_registry_update_mkdir_fallback releases lockdir after successful update" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    chmod 600 "$CKIPPER_REGISTRY"

    _run_registry '_core_registry_update_mkdir_fallback ".default = \"alice\""'

    [ "$status" -eq 0 ]
    [[ ! -d "$CKIPPER_DIR/.registry.lock.d" ]]
    local default
    default=$(jq -r '.default' "$CKIPPER_REGISTRY")
    [ "$default" = "alice" ]
}

@test "_core_registry_update_mkdir_fallback releases lockdir after jq failure" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    chmod 600 "$CKIPPER_REGISTRY"

    _run_registry '_core_registry_update_mkdir_fallback "this is not a valid jq filter @@@"'

    [ "$status" -ne 0 ]
    [[ ! -d "$CKIPPER_DIR/.registry.lock.d" ]]
}
