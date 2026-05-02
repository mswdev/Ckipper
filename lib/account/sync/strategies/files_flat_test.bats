#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/files_flat.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/files_flat.zsh\"; $*"
}

@test "agents_enumerate lists .md files in agents/" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/agents"
    echo "a" > "$src/agents/foo.md"
    echo "b" > "$src/agents/bar.md"
    run_in_zsh "_ckipper_account_sync_agents_enumerate '$src' | cut -f1 | sort | tr '\n' ','"
    [[ "$output" == *"agents/bar.md,agents/foo.md,"* ]]
}

@test "commands_enumerate lists .md files in commands/" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/commands"
    echo "x" > "$src/commands/deploy.md"
    run_in_zsh "_ckipper_account_sync_commands_enumerate '$src' | cut -f1"
    [[ "$output" == *"commands/deploy.md"* ]]
}

@test "claude-md_enumerate emits a single CLAUDE.md entry when present" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo "user memory" > "$src/CLAUDE.md"
    run_in_zsh "_ckipper_account_sync_claude-md_enumerate '$src' | cut -f1"
    [[ "$output" == *"CLAUDE.md"* ]]
}

@test "claude-md_enumerate is empty when CLAUDE.md absent" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    run_in_zsh "_ckipper_account_sync_claude-md_enumerate '$src' | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "files_flat_compare: new when destination lacks the file" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/agents" "$dst/agents"
    echo "x" > "$src/agents/foo.md"
    run_in_zsh "_ckipper_account_sync_agents_compare '$src' '$dst' agents/foo.md"
    [[ "$output" == *"new"* ]]
}

@test "files_flat_compare: unchanged when contents match" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/agents" "$dst/agents"
    echo "x" > "$src/agents/foo.md"
    echo "x" > "$dst/agents/foo.md"
    run_in_zsh "_ckipper_account_sync_agents_compare '$src' '$dst' agents/foo.md"
    [[ "$output" == *"unchanged"* ]]
}

@test "files_flat_compare: overwrite when contents differ" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/agents" "$dst/agents"
    echo "new" > "$src/agents/foo.md"
    echo "old" > "$dst/agents/foo.md"
    run_in_zsh "_ckipper_account_sync_agents_compare '$src' '$dst' agents/foo.md"
    [[ "$output" == *"overwrite"* ]]
}

@test "files_flat_summary returns +N/-N line stats for overwrite" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    printf 'a\nb\nc\n' > "$src/CLAUDE.md"
    printf 'a\nx\n' > "$dst/CLAUDE.md"
    run_in_zsh "_ckipper_account_sync_claude-md_summary '$src' '$dst' CLAUDE.md"
    [[ "$output" == *"+"* ]]
    [[ "$output" == *"-"* ]]
    [[ "$output" == *"lines"* ]]
}

@test "files_flat_apply copies file with backup of prior content" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/commands" "$dst/commands"
    echo "new content" > "$src/commands/deploy.md"
    echo "old content" > "$dst/commands/deploy.md"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_commands_apply '$src' '$dst' commands/deploy.md \"\$backup_dir\"
        cat '$dst/commands/deploy.md'
        cat \"\$backup_dir/commands/deploy.md\""
    [[ "$output" == *"new content"* ]]
    [[ "$output" == *"old content"* ]]
}
