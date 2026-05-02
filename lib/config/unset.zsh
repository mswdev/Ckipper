#!/usr/bin/env zsh
# `ckipper config unset` handler. Thin wrapper over _core_config_unset that
# adds CLI-level argument parsing and schema-membership validation.

# Verify the user supplied a key and that it exists in the schema. Surfaces
# both the usage line and the unknown-key error so the caller can treat the
# result as a single validation gate.
#
# Args: $1 — candidate key (may be empty).
# Returns: 0 if the key is non-empty and in the schema; 1 otherwise.
# Errors (stderr):
#   "Usage: ckipper config unset [--account <name>] <key>" — when no key.
#   "Unknown config key: '<key>'" — key not in schema.
_ckipper_config_unset_validate_key() {
    local key="$1"
    if [[ -z "$key" ]]; then
        echo "Usage: ckipper config unset [--account <name>] <key>" >&2
        return 1
    fi
    if [[ -z "${_CKIPPER_SCHEMA_TYPE[$key]:-}" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
}

# Remove the override for a configuration key, reverting future reads to the
# schema default (or to the global value when an account override is removed).
#
# Args:
#   $1..$N — `[--account <name>] <key>`. The flag and its value may appear in
#            any order before the positional <key>; only one --account is read.
#
# Returns: 0 on success; 1 on missing key, unknown key, unknown flag, missing
#   --account on an account-scoped key, or unregistered account.
#
# Errors (stderr):
#   "Usage: ckipper config unset [--account <name>] <key>" — when no key.
#   "Unknown config key: '<key>'" — when key is not in the schema.
#   "Unknown flag: '<flag>'" — when an unrecognized flag is encountered.
#   "Flag --account requires a value." — when --account has no following arg.
#   "Account '<name>' is not registered." — propagated from _core_account_dir.
#   "Key '<key>' requires --account." — propagated from _core_config_unset
#     when scope=account but no account name was supplied.
_ckipper_config_unset() {
    _core_registry_check_version || return 1
    local account="" key=""
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                account="$2"; shift 2
                ;;
            --account=*) account="${1#--account=}"; shift ;;
            -*) echo "Unknown flag: '$1'" >&2; return 1 ;;
            *) key="$1"; shift ;;
        esac
    done
    _ckipper_config_unset_validate_key "$key" || return 1
    [[ -n "$account" ]] && { _core_account_dir "$account" >/dev/null || return 1; }
    _core_config_unset "$key" "$account"
}
