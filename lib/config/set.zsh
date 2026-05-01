#!/usr/bin/env zsh
# `ckipper config set` handler. Thin wrapper over _core_config_set that adds
# CLI-level argument parsing, schema-membership validation, and an interactive
# value-prompt fallback.
#
# Phase-2 dependency: _core_prompt_input / _core_prompt_choose live in
# lib/core/prompt.zsh (not yet landed). Tests exercise only the explicit-value
# path; the prompt branches are unreachable until prompt.zsh is sourced.

# Absorb a positional token into the caller's key/value/has_value slots.
# First positional becomes the key; subsequent positionals overwrite the value
# and flip the has_value sentinel.
#
# Uses zsh indirect assignment via `(P)`-flagged parameter expansion — zsh
# 5.9 has no `typeset -n` namerefs.
#
# Args: $1 — token, $2 — name of caller's `key` var, $3 — name of caller's
#       `value` var, $4 — name of caller's `has_value` var.
# Returns: 0 always.
_ckipper_config_set_absorb_positional() {
    local token="$1" key_var="$2" value_var="$3" hasv_var="$4"
    if [[ -z "${(P)key_var}" ]]; then
        : ${(P)key_var::=$token}
        return 0
    fi
    : ${(P)value_var::=$token}
    : ${(P)hasv_var::=true}
}

# Verify the user supplied a key and that it exists in the schema. Surfaces
# both the no-key usage line and the unknown-key error so the caller can
# treat the result as a single validation gate.
#
# Args: $1 — candidate key (may be empty).
# Returns: 0 if the key is non-empty and in the schema; 1 otherwise.
# Errors (stderr):
#   "Usage: ckipper config set [--account <name>] <key> [value]" — no key.
#   "Unknown config key: '<key>'" — key not in schema.
_ckipper_config_set_validate_key() {
    local key="$1"
    if [[ -z "$key" ]]; then
        echo "Usage: ckipper config set [--account <name>] <key> [value]" >&2
        return 1
    fi
    if [[ -z "${_CKIPPER_SCHEMA_TYPE[$key]:-}" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
}

# Resolve the value to write: use the supplied value when has_value is "true",
# otherwise prompt the user via the Phase-2 input helper. _core_prompt_input
# writes back into the caller's variable directly.
#
# Args: $1 — schema key, $2 — has_value sentinel ("true"/"false"),
#       $3 — name of the value variable in the caller's scope.
# Returns: 0 on success; non-zero if the prompt is cancelled.
_ckipper_config_set_resolve_value() {
    local key="$1" has_value="$2" var_name="$3"
    [[ "$has_value" == "true" ]] && return 0
    local prompt_label="Value for $key (${_CKIPPER_SCHEMA_TYPE[$key]})"
    _core_prompt_input "$prompt_label" "$var_name"
}

# Set a configuration key. Routes to the global file or to the account
# preference store based on the schema scope.
#
# Args:
#   $1..$N — `[--account <name>] <key> [<value>]`. When <value> is omitted
#            the function prompts via _core_prompt_input (Phase-2).
#
# Returns: 0 on success; 1 on unknown key, unknown flag, validation failure,
#   missing --account on an account-scoped key, or unregistered account.
#
# Errors (stderr):
#   "Usage: ckipper config set [--account <name>] <key> [value]" — no key.
#   "Unknown config key: '<key>'" — when key is not in the schema.
#   "Unknown flag: '<flag>'" — when an unrecognized flag is encountered.
#   "Flag --account requires a value." — when --account has no following arg.
#   "Account '<name>' is not registered." — propagated from _core_account_dir.
#   "Key '<key>' requires --account." — propagated from _core_config_set when
#     scope=account but no account name was supplied.
#   "Invalid value for '<key>': '<value>' (expected <type>)" — propagated
#     from _core_config_validate on type mismatch.
_ckipper_config_set() {
    local account="" key="" value="" has_value="false"
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                account="$2"; shift 2
                ;;
            --account=*) account="${1#--account=}"; shift ;;
            -*) echo "Unknown flag: '$1'" >&2; return 1 ;;
            *) _ckipper_config_set_absorb_positional "$1" key value has_value; shift ;;
        esac
    done
    _ckipper_config_set_validate_key "$key" || return 1
    [[ -n "$account" ]] && { _core_account_dir "$account" >/dev/null || return 1; }
    _ckipper_config_set_resolve_value "$key" "$has_value" value || return 1
    _core_config_set "$key" "$value" "$account"
}
