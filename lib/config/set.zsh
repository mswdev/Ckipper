#!/usr/bin/env zsh
# `ckipper config set` handler. Thin wrapper over _core_config_set that adds
# CLI-level argument parsing, schema-membership validation, and an interactive
# value-prompt fallback when the user omits the value argument.
#
# The prompt fallback delegates to _core_prompt_input (lib/core/prompt.zsh),
# which honors CKIPPER_NO_GUM=1 and reads from stdin in the fallback path.

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

# Module-level scratch globals populated by _ckipper_config_set_parse_args.
# Lifecycle: reset by the parser on each call, consumed by _ckipper_config_set,
# then left in place. They are not meant to be read by other modules.
typeset -g _CKIPPER_CONFIG_SET_ACCOUNT=""
typeset -g _CKIPPER_CONFIG_SET_KEY=""
typeset -g _CKIPPER_CONFIG_SET_VALUE=""
typeset -g _CKIPPER_CONFIG_SET_HAS_VALUE="false"

# Capture a positional arg into the parser's scratch globals: first positional
# becomes the key, second becomes the value (and flips has_value to "true").
# Extracted to keep _ckipper_config_set_parse_args at <=2 nesting levels.
#
# Args: $1 — the positional token.
# Returns: 0 always.
_ckipper_config_set_record_positional() {
    if [[ -z "$_CKIPPER_CONFIG_SET_KEY" ]]; then
        _CKIPPER_CONFIG_SET_KEY="$1"
        return 0
    fi
    _CKIPPER_CONFIG_SET_VALUE="$1"
    _CKIPPER_CONFIG_SET_HAS_VALUE="true"
}

# Parse the `ckipper config set` arg list into the module scratch globals.
#
# Args: $@ — the user's argv after `ckipper config set`.
# Returns: 0 on success; 1 on missing --account value or unknown flag.
# Errors (stderr):
#   "Flag --account requires a value." — when --account has no following arg.
#   "Unknown flag: '<flag>'" — when an unrecognized flag is encountered.
_ckipper_config_set_parse_args() {
    _CKIPPER_CONFIG_SET_ACCOUNT=""
    _CKIPPER_CONFIG_SET_KEY=""
    _CKIPPER_CONFIG_SET_VALUE=""
    _CKIPPER_CONFIG_SET_HAS_VALUE="false"
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                _CKIPPER_CONFIG_SET_ACCOUNT="$2"; shift 2
                ;;
            --account=*) _CKIPPER_CONFIG_SET_ACCOUNT="${1#--account=}"; shift ;;
            -*) echo "Unknown flag: '$1'" >&2; return 1 ;;
            *) _ckipper_config_set_record_positional "$1"; shift ;;
        esac
    done
}

# Set a configuration key. Routes to the global file or to the account
# preference store based on the schema scope. When the user omits the
# value argument, prompt them via _core_prompt_input.
#
# Args:
#   $1..$N — `[--account <name>] <key> [<value>]`. When <value> is omitted
#            the function prompts the user via _core_prompt_input, which
#            reads from stdin in its CKIPPER_NO_GUM fallback path.
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
    _core_registry_check_version || return 1
    _ckipper_config_set_parse_args "$@" || return 1
    local account="$_CKIPPER_CONFIG_SET_ACCOUNT"
    local key="$_CKIPPER_CONFIG_SET_KEY"
    local value="$_CKIPPER_CONFIG_SET_VALUE"
    _ckipper_config_set_validate_key "$key" || return 1
    [[ -n "$account" ]] && { _core_account_dir "$account" >/dev/null || return 1; }
    if [[ "$_CKIPPER_CONFIG_SET_HAS_VALUE" != "true" ]]; then
        local prompt_label="Value for $key (${_CKIPPER_SCHEMA_TYPE[$key]})"
        # Cancellation must abort the write, not commit an empty value.
        # _core_prompt_input returns non-zero on Esc/Ctrl-C; without this
        # check the user pressing cancel would silently blank the key.
        if ! value=$(_core_prompt_input "$prompt_label" ""); then
            return 1
        fi
    fi
    _core_config_set "$key" "$value" "$account"
}
