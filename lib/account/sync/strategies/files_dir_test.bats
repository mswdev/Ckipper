#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/files_dir.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/files_dir.zsh\"; $*"
}

@test "skills_enumerate lists each subdir under skills/" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/skills/foo" "$src/skills/bar"
    run_in_zsh "_ckipper_account_sync_skills_enumerate '$src' | cut -f2 | sort | tr '\n' ','"
    [[ "$output" == *"bar,foo,"* ]]
}

@test "skills_enumerate includes symlinks (treated as items)" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/skills" "$TMP_HOME/shared/some-skill"
    ln -s "$TMP_HOME/shared/some-skill" "$src/skills/some-skill"
    run_in_zsh "_ckipper_account_sync_skills_enumerate '$src' | cut -f2"
    [[ "$output" == *"some-skill"* ]]
}

@test "skills_enumerate emits empty when no skills/ dir" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    run_in_zsh "_ckipper_account_sync_skills_enumerate '$src' | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "skills_compare: new when dst lacks the dir" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/skills/foo" "$dst/skills"
    run_in_zsh "_ckipper_account_sync_skills_compare '$src' '$dst' skills/foo"
    [[ "$output" == *"new"* ]]
}

@test "skills_apply preserves symlinks via cp -a" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/skills" "$dst/skills"
    mkdir -p "$TMP_HOME/shared/sk1"
    echo "skill content" > "$TMP_HOME/shared/sk1/SKILL.md"
    ln -s "$TMP_HOME/shared/sk1" "$src/skills/sk1"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' src)
        _core_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_skills_apply '$src' '$dst' skills/sk1 \"\$backup_dir\"
        [[ -L '$dst/skills/sk1' ]] && echo IS_SYMLINK || echo NOT_SYMLINK
        readlink '$dst/skills/sk1'"
    [[ "$output" == *"IS_SYMLINK"* ]]
    [[ "$output" == *"$TMP_HOME/shared/sk1"* ]]
}

@test "skills_apply copies regular directory recursively" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/skills/foo" "$dst/skills"
    echo "x" > "$src/skills/foo/SKILL.md"
    echo "y" > "$src/skills/foo/extra.md"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' src)
        _core_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_skills_apply '$src' '$dst' skills/foo \"\$backup_dir\"
        cat '$dst/skills/foo/SKILL.md'
        cat '$dst/skills/foo/extra.md'"
    [[ "$output" == *"x"* ]]
    [[ "$output" == *"y"* ]]
}
