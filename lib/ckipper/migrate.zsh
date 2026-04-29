#!/usr/bin/env zsh
# One-time migration from legacy ~/.claude/docker/ layout.

_ckipper_migrate() {
    _core_registry_check_version || return 1
    local legacy_docker="$HOME/.claude/docker"
    local legacy_claude="$HOME/.claude"

    # ── Precondition 1: no Claude process running ─────────────────
    _core_assert_no_running_claude || return 1

    # ── Precondition 2: ~/.claude must NOT be a symlink ──────────
    # Some users symlink ~/.claude to a synced location. Renaming a symlink
    # moves the link, not the target — confusing and probably not what they want.
    if [[ -L "$legacy_claude" ]]; then
        local target; target=$(readlink "$legacy_claude")
        echo "Error: $legacy_claude is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual directory contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi

    # ── Precondition 3: ~/.claude.json must NOT be a symlink ──────
    # Same reasoning — Dropbox/iCloud users symlink this for cross-machine sync.
    # mv on a symlink moves the link itself, breaking the sync target.
    local legacy_homejson_check="$HOME/.claude.json"
    if [[ -L "$legacy_homejson_check" ]]; then
        local target; target=$(readlink "$legacy_homejson_check")
        echo "Error: $legacy_homejson_check is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual file contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi

    # ── 1. Move ~/.claude/docker → ~/.ckipper/docker if not done ──
    if [[ -d "$legacy_docker" && ! -d "$CKIPPER_DIR/docker" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cp -a "$legacy_docker/." "$CKIPPER_DIR/docker/"
        echo "Copied $legacy_docker → $CKIPPER_DIR/docker (legacy left intact for one release cycle)"
    fi

    # ── 2. Adopt ~/.claude as a registered account ────────────────
    # Eligible if either ~/.claude/.claude.json or ~/.claude/settings.json exists,
    # OR ~/.claude.json exists at home root (Claude Code's canonical big-config location).
    local legacy_homejson="$HOME/.claude.json"
    local has_inner_state=0 has_homejson=0
    [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" ]] && has_inner_state=1
    [[ -f "$legacy_homejson" ]] && has_homejson=1

    if (( has_inner_state == 0 && has_homejson == 0 )); then
        local has_registry=0
        [[ -f "$CKIPPER_REGISTRY" ]] && jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1 && has_registry=1
        if (( has_registry )); then
            echo "Nothing to migrate: no $legacy_claude state and no $legacy_homejson at home root."
            echo "($CKIPPER_REGISTRY already has registered accounts — you're likely already migrated.)"
            echo "Run: ckipper list"
        else
            echo "Nothing to migrate: no $legacy_claude/.claude.json, no $legacy_claude/settings.json, no $legacy_homejson."
            echo "If this is a fresh setup, register an account directly: ckipper add <name>"
        fi
        return 0
    fi

    if [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" || -f "$legacy_homejson" ]]; then
        if [[ ! -f "$CKIPPER_REGISTRY" ]] || \
           ! jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then

            # ── Prompt for the account name ──────────────────────
            local default_name="personal"
            local name=""
            while [[ -z "$name" ]]; do
                read -r "?What name do you want for this migrated account? [$default_name] " name
                [[ -z "$name" ]] && name="$default_name"
                if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
                    echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen). Try again."
                    name=""
                fi
                if [[ -n "$name" && -e "$HOME/.claude-$name" ]]; then
                    echo "$HOME/.claude-$name already exists. Pick a different name."
                    name=""
                fi
            done
            local target_dir="$HOME/.claude-$name"

            # Show the user what we're about to do.
            cat <<EOF

Detected existing $legacy_claude with login credentials.
EOF
            [[ -f "$legacy_homejson" ]] && \
                echo "Also detected $legacy_homejson (Claude's main config — projects, MCPs, trust state)."

            cat <<EOF

This migration will:
  1. Rename $legacy_claude → $target_dir.
EOF
            [[ -f "$legacy_homejson" ]] && \
                echo "  2. Move $legacy_homejson → $target_dir/.claude.json (preserving any existing inner one as a backup)."
            cat <<EOF
  3. Register '$name' in $CKIPPER_REGISTRY.
  4. Probe macOS Keychain for the matching 'Claude Code-credentials' entry.

NOT a symlink — bare 'claude' will no longer use this account; use 'claude-$name' instead.
If anything fails, the rename is automatically reverted.

EOF
            read -r "?Proceed? [y/N] " ans
            if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
                echo "Aborted."
                return 1
            fi

            # ── Precondition: probe Keychain entry exists ───────
            local probed_service="Claude Code-credentials"
            if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
                if ! security find-generic-password -s "$probed_service" -w >/dev/null 2>&1; then
                    echo "Warning: '$probed_service' not found in Keychain."
                    echo "Listing available Claude Keychain entries:"
                    _core_keychain_snapshot || return 1
                    read -r "?Enter the Keychain service for the '$name' account (or empty to skip): " probed_service
                    if [[ -n "$probed_service" ]] && ! _core_keychain_validate "$probed_service"; then
                        echo "Invalid Keychain service shape. Aborting."
                        return 1
                    fi
                fi
            else
                probed_service=""
            fi

            # ── Destructive operation with explicit rollback ─────
            # Tracks every step performed so rollback can undo precisely:
            #   1 = ~/.claude renamed; 2 = ~/.claude.json moved (inner backed up)
            local migrate_step=0
            local moved_homejson_backup=""
            _ckipper_migrate_rollback() {
                local why="${1:-rollback}"
                # Step 2 reverse: restore ~/.claude.json at home root, restore the
                # inner backup if we made one.
                if (( migrate_step >= 2 )) && [[ -f "$target_dir/.claude.json" && ! -e "$legacy_homejson" ]]; then
                    mv "$target_dir/.claude.json" "$legacy_homejson" 2>/dev/null
                    if [[ -n "$moved_homejson_backup" && -f "$moved_homejson_backup" ]]; then
                        mv "$moved_homejson_backup" "$target_dir/.claude.json" 2>/dev/null
                    fi
                fi
                # Step 1 reverse: rename target_dir back to legacy_claude.
                if (( migrate_step >= 1 )) && [[ -d "$target_dir" && ! -e "$legacy_claude" ]]; then
                    mv "$target_dir" "$legacy_claude" 2>/dev/null
                    echo "Migration $why — restored $legacy_claude." >&2
                fi
                # Clean partial registry entry so a re-run isn't blocked.
                if [[ -f "$CKIPPER_REGISTRY" ]] && \
                   jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
                    _core_registry_update \
                        'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' \
                        --arg n "$name"
                    echo "Cleaned partial '$name' entry from $CKIPPER_REGISTRY." >&2
                fi
                # Regenerate aliases.zsh so it reflects the post-rollback registry
                # (otherwise it would still define claude-<name>() pointing into a
                # dir that no longer exists).
                _ckipper_regenerate_aliases 2>/dev/null || true
            }
            # HUP catches Terminal.app window-close mid-migrate; QUIT catches Ctrl-\.
            trap '_ckipper_migrate_rollback interrupted; trap - INT TERM HUP QUIT ERR; return 130' INT TERM HUP QUIT

            # Step 1: rename ~/.claude → ~/.claude-<name>
            if ! mv "$legacy_claude" "$target_dir" 2>/dev/null; then
                trap - INT TERM HUP QUIT
                echo "Error: failed to rename $legacy_claude → $target_dir" >&2
                echo "(Check permissions on $HOME and that no process holds the directory open.)" >&2
                return 1
            fi
            migrate_step=1

            # Step 2: move ~/.claude.json → $target_dir/.claude.json.
            # If $target_dir already has a .claude.json (Claude wrote one when
            # CLAUDE_CONFIG_DIR was set in some prior run), back it up — the
            # home-root file is canonical.
            if [[ -f "$legacy_homejson" ]]; then
                if [[ -f "$target_dir/.claude.json" ]]; then
                    moved_homejson_backup="$target_dir/.claude.json.pre-migrate-backup"
                    mv "$target_dir/.claude.json" "$moved_homejson_backup"
                fi
                if ! mv "$legacy_homejson" "$target_dir/.claude.json" 2>/dev/null; then
                    _ckipper_migrate_rollback failed
                    trap - INT TERM HUP QUIT
                    echo "Error: failed to move $legacy_homejson → $target_dir/.claude.json" >&2
                    return 1
                fi
                migrate_step=2
            fi

            # Step 2.5: rewrite stale absolute paths in plugin metadata.
            # Without this, Claude Code raises "Plugin not found in marketplace"
            # for every previously-installed plugin, because installed_plugins.json
            # and known_marketplaces.json still reference $legacy_claude/...
            # (which no longer exists post-rename).
            _ckipper_rewrite_plugin_paths "$legacy_claude/" "$target_dir/"

            if ! _ckipper_finalize_registration "$name" "$target_dir" "$probed_service" "migrate"; then
                _ckipper_migrate_rollback failed
                trap - INT TERM HUP QUIT
                return 1
            fi
            trap - INT TERM HUP QUIT
            unset -f _ckipper_migrate_rollback
        fi
    fi

    # ── 3. Best-effort cleanup of old Docker image ────────────────
    if command -v docker >/dev/null 2>&1; then
        docker rmi claude-dev 2>/dev/null && echo "Removed old claude-dev Docker image."
    fi

    # Reload `name` from registry for the success-message context (in case migrate
    # was run for a no-op state and `name` was never set in this scope).
    local registered_name=""
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        registered_name=$(jq -r '.default // (.accounts | keys[0] // "")' "$CKIPPER_REGISTRY")
    fi

    cat <<EOF

Migration complete.

Next steps:
  1. Confirm your ~/.zshrc sources the new path:
       source ~/.ckipper/docker/w-function.zsh
     (install.sh updates this automatically; if you used a manual install, edit it yourself.)
  2. Add to ~/.zshrc to enable per-account aliases AND the bare-claude guard:
       [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
  3. Restart your shell:  exec zsh
  4. Run:  ckipper add <other-account-name>   to add additional accounts.

EOF
    if [[ -n "$registered_name" ]]; then
        cat <<EOF
To launch Claude with your migrated account, use:  claude-$registered_name
(Bare 'claude' no longer resolves to it — the guard in aliases.zsh refuses bare invocation once accounts are registered.)

EOF
    fi
}
