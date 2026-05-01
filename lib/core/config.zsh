#!/usr/bin/env zsh
# Pure config get/set/unset/validate primitives. Operates on:
#   - global file: $CKIPPER_DIR/docker/ckipper-config.zsh (zsh assignments)
#   - per-account: $CKIPPER_REGISTRY (.accounts.<name>.preferences.<key>)
#
# Schema source-of-truth: lib/config/schema.zsh — must be sourced before this.
# Functions here resolve the schema arrays at call time, never source-time.

readonly _CKIPPER_GLOBAL_PREFIX="CKIPPER_"

# Translate a schema key to the global file's variable name.
#
# Args: $1 — schema key (e.g. "notify_bell")
# Returns: 0; prints "CKIPPER_NOTIFY_BELL".
_core_config_global_var() {
    local key="$1"
    echo "${_CKIPPER_GLOBAL_PREFIX}${(U)key}"
}

# Path to the global config file.
#
# Returns: 0; prints absolute path under $CKIPPER_DIR/docker/.
_core_config_global_file() {
    echo "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper-config.zsh"
}

# Read a global value from the config file without sourcing it.
#
# Args: $1 — schema key
# Returns: 0; prints the assigned value (quotes stripped) or empty string if unset.
_core_config_read_global() {
    local key="$1"
    local var
    var=$(_core_config_global_var "$key")
    local file
    file=$(_core_config_global_file)
    [[ -f "$file" ]] || {
        echo ""
        return 0
    }
    awk -v v="$var" -F= '$1 == v { sub(/^[^=]+=/, ""); gsub(/^"|"$/, ""); print; exit }' "$file"
}

# Read an account preference from the registry.
#
# Args: $1 — key, $2 — account name
# Returns: 0; prints the stored value or empty string if unset.
_core_config_read_account() {
    local key="$1" account="$2"
    [[ -f "$CKIPPER_REGISTRY" ]] || {
        echo ""
        return 0
    }
    jq -r --arg n "$account" --arg k "$key" '
        if (.accounts[$n].preferences | has($k))
        then .accounts[$n].preferences[$k] | tostring
        else ""
        end
    ' "$CKIPPER_REGISTRY"
}

# Resolve effective value: account override → global → schema default.
#
# Args: $1 — key, $2 — (optional) account name
# Returns: 0; prints the resolved value (may be empty if default is empty).
_core_config_get() {
    local key="$1" account="${2:-}"
    local val=""
    if [[ -n "$account" && "${_CKIPPER_SCHEMA_SCOPE[$key]}" == "account" ]]; then
        val=$(_core_config_read_account "$key" "$account")
        [[ -n "$val" ]] && {
            echo "$val"
            return 0
        }
    fi
    val=$(_core_config_read_global "$key")
    [[ -n "$val" ]] && {
        echo "$val"
        return 0
    }
    echo "${_CKIPPER_SCHEMA_DEFAULT[$key]}"
}

# Validate a value against the schema type for a key.
#
# Args: $1 — key, $2 — value
# Returns: 0 if valid; 1 on unknown key or type mismatch.
# Errors (stderr):
#   "Unknown config key: '<key>'" — when key not in schema.
#   "Invalid value for '<key>': '<value>' (expected <type>)" — on type mismatch.
_core_config_validate() {
    local key="$1" value="$2"
    local type="${_CKIPPER_SCHEMA_TYPE[$key]:-}"
    if [[ -z "$type" ]]; then
        echo "Unknown config key: '$key'" >&2
        return 1
    fi
    case "$type" in
        bool)
            [[ "$value" == "true" || "$value" == "false" ]] && return 0
            ;;
        int)
            [[ "$value" =~ ^[0-9]+$ ]] && return 0
            ;;
        int_array)
            [[ "$value" =~ ^[0-9]+(,[0-9]+)*$ ]] && return 0
            ;;
        string | path)
            return 0
            ;;
    esac
    echo "Invalid value for '$key': '$value' (expected $type)" >&2
    return 1
}

# Write a global key into the config file, replacing any existing assignment.
# Idempotent: existing CKIPPER_<KEY>= line is rewritten in place; absent keys
# are appended.
#
# Args: $1 — key, $2 — value
# Returns: 0 on success; 1 on validation failure.
_core_config_write_global() {
    local key="$1" value="$2"
    _core_config_validate "$key" "$value" || return 1
    local var
    var=$(_core_config_global_var "$key")
    local file
    file=$(_core_config_global_file)
    mkdir -p "${file:h}"
    [[ -f "$file" ]] || : >"$file"
    local tmp
    tmp=$(mktemp "${file}.XXXXXX")
    awk -v v="$var" -v val="$value" -F= '
        $1 == v { print v "=\"" val "\""; found=1; next }
        { print }
        END { if (!found) print v "=\"" val "\"" }
    ' "$file" >"$tmp" && mv "$tmp" "$file"
}

# Write an account preference into the registry. Coerces "true"/"false"/numeric
# strings to native JSON types so consumers don't see stringified bools.
#
# Args: $1 — key, $2 — value, $3 — account name
# Returns: 0 on success; 1 on validation or jq/write failure.
_core_config_write_account() {
    local key="$1" value="$2" account="$3"
    _core_config_validate "$key" "$value" || return 1
    local tmp
    tmp=$(mktemp "${CKIPPER_REGISTRY}.XXXXXX")
    jq --arg n "$account" --arg k "$key" --arg v "$value" '
        .accounts[$n].preferences[$k] = (
            if $v == "true" then true
            elif $v == "false" then false
            elif ($v | test("^[0-9]+$")) then ($v | tonumber)
            else $v end
        )
    ' "$CKIPPER_REGISTRY" >"$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
}

# Public set — routes to global or account-scoped write per the schema.
#
# Args: $1 — key, $2 — value, $3 — (optional) account name
# Returns: 0 on success; 1 on validation/write failure or missing account
#   for an account-scoped key.
# Errors (stderr): "Key '<key>' requires --account." — when scope=account
#   but no account name was supplied.
_core_config_set() {
    local key="$1" value="$2" account="${3:-}"
    local scope="${_CKIPPER_SCHEMA_SCOPE[$key]:-}"
    if [[ "$scope" == "account" ]]; then
        [[ -z "$account" ]] && {
            echo "Key '$key' requires --account." >&2
            return 1
        }
        _core_config_write_account "$key" "$value" "$account"
    else
        _core_config_write_global "$key" "$value"
    fi
}

# Remove a global override, reverting future reads to the schema default.
#
# Args: $1 — key
# Returns: 0 always (no-op when file is absent or line is missing).
_core_config_unset_global() {
    local key="$1"
    local var
    var=$(_core_config_global_var "$key")
    local file
    file=$(_core_config_global_file)
    [[ -f "$file" ]] || return 0
    local tmp
    tmp=$(mktemp "${file}.XXXXXX")
    awk -v v="$var" -F= '$1 != v' "$file" >"$tmp" && mv "$tmp" "$file"
}

# Remove an account preference override.
#
# Args: $1 — key, $2 — account name
# Returns: 0 always (no-op when registry absent).
_core_config_unset_account() {
    local key="$1" account="$2"
    [[ -f "$CKIPPER_REGISTRY" ]] || return 0
    local tmp
    tmp=$(mktemp "${CKIPPER_REGISTRY}.XXXXXX")
    jq --arg n "$account" --arg k "$key" 'del(.accounts[$n].preferences[$k])' "$CKIPPER_REGISTRY" >"$tmp" \
        && mv "$tmp" "$CKIPPER_REGISTRY"
}

# Public unset — routes to global or account-scoped removal per the schema.
#
# Args: $1 — key, $2 — (optional) account name
# Returns: 0 on success; 1 if scope=account but no account name supplied.
# Errors (stderr): "Key '<key>' requires --account." — see above.
_core_config_unset() {
    local key="$1" account="${2:-}"
    local scope="${_CKIPPER_SCHEMA_SCOPE[$key]:-global}"
    if [[ "$scope" == "account" ]]; then
        [[ -z "$account" ]] && {
            echo "Key '$key' requires --account." >&2
            return 1
        }
        _core_config_unset_account "$key" "$account"
    else
        _core_config_unset_global "$key"
    fi
}
