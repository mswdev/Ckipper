#!/usr/bin/env zsh
# `ckipper config unset` handler. Thin wrapper over _core_config_unset that
# adds CLI-level argument parsing and schema-membership validation.

# Remove the override for a configuration key, reverting future reads to the
# schema default (or to the global value when an account override is removed).
#
# Args:
#   $1..$N — `[--account <name>] <key>`. The flag and its value may appear in
#            any order before the positional <key>; only one --account is read.
#
# Returns: 0 on success; 1 on missing key, unknown key, or unknown flag.
#
# Errors (stderr):
#   "Usage: ckipper config unset [--account <name>] <key>" — when no key.
#   "Unknown config key: '<key>'" — when key is not in the schema.
#   "Unknown flag: '<flag>'" — when an unrecognized flag is encountered.
_ckipper_config_unset() {
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
        echo "Usage: ckipper config unset [--account <name>] <key>" >&2
        return 1
    fi
    if [[ -z "${_CKIPPER_SCHEMA_TYPE[$key]:-}" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
    _core_config_unset "$key" "$account"
}
