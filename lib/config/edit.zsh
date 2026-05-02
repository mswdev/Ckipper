#!/usr/bin/env zsh
# `ckipper config edit` handler. Opens the global config file in $EDITOR, or
# round-trips an account's preferences JSON object through a tmpfile when
# called with --account.

# Open the global config file in the user's preferred editor. No validation —
# the file is sourced lazily by ckipper.zsh on next shell startup.
#
# Returns: editor exit status.
# Errors (stderr): editor errors (e.g. "command not found") pass through
#   unchanged from the underlying $EDITOR invocation.
_ckipper_config_edit_global() {
    local file
    file=$(_core_config_global_file)
    mkdir -p "${file:h}"
    [[ -f "$file" ]] || : >"$file"
    "${EDITOR:-vi}" "$file"
}

# Write an account's preferences JSON to a fresh tmpfile and return its path
# on stdout. Caller owns deletion.
#
# Args: $1 — account name.
# Returns: 0 on success; 1 on jq failure.
_ckipper_config_edit_dump_prefs() {
    local account="$1"
    local tmp
    tmp=$(mktemp -t "ckipper-config-edit-XXXXXX") || return 1
    if ! jq --arg n "$account" '.accounts[$n].preferences // {}' "$CKIPPER_REGISTRY" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    print -- "$tmp"
}

# Validate that a tmpfile contains parseable JSON.
#
# Args: $1 — path to candidate JSON file.
# Returns: 0 if parseable; 1 otherwise. Errors go to stderr via jq.
_ckipper_config_edit_validate_json() {
    # NB: zsh's `path` is tied to $PATH — declaring `local path=...` would wipe
    # PATH for the duration of the function and break every external command.
    local file="$1"
    jq empty "$file" >/dev/null 2>&1
}

# Slurp the edited preferences JSON back into the registry under
# accounts.<name>.preferences.
#
# Args: $1 — account name, $2 — path to edited JSON file.
# Returns: 0 on success; 1 on jq/write failure.
_ckipper_config_edit_writeback() {
    local account="$1" edited="$2"
    local out
    out=$(mktemp "${CKIPPER_REGISTRY}.XXXXXX") || return 1
    if ! jq --arg n "$account" --slurpfile p "$edited" \
        '.accounts[$n].preferences = $p[0]' "$CKIPPER_REGISTRY" >"$out"; then
        rm -f "$out"
        return 1
    fi
    mv "$out" "$CKIPPER_REGISTRY"
}

# Open an account's preferences in $EDITOR. Round-trip: dump → edit → validate
# → writeback. Aborts (and leaves the registry untouched) if the edited file
# is not parseable JSON.
#
# Args: $1 — account name.
# Returns: 0 on success; 1 on dump/validate/writeback failure or unregistered
#   account.
# Errors (stderr):
#   "Account '<name>' is not registered." — propagated from _core_account_dir.
#   "Edited file is not valid JSON; registry not updated." — when the edited
#     tmpfile fails jq parse.
_ckipper_config_edit_account() {
    local account="$1"
    _core_registry_check_version || return 1
    _core_account_dir "$account" >/dev/null || return 1
    # Ensure the tmpfile is removed even if the user kills the editor (Ctrl-C)
    # or the shell receives a TERM signal mid-edit. local_traps scopes the
    # trap to this function so it doesn't leak to callers.
    setopt local_options local_traps
    local tmp
    tmp=$(_ckipper_config_edit_dump_prefs "$account") || return 1
    trap 'rm -f "$tmp"' EXIT INT TERM
    "${EDITOR:-vi}" "$tmp"
    if ! _ckipper_config_edit_validate_json "$tmp"; then
        echo "Edited file is not valid JSON; registry not updated." >&2
        return 1
    fi
    _ckipper_config_edit_writeback "$account" "$tmp"
}

# Public edit entry point. Routes between the global-file editor and the
# account-preferences round-trip per the --account flag.
#
# Args: $1..$N — `[--account <name>]`.
#
# Returns: editor / handler exit status; 1 on unknown flag, stray positional
#   argument, or unregistered account.
# Errors (stderr):
#   "Unknown flag: '<flag>'" — when an unrecognized --flag is encountered.
#   "Flag --account requires a value." — when --account has no following arg.
#   "ckipper config edit takes no positional arguments. Did you mean: --account <arg>?"
#     — when the user passes a bare positional (e.g. `ckipper config edit work`).
#   "Account '<name>' is not registered." — propagated from _core_account_dir
#     via _ckipper_config_edit_account.
_ckipper_config_edit() {
    local account=""
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
            *)
                echo "ckipper config edit takes no positional arguments. Did you mean: --account $1?" >&2
                return 1
                ;;
        esac
    done
    if [[ -z "$account" ]]; then
        _ckipper_config_edit_global
    else
        _ckipper_config_edit_account "$account"
    fi
}
