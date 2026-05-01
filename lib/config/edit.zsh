#!/usr/bin/env zsh
# `ckipper config edit` handler. Opens the global config file in $EDITOR, or
# round-trips an account's preferences JSON object through a tmpfile when
# called with --account.

# Open the global config file in the user's preferred editor. No validation —
# the file is sourced lazily by ckipper.zsh on next shell startup.
#
# Returns: editor exit status.
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
    local path="$1"
    jq empty "$path" >/dev/null 2>&1
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
# Returns: 0 on success; 1 on dump/validate/writeback failure.
# Errors (stderr): "Edited file is not valid JSON; registry not updated."
_ckipper_config_edit_account() {
    local account="$1"
    local tmp
    tmp=$(_ckipper_config_edit_dump_prefs "$account") || return 1
    "${EDITOR:-vi}" "$tmp"
    if ! _ckipper_config_edit_validate_json "$tmp"; then
        echo "Edited file is not valid JSON; registry not updated." >&2
        rm -f "$tmp"
        return 1
    fi
    _ckipper_config_edit_writeback "$account" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# Public edit entry point. Routes between the global-file editor and the
# account-preferences round-trip per the --account flag.
#
# Args: $1..$N — `[--account <name>]`.
#
# Returns: editor / handler exit status; 1 on unknown flag.
# Errors (stderr): "Unknown flag: '<flag>'" — see Returns.
_ckipper_config_edit() {
    local account=""
    while (( $# > 0 )); do
        case "$1" in
            --account)
                [[ -z "${2:-}" ]] && { echo "Flag --account requires a value." >&2; return 1; }
                account="$2"; shift 2
                ;;
            --account=*) account="${1#--account=}"; shift ;;
            *)
                echo "Unknown flag: '$1'" >&2
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
