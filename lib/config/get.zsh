#!/usr/bin/env zsh
# `ckipper config get` handler. Thin wrapper over _core_config_get that adds
# CLI-level argument parsing and schema-membership validation.

# Print the resolved value of a configuration key.
#
# Args:
#   $1..$N — `[--account <name>] <key>`. The flag and its value may appear in
#            any order before the positional <key>; only one --account is read.
#
# Returns: 0 on success; 1 on missing key, unknown key, unknown flag, or
#   unregistered account.
#
# Errors (stderr):
#   "Usage: ckipper config get [--account <name>] <key>" — when no key supplied.
#   "Unknown config key: '<key>'" — when key is not in the schema.
#   "Unknown flag: '<flag>'" — when an unrecognized flag is encountered.
#   "Flag --account requires a value." — when --account has no following arg.
#   "Account '<name>' is not registered." — propagated from _core_account_dir.
_ckipper_config_get() {
    local account="" key=""
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                account="$2"; shift 2
                ;;
            --account=*) account="${1#--account=}"; shift ;;
            -*)
                echo "Unknown flag: '$1'" >&2
                return 1
                ;;
            *) key="$1"; shift ;;
        esac
    done
    if [[ -z "$key" ]]; then
        echo "Usage: ckipper config get [--account <name>] <key>" >&2
        return 1
    fi
    if [[ -z "${_CKIPPER_SCHEMA_TYPE[$key]:-}" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
    [[ -n "$account" ]] && { _core_account_dir "$account" >/dev/null || return 1; }
    _core_config_get "$key" "$account"
}
