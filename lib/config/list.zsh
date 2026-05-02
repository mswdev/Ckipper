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

# Validate the format token against the supported renderers.
#
# Args: $1 — format string.
# Returns: 0 if recognized; 1 otherwise.
# Errors (stderr): "Unknown format: '<fmt>' (expected: table, json, env)".
_ckipper_config_list_validate_format() {
    case "$1" in
        table | json | env) return 0 ;;
    esac
    echo "Unknown format: '$1' (expected: table, json, env)" >&2
    return 1
}

# Dispatch to the renderer matching the resolved format. Caller is responsible
# for having validated the format already via _ckipper_config_list_validate_format.
#
# Args: $1 — format ("table" | "json" | "env"), $2 — account ("" if global).
# Returns: renderer's exit status.
_ckipper_config_list_render() {
    local format="$1" account="$2"
    case "$format" in
        table) _ckipper_config_list_table "$account" ;;
        json)  _ckipper_config_list_json "$account" ;;
        env)   _ckipper_config_list_env "$account" ;;
    esac
}

# Public list entry point. Parses flags then delegates to a format printer.
#
# Args: $1..$N — `[--account <name>] [--format=table|json|env]`.
#
# Returns: 0 on success; 1 on argument-parse failure or unregistered account.
#
# Errors (stderr):
#   "Unknown flag: '<flag>'" — when an unrecognized argument is encountered.
#   "Flag --account requires a value." — when --account has no following arg.
#   "Flag --format requires a value." — when --format has no following arg.
#   "Unknown format: '<fmt>' (expected: table, json, env)" — invalid format.
#   "Account '<name>' is not registered." — propagated from _core_account_dir.
_ckipper_config_list() {
    _core_registry_check_version || return 1
    local account="" format="table"
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                account="$2"; shift 2
                ;;
            --account=*) account="${1#--account=}"; shift ;;
            --format=*) format="${1#--format=}"; shift ;;
            --format)
                [[ -z "${2:-}" ]] && { echo "Flag --format requires a value." >&2; return 1; }
                format="$2"; shift 2
                ;;
            *)
                echo "Unknown flag: '$1'" >&2
                return 1
                ;;
        esac
    done
    _ckipper_config_list_validate_format "$format" || return 1
    [[ -n "$account" ]] && { _core_account_dir "$account" >/dev/null || return 1; }
    _ckipper_config_list_render "$format" "$account"
}
