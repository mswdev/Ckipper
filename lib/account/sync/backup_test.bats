#!/usr/bin/env bats
# Unit tests for lib/account/sync/backup.zsh — backup creation, manifest, undo.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; $*"
}

@test "_ckipper_account_sync_backup_dir_path generates a UTC ISO timestamp" {
    run_in_zsh '
        path=$(_ckipper_account_sync_backup_dir_path "/tmp/dst" "personal")
        echo "$path"'
    [ "$status" -eq 0 ]
    [[ "$output" == */tmp/dst/.ckipper-sync-backups/*-from-personal* ]]
}

@test "_ckipper_account_sync_backup_create makes the dir 0700" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        echo \"\$backup_dir\""
    [ "$status" -eq 0 ]
    local dir; dir=$(echo "$output" | tail -1)
    [[ -d "$dir" ]]
    local mode; mode=$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null)
    [[ "$mode" == "700" ]]
}

@test "_ckipper_account_sync_backup_file copies a regular file with 0600" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original content" > "$dst/hooks/foo.sh"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        cat \"\$backup_dir/hooks/foo.sh\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"original content"* ]]
}

@test "_ckipper_account_sync_backup_file is a no-op for missing source (operation == create)" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/does-not-exist' 'phantom' && echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_backup_file is idempotent: second call preserves original snapshot" {
    # Two strategies (e.g. settings + statusline) both back up settings.json.
    # The first call must capture the pre-sync state; the second must NOT
    # overwrite it with the post-first-write intermediate state, otherwise
    # rollback restores a corrupted baseline.
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    echo "ORIGINAL" > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/settings.json' 'settings.json'
        echo MODIFIED > '$dst/settings.json'
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/settings.json' 'settings.json'
        cat \"\$backup_dir/settings.json\""
    [[ "$output" == *"ORIGINAL"* ]]
    [[ "$output" != *"MODIFIED"* ]]
}

@test "_ckipper_account_sync_backup_file copies directories recursively (cp -a)" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/skills/foo"
    echo "a" > "$dst/skills/foo/SKILL.md"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/skills/foo' 'skills/foo'
        cat \"\$backup_dir/skills/foo/SKILL.md\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"a"* ]]
}

@test "_ckipper_account_sync_manifest_init writes a valid empty manifest" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        cat \"\$backup_dir/.ckipper-sync-manifest.json\" | jq -r '.version, .source, .target'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"personal"* ]]
    [[ "$output" == *"work"* ]]
}

@test "_ckipper_account_sync_manifest_append cleans up its tmp file when jq fails" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        # Corrupt the manifest so jq exits non-zero on the next append.
        echo 'not-json' > \"\$backup_dir/.ckipper-sync-manifest.json\"
        _ckipper_account_sync_manifest_append \"\$backup_dir\" 'x' overwrite mcp 'a' 2>/dev/null
        # Tmp files match .ckipper-sync-manifest.json.XXXXXX in the backup dir.
        ls \"\$backup_dir\"/.ckipper-sync-manifest.json.* 2>/dev/null | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "_ckipper_account_sync_manifest_append adds an entry" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        _ckipper_account_sync_manifest_append \"\$backup_dir\" 'settings.json' overwrite mcp 'github,vibma'
        jq -r '.files | length' \"\$backup_dir/.ckipper-sync-manifest.json\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

@test "_ckipper_account_sync_manifest_list_backups sorts newest first" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/.ckipper-sync-backups/2026-01-01T00-00-00Z-from-a"
    mkdir -p "$dst/.ckipper-sync-backups/2026-05-02T00-00-00Z-from-b"
    mkdir -p "$dst/.ckipper-sync-backups/2026-03-15T00-00-00Z-from-c"
    run_in_zsh "_ckipper_account_sync_manifest_list_backups '$dst' | head -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2026-05-02T00-00-00Z-from-b"* ]]
}

@test "_ckipper_account_sync_rollback_target restores backed-up files atomically" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original" > "$dst/hooks/foo.sh"

    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        _ckipper_account_sync_manifest_append \"\$backup_dir\" 'hooks/foo.sh' overwrite hooks foo.sh
        echo modified > '$dst/hooks/foo.sh'
        _ckipper_account_sync_rollback_target \"\$backup_dir\" '$dst'
        cat '$dst/hooks/foo.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"original"* ]]
    [[ "$output" != *"modified"* ]]
}

@test "_ckipper_account_sync_rollback_target removes files marked operation=create" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"

    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        _ckipper_account_sync_manifest_append \"\$backup_dir\" 'hooks/new.sh' create hooks new.sh
        echo new-content > '$dst/hooks/new.sh'
        _ckipper_account_sync_rollback_target \"\$backup_dir\" '$dst'
        [[ -e '$dst/hooks/new.sh' ]] && echo STILL_THERE || echo GONE"
    [[ "$output" == *"GONE"* ]]
}

@test "_ckipper_account_sync_undo_from_backup restores and removes backup dir" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original" > "$dst/hooks/foo.sh"

    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' personal)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" personal work
        _ckipper_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        _ckipper_account_sync_manifest_append \"\$backup_dir\" 'hooks/foo.sh' overwrite hooks foo.sh
        echo modified > '$dst/hooks/foo.sh'
        _ckipper_account_sync_undo_from_backup \"\$backup_dir\" '$dst'
        echo \"--\"
        cat '$dst/hooks/foo.sh'
        echo \"--\"
        [[ -d \"\$backup_dir\" ]] && echo BACKUP_KEPT || echo BACKUP_REMOVED"
    [[ "$output" == *"original"* ]]
    [[ "$output" == *"BACKUP_REMOVED"* ]]
}

# ── live_path + type-aware rollback (Bug G fix) ──────────────────────────

@test "_ckipper_account_sync_live_path returns CKIPPER_REGISTRY for type=prefs" {
    run_in_zsh "
        export CKIPPER_REGISTRY='$TMP_HOME/.ckipper/accounts.json'
        _ckipper_account_sync_live_path prefs '$TMP_HOME/dst' 'accounts.json'"
    [[ "$output" == *".ckipper/accounts.json"* ]]
    [[ "$output" != *"/dst/accounts.json"* ]]
}

@test "_ckipper_account_sync_live_path returns dst/rel for non-prefs types" {
    run_in_zsh "_ckipper_account_sync_live_path mcp '$TMP_HOME/dst' '.claude.json'"
    [[ "$output" == *"$TMP_HOME/dst/.claude.json"* ]]
}

@test "_ckipper_account_sync_live_path falls back to dst/rel when type is empty" {
    run_in_zsh "_ckipper_account_sync_live_path '' '$TMP_HOME/dst' 'foo'"
    [[ "$output" == *"$TMP_HOME/dst/foo"* ]]
}

# Bug G: prefs rollback used to write to $dst_dir/accounts.json, NOT to
# $CKIPPER_REGISTRY — silently corrupting the registry restore. Fix passes
# the type field from the manifest through to rollback_one so prefs is
# correctly routed to the registry.
@test "_ckipper_account_sync_rollback_target restores prefs to CKIPPER_REGISTRY (Bug G)" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst" "$TMP_HOME/.ckipper"
    local registry="$TMP_HOME/.ckipper/accounts.json"
    echo '{"version":2,"original":"yes"}' > "$registry"

    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        CKIPPER_REGISTRY="$registry" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src); \
                _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst; \
                _ckipper_account_sync_backup_file \"\$backup_dir\" '$registry' 'accounts.json'; \
                _ckipper_account_sync_manifest_append \"\$backup_dir\" 'accounts.json' overwrite prefs always_docker; \
                echo '{\"version\":2,\"corrupted\":\"yes\"}' > '$registry'; \
                _ckipper_account_sync_rollback_target \"\$backup_dir\" '$dst'; \
                jq -r '.original // \"missing\"' '$registry'; \
                [[ -e '$dst/accounts.json' ]] && echo STRAY_DST_FILE || echo NO_STRAY"
    [[ "$output" == *"yes"* ]]
    [[ "$output" == *"NO_STRAY"* ]]
}
