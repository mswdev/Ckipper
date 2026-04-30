#!/usr/bin/env zsh
# Plugin metadata path rewrite utilities: rewrite_plugin_paths, repair_plugins.

# Rewrite stale absolute paths embedded in Claude Code's plugin metadata files
# (known_marketplaces.json, installed_plugins.json). After moving an account
# directory (legacy ~/.claude → ~/.claude-<name>), the plugin cache files on
# disk have moved with the rename, but the JSON metadata still has the old
# absolute paths baked in — Claude Code then fails to resolve plugins with
# "Plugin not found in marketplace ..." errors.
#
# Args:
#   $1 — old prefix (must end with `/`), e.g. "$HOME/.claude/"
#   $2 — new prefix (must end with `/`), e.g. "$HOME/.claude-personal/"
#
# Returns:
#   0 always (idempotent: if neither file contains old prefix, this is a no-op);
#   1 if arguments are invalid.
_ckipper_rewrite_plugin_paths() {
    local old="$1" new="$2"
    [[ -z "$old" || -z "$new" || "$old" != */ || "$new" != */ ]] && return 1
    [[ "$old" == "$new" ]] && return 0
    local f
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        _ckipper_rewrite_single_plugin_file "$old" "$new" "$f"
    done
    return 0
}

# Rewrite stale paths in a single plugin metadata file using sed (in-place).
# Creates a timestamped backup before modifying the file.
#
# Args:
#   $1 — old prefix (must end with `/`)
#   $2 — new prefix (must end with `/`)
#   $3 — relative plugin file path (e.g. plugins/known_marketplaces.json)
#
# Returns:
#   0 always (no-op if file absent or old prefix not found).
_ckipper_rewrite_single_plugin_file() {
    local old="$1" new="$2" rel_path="$3"
    local fp="$new$rel_path"
    [[ -f "$fp" ]] || return 0
    grep -q -- "$old" "$fp" 2>/dev/null || return 0
    cp "$fp" "$fp.pre-rewrite-backup-$(date +%s)"
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        sed -i '' "s|$old|$new|g" "$fp"
    else
        sed -i "s|$old|$new|g" "$fp"
    fi
}

# Detect the stale prefix in the plugin metadata files for the given account.
#
# Args:
#   $1 — account config directory path
#
# Returns:
#   0 always; prints stale prefix to stdout (empty if none found).
_ckipper_detect_stale_plugin_prefix() {
    local dir="$1"
    local f
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        [[ -f "$dir/$f" ]] || continue
        local hit
        hit=$(grep -oE "$HOME/\.claude(-[a-z0-9_-]+)?/" "$dir/$f" 2>/dev/null | \
            sort -u | grep -v "^$dir/$" | head -1)
        if [[ -n "$hit" ]]; then
            printf '%s' "$hit"
            return 0
        fi
    done
}

# Rewrite stale absolute paths in plugin metadata for a single registered account.
#
# Args:
#   $1 — registered account name
#
# Returns:
#   0 on success or when no repair is needed; 1 on error.
#
# Errors (stderr):
#   "Usage: ckipper repair-plugins <name>" — when name is empty.
#   "Account '...' is not registered." — when account not found.
#   "Account dir does not exist: ..." — when directory is missing.
_ckipper_repair_plugins() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper repair-plugins <name>"
        return 1
    fi
    _core_registry_check_version || return 1
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir // empty' "$CKIPPER_REGISTRY")
    if [[ -z "$dir" ]]; then
        echo "Account '$name' is not registered. Run: ckipper list"
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        echo "Account dir does not exist: $dir"
        return 1
    fi
    _ckipper_repair_plugins_apply "$name" "$dir"
}

# Apply stale-prefix repair to an account directory once validation has passed.
#
# Args:
#   $1 — account name (for messages)
#   $2 — account config directory
#
# Returns:
#   0 on success or when no repair is needed.
_ckipper_repair_plugins_apply() {
    local name="$1" dir="$2"
    local stale_prefix
    stale_prefix=$(_ckipper_detect_stale_plugin_prefix "$dir")
    if [[ -z "$stale_prefix" ]]; then
        echo "No stale paths found in $dir/plugins/. Nothing to repair."
        return 0
    fi
    echo "Rewriting plugin metadata for '$name':"
    echo "  $stale_prefix → $dir/"
    _ckipper_rewrite_plugin_paths "$stale_prefix" "$dir/"
    echo "Done. Backups saved alongside each rewritten file (.pre-rewrite-backup-<ts>)."
}
