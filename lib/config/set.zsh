#!/usr/bin/env zsh
# `ckipper config set` handler. Thin wrapper over _core_config_set that adds
# CLI-level argument parsing, schema-membership validation, and an interactive
# value-prompt fallback.
#
# Phase-2 dependency: _core_prompt_input / _core_prompt_choose live in
# lib/core/prompt.zsh (not yet landed). Tests exercise only the explicit-value
# path; the prompt branches are unreachable until prompt.zsh is sourced.

# Module-level argument-parse output. Populated by _ckipper_config_set_parse_args
# and consumed by _ckipper_config_set immediately after.
typeset -gA _CKIPPER_CONFIG_SET_ARGS

# Record a positional argument (first one becomes the key, second becomes the
# value) into _CKIPPER_CONFIG_SET_ARGS.
#
# Args: $1 — the positional token to absorb.
# Returns: 0 always.
_ckipper_config_set_absorb_positional() {
    if [[ -z "${_CKIPPER_CONFIG_SET_ARGS[key]}" ]]; then
        _CKIPPER_CONFIG_SET_ARGS[key]="$1"
        return 0
    fi
    _CKIPPER_CONFIG_SET_ARGS[value]="$1"
    _CKIPPER_CONFIG_SET_ARGS[has_value]="true"
}

# Parse `[--account <name>] [<key>] [<value>]` into _CKIPPER_CONFIG_SET_ARGS.
#
# Args: $1..$N — raw CLI arguments forwarded from _ckipper_config_set.
#
# Returns: 0 on success; 1 on unknown flag.
# Errors (stderr): "Unknown flag: '<flag>'" — see Returns.
_ckipper_config_set_parse_args() {
    _CKIPPER_CONFIG_SET_ARGS=([account]="" [key]="" [value]="" [has_value]="false")
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                _CKIPPER_CONFIG_SET_ARGS[account]="$2"; shift 2
                ;;
            --account=*) _CKIPPER_CONFIG_SET_ARGS[account]="${1#--account=}"; shift ;;
            -*)
                echo "Unknown flag: '$1'" >&2
                return 1
                ;;
            *)
                _ckipper_config_set_absorb_positional "$1"
                shift
                ;;
        esac
    done
}

# Interactively pick a schema key via the Phase-2 prompt helper.
#
# Args: $1 — name of the variable to receive the picked key (nameref).
#
# Returns: 0 on success; non-zero if the prompt is cancelled or
#   _core_prompt_choose is unavailable.
_ckipper_config_set_pick_key() {
    typeset -n _picked="$1"
    local -a candidates
    candidates=("${(@kon)_CKIPPER_SCHEMA_TYPE}")
    _core_prompt_choose "Pick a config key" _picked "${candidates[@]}"
}

# Set a configuration key. Routes to the global file or to the account
# preference store based on the schema scope.
#
# Args:
#   $1..$N — `[--account <name>] <key> [<value>]`. When <value> is omitted
#            the function prompts via _core_prompt_input (Phase-2).
#
# Returns: 0 on success; 1 on unknown key, validation failure, or missing
#   --account on an account-scoped key.
#
# Errors (stderr):
#   "Usage: ckipper config set [--account <name>] <key> [value]" — no key.
#   "Unknown config key: '<key>'" — when key is not in the schema.
_ckipper_config_set() {
    _ckipper_config_set_parse_args "$@" || return 1
    local key="${_CKIPPER_CONFIG_SET_ARGS[key]}"
    local value="${_CKIPPER_CONFIG_SET_ARGS[value]}"
    local account="${_CKIPPER_CONFIG_SET_ARGS[account]}"
    if [[ -z "$key" ]]; then
        echo "Usage: ckipper config set [--account <name>] <key> [value]" >&2
        return 1
    fi
    if [[ -z "${_CKIPPER_SCHEMA_TYPE[$key]:-}" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
    if [[ "${_CKIPPER_CONFIG_SET_ARGS[has_value]}" != "true" ]]; then
        local prompt_label="Value for $key (${_CKIPPER_SCHEMA_TYPE[$key]})"
        _core_prompt_input "$prompt_label" value || return 1
    fi
    _core_config_set "$key" "$value" "$account"
}
