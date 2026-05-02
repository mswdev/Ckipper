#!/usr/bin/env bats
# Unit tests for lib/account/sync/backup.zsh — backup creation, manifest, undo.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; $*"
}

@test "_core_account_sync_backup_dir_path generates a UTC ISO timestamp" {
    run_in_zsh '
        path=$(_core_account_sync_backup_dir_path "/tmp/dst" "personal")
        echo "$path"'
    [ "$status" -eq 0 ]
    [[ "$output" == */tmp/dst/.ckipper-sync-backups/*-from-personal* ]]
}

@test "_core_account_sync_backup_create makes the dir 0700" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        echo \"\$backup_dir\""
    [ "$status" -eq 0 ]
    local dir; dir=$(echo "$output" | tail -1)
    [[ -d "$dir" ]]
    local mode; mode=$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null)
    [[ "$mode" == "700" ]]
}

@test "_core_account_sync_backup_file copies a regular file with 0600" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original content" > "$dst/hooks/foo.sh"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        cat \"\$backup_dir/hooks/foo.sh\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"original content"* ]]
}

@test "_core_account_sync_backup_file is a no-op for missing source (operation == create)" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_backup_file \"\$backup_dir\" '$dst/does-not-exist' 'phantom' && echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_backup_file copies directories recursively (cp -a)" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/skills/foo"
    echo "a" > "$dst/skills/foo/SKILL.md"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_backup_file \"\$backup_dir\" '$dst/skills/foo' 'skills/foo'
        cat \"\$backup_dir/skills/foo/SKILL.md\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"a"* ]]
}

@test "_core_account_sync_manifest_init writes a valid empty manifest" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_manifest_init \"\$backup_dir\" personal work
        cat \"\$backup_dir/.ckipper-sync-manifest.json\" | jq -r '.version, .source, .target'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"personal"* ]]
    [[ "$output" == *"work"* ]]
}

@test "_core_account_sync_manifest_append adds an entry" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_manifest_init \"\$backup_dir\" personal work
        _core_account_sync_manifest_append \"\$backup_dir\" 'settings.json' overwrite mcp 'github,vibma'
        jq -r '.files | length' \"\$backup_dir/.ckipper-sync-manifest.json\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

@test "_core_account_sync_manifest_list_backups sorts newest first" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/.ckipper-sync-backups/2026-01-01T00-00-00Z-from-a"
    mkdir -p "$dst/.ckipper-sync-backups/2026-05-02T00-00-00Z-from-b"
    mkdir -p "$dst/.ckipper-sync-backups/2026-03-15T00-00-00Z-from-c"
    run_in_zsh "_core_account_sync_manifest_list_backups '$dst' | head -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2026-05-02T00-00-00Z-from-b"* ]]
}

@test "_core_account_sync_rollback_target restores backed-up files atomically" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original" > "$dst/hooks/foo.sh"

    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_manifest_init \"\$backup_dir\" personal work
        _core_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        _core_account_sync_manifest_append \"\$backup_dir\" 'hooks/foo.sh' overwrite hooks foo.sh
        echo modified > '$dst/hooks/foo.sh'
        _core_account_sync_rollback_target \"\$backup_dir\" '$dst'
        cat '$dst/hooks/foo.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"original"* ]]
    [[ "$output" != *"modified"* ]]
}

@test "_core_account_sync_rollback_target removes files marked operation=create" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"

    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_manifest_init \"\$backup_dir\" personal work
        _core_account_sync_manifest_append \"\$backup_dir\" 'hooks/new.sh' create hooks new.sh
        echo new-content > '$dst/hooks/new.sh'
        _core_account_sync_rollback_target \"\$backup_dir\" '$dst'
        [[ -e '$dst/hooks/new.sh' ]] && echo STILL_THERE || echo GONE"
    [[ "$output" == *"GONE"* ]]
}

@test "_core_account_sync_undo_from_backup restores and removes backup dir" {
    local dst="$TMP_HOME/dest"
    mkdir -p "$dst/hooks"
    echo "original" > "$dst/hooks/foo.sh"

    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' personal)
        _core_account_sync_manifest_init \"\$backup_dir\" personal work
        _core_account_sync_backup_file \"\$backup_dir\" '$dst/hooks/foo.sh' 'hooks/foo.sh'
        _core_account_sync_manifest_append \"\$backup_dir\" 'hooks/foo.sh' overwrite hooks foo.sh
        echo modified > '$dst/hooks/foo.sh'
        _core_account_sync_undo_from_backup \"\$backup_dir\" '$dst'
        echo \"--\"
        cat '$dst/hooks/foo.sh'
        echo \"--\"
        [[ -d \"\$backup_dir\" ]] && echo BACKUP_KEPT || echo BACKUP_REMOVED"
    [[ "$output" == *"original"* ]]
    [[ "$output" == *"BACKUP_REMOVED"* ]]
}
