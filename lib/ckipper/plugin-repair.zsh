#!/usr/bin/env zsh
# Plugin metadata path rewrite utilities: rewrite_plugin_paths, repair_plugins.

# Rewrite stale absolute paths embedded in Claude Code's plugin metadata files
# (known_marketplaces.json, installed_plugins.json). After moving an account
# directory (legacy ~/.claude → ~/.claude-<name>), the plugin cache files on
# disk have moved with the rename, but the JSON metadata still has the old
# absolute paths baked in — Claude Code then fails to resolve plugins with
# "Plugin not found in marketplace ..." errors.
#
# $1 = old prefix (must end with `/`), e.g. "$HOME/.claude/"
# $2 = new prefix (must end with `/`), e.g. "$HOME/.claude-personal/"
# Idempotent: if neither file contains the old prefix, this is a no-op.
_ckipper_rewrite_plugin_paths() {
    local old="$1" new="$2"
    [[ -z "$old" || -z "$new" || "$old" != */ || "$new" != */ ]] && return 1
    [[ "$old" == "$new" ]] && return 0
    local f rewrote=0
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        local fp="$new$f"
        [[ -f "$fp" ]] || continue
        grep -q -- "$old" "$fp" 2>/dev/null || continue
        cp "$fp" "$fp.pre-rewrite-backup-$(date +%s)"
        if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
            sed -i '' "s|$old|$new|g" "$fp"
        else
            sed -i "s|$old|$new|g" "$fp"
        fi
        rewrote=1
    done
    return 0
}

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

    # Detect what stale prefix the metadata is using. Almost always the legacy
    # ~/.claude/, but a previously-renamed account could carry an older suffix.
    local stale_prefix=""
    local f
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        [[ -f "$dir/$f" ]] || continue
        # Combined declare+assign on one line: zsh 5.9 emits "var=''" to stdout
        # when `local var` and `var=$(...)` are split across two lines inside a
        # `for` loop body. Trivia that mostly bites diagnostic helpers like this.
        local hit=$(grep -oE "$HOME/\.claude(-[a-z0-9_-]+)?/" "$dir/$f" 2>/dev/null | sort -u | grep -v "^$dir/$" | head -1)
        if [[ -n "$hit" ]]; then
            stale_prefix="$hit"
            break
        fi
    done
    if [[ -z "$stale_prefix" ]]; then
        echo "No stale paths found in $dir/plugins/. Nothing to repair."
        return 0
    fi
    echo "Rewriting plugin metadata for '$name':"
    echo "  $stale_prefix → $dir/"
    _ckipper_rewrite_plugin_paths "$stale_prefix" "$dir/"
    echo "Done. Backups saved alongside each rewritten file (.pre-rewrite-backup-<ts>)."
}
