#!/usr/bin/env zsh
# `ckipper config list` handler. Renders every effective configuration key in
# one of three formats: table (default), json, env.
#
# Account-scope filtering: account-scoped keys (those with SCOPE=="account")
# are emitted only when the caller passes `--account <name>`. Without that
# flag, only global keys appear — printing account-scoped defaults without an
# account would be misleading because their effective value is per-account.
#
# Phase-2 dependency: _core_style_header / _core_style_divider live in
# lib/core/style.zsh (not yet landed). Tests stub them; production callers
# source style.zsh from ckipper.zsh before list.zsh.

# Module-level argument-parse output. Populated by _ckipper_config_list_parse_args
# and consumed by the format printers.
typeset -gA _CKIPPER_CONFIG_LIST_ARGS

# Parse `[--account <name>] [--format=<fmt>]` into _CKIPPER_CONFIG_LIST_ARGS.
#
# Args: $1..$N — raw CLI arguments forwarded from _ckipper_config_list.
#
# Returns: 0 on success; 1 on unknown flag or unsupported format.
# Errors (stderr):
#   "Unknown flag: '<flag>'" — when an unrecognized argument is encountered.
#   "Unknown format: '<fmt>' (expected: table, json, env)"
_ckipper_config_list_parse_args() {
    _CKIPPER_CONFIG_LIST_ARGS=([account]="" [format]="table")
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                _CKIPPER_CONFIG_LIST_ARGS[account]="$2"; shift 2
                ;;
            --account=*) _CKIPPER_CONFIG_LIST_ARGS[account]="${1#--account=}"; shift ;;
            --format=*) _CKIPPER_CONFIG_LIST_ARGS[format]="${1#--format=}"; shift ;;
            --format)
                [[ -z "${2:-}" ]] && { echo "Flag --format requires a value." >&2; return 1; }
                _CKIPPER_CONFIG_LIST_ARGS[format]="$2"; shift 2
                ;;
            *)
                echo "Unknown flag: '$1'" >&2
                return 1
                ;;
        esac
    done
    case "${_CKIPPER_CONFIG_LIST_ARGS[format]}" in
        table | json | env) return 0 ;;
    esac
    echo "Unknown format: '${_CKIPPER_CONFIG_LIST_ARGS[format]}' (expected: table, json, env)" >&2
    return 1
}

# Decide whether a schema key should appear in the listing for the current
# scope choice. Global keys always appear; account-scoped keys appear only
# when --account was supplied.
#
# Args: $1 — schema key, $2 — account name ("" when --account omitted).
# Returns: 0 if the key should be listed; 1 if it should be skipped.
_ckipper_config_list_should_include() {
    local key="$1" account="$2"
    local scope="${_CKIPPER_SCHEMA_SCOPE[$key]:-global}"
    [[ "$scope" == "global" ]] && return 0
    [[ "$scope" == "account" && -n "$account" ]] && return 0
    return 1
}

# Print sorted list of keys this invocation will emit, one per line.
#
# Args: $1 — account name ("" when --account omitted).
# Returns: 0 always. Stdout: newline-separated keys in lexical order.
_ckipper_config_list_keys() {
    local account="$1" key
    for key in "${(@kon)_CKIPPER_SCHEMA_TYPE}"; do
        if _ckipper_config_list_should_include "$key" "$account"; then
            print -- "$key"
        fi
    done
}

# Render the table format: header, divider, then `<key>=<value>` lines.
#
# Args: $1 — account name ("" when --account omitted).
# Returns: 0 always.
_ckipper_config_list_table() {
    local account="$1" key value
    _core_style_header "Ckipper config"
    _core_style_divider
    while IFS= read -r key; do
        value=$(_core_config_get "$key" "$account")
        print -- "$key=$value"
    done < <(_ckipper_config_list_keys "$account")
}

# Render the JSON format. Builds the object key-by-key with jq so values
# containing quotes, backslashes, or other JSON metacharacters are encoded
# safely. Output is a single JSON object on stdout.
#
# Args: $1 — account name ("" when --account omitted).
# Returns: 0 always.
_ckipper_config_list_json() {
    local account="$1" key value
    local doc='{}'
    while IFS= read -r key; do
        value=$(_core_config_get "$key" "$account")
        doc=$(jq --arg k "$key" --arg v "$value" '. + {($k): $v}' <<<"$doc")
    done < <(_ckipper_config_list_keys "$account")
    print -- "$doc"
}

# Render the env format: `CKIPPER_<UPPER_KEY>=<value>` lines, one per key.
#
# Args: $1 — account name ("" when --account omitted).
# Returns: 0 always.
_ckipper_config_list_env() {
    local account="$1" key value var
    while IFS= read -r key; do
        value=$(_core_config_get "$key" "$account")
        var=$(_core_config_global_var "$key")
        print -- "$var=$value"
    done < <(_ckipper_config_list_keys "$account")
}

# Public list entry point. Parses flags then delegates to a format printer.
#
# Args: $1..$N — `[--account <name>] [--format=table|json|env]`.
#
# Returns: 0 on success; 1 on argument-parse failure.
_ckipper_config_list() {
    _ckipper_config_list_parse_args "$@" || return 1
    local account="${_CKIPPER_CONFIG_LIST_ARGS[account]}"
    local format="${_CKIPPER_CONFIG_LIST_ARGS[format]}"
    case "$format" in
        table) _ckipper_config_list_table "$account" ;;
        json)  _ckipper_config_list_json "$account" ;;
        env)   _ckipper_config_list_env "$account" ;;
    esac
}
