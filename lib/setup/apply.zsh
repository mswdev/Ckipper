#!/usr/bin/env zsh
# Wizard "commit" step for `ckipper setup`. Takes the prompt-derived map of
# updates produced by `lib/setup/prompts.zsh` and writes each entry to either
# the global config file or the per-account preferences in the registry,
# routing via _core_config_set.
#
# Depends on:
#   - lib/config/schema.zsh   (`_CKIPPER_SCHEMA_*` arrays — read by _core_config_set)
#   - lib/core/config.zsh     (`_core_config_set`)
#   - lib/core/registry.zsh   (`_core_account_dir` — account-existence guard)
#
# Indirect-array convention (zsh 5.9 has no working `local -n` / `typeset -n`):
# both functions take the NAME of an associative array, not the array itself.
# Callers declare and populate the map, then pass the bare variable name:
#
#     typeset -A updates=([notify_bell]=false [dep_install_cmd]="pnpm install")
#     _ckipper_setup_apply_global updates
#
# Iteration uses `${(@kP)name}` for keys and `${${(P)name}[$key]}` for values.
# (Note: `${(P)name[$key]}` does NOT work in zsh 5.9 — the (P) flag binds to
# the outer expansion, so the subscript must live inside a nested ${...}.)

# Apply each entry of an associative array as a global config write. Stops on
# the first failure so a malformed value short-circuits the whole batch rather
# than producing a partial write.
#
# Args: $1 — name of an associative array (e.g. `updates`); each entry's key is
#   a schema key, each value is the new value to store.
# Returns: 0 if every write succeeded (including the empty-array case); 1 if
#   any underlying _core_config_set call failed (typically validation).
_ckipper_setup_apply_global() {
    local name="$1"
    local key value
    for key in "${(@kP)name}"; do
        value="${${(P)name}[$key]}"
        _core_config_set "$key" "$value" || return 1
    done
    return 0
}

# Apply each entry of an associative array as an account-scoped preference
# write. Validates account existence up front (mirroring the guard in
# `lib/config/`'s set handler) so a typo in the account name is rejected
# instead of silently creating a phantom account record.
#
# Args: $1 — account name; $2 — name of an associative array of preferences.
# Returns: 0 if the account exists and every write succeeded; 1 if the account
#   is unregistered or any underlying _core_config_set call failed.
# Errors (stderr): "Account '<name>' is not registered." — propagated from
#   _core_account_dir when $1 is unknown.
_ckipper_setup_apply_account() {
    local account="$1" name="$2"
    local key value
    _core_account_dir "$account" >/dev/null || return 1
    for key in "${(@kP)name}"; do
        value="${${(P)name}[$key]}"
        _core_config_set "$key" "$value" "$account" || return 1
    done
    return 0
}
