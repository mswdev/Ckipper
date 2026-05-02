#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/hooks.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    # Simulate ckipper install hook set so the allowlist filter has data.
    mkdir -p "$CKIPPER_DIR/hooks"
    touch "$CKIPPER_DIR/hooks/bash-guardrails.sh"
    touch "$CKIPPER_DIR/hooks/protect-claude-config.sh"
    touch "$CKIPPER_DIR/hooks/docker-context.sh"
    touch "$CKIPPER_DIR/hooks/notify-bell.sh"
}
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/files_flat.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/hooks.zsh\"; $*"
}

@test "hooks_enumerate skips ckipper safety hooks (filename allowlist)" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/hooks"
    # Two safety hooks (mirroring install dir) — should be filtered.
    echo "x" > "$src/hooks/bash-guardrails.sh"
    echo "x" > "$src/hooks/notify-bell.sh"
    # One user hook — should appear.
    echo "x" > "$src/hooks/lint-on-save.sh"
    run_in_zsh "_ckipper_account_sync_hooks_enumerate '$src' | cut -f1"
    [[ "$output" == *"hooks/lint-on-save.sh"* ]]
    [[ "$output" != *"bash-guardrails.sh"* ]]
    [[ "$output" != *"notify-bell.sh"* ]]
}

@test "hooks_enumerate emits empty when no user hooks present" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/hooks"
    echo "x" > "$src/hooks/bash-guardrails.sh"
    run_in_zsh "_ckipper_account_sync_hooks_enumerate '$src' | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "hooks_compare: new when destination lacks the script" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/hooks" "$dst/hooks"
    echo "x" > "$src/hooks/lint.sh"
    run_in_zsh "_ckipper_account_sync_hooks_compare '$src' '$dst' hooks/lint.sh"
    [[ "$output" == *"new"* ]]
}

@test "hooks_apply copies the script AND adds the paired settings entry" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/hooks" "$dst/hooks"
    echo "#!/bin/bash" > "$src/hooks/lint.sh"
    cat > "$src/settings.json" <<JSON
{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"bash $src/hooks/lint.sh"}]}]}}
JSON
    echo '{}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_core_account_sync_backup_create '$dst' src)
        _core_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_hooks_apply '$src' '$dst' hooks/lint.sh \"\$backup_dir\"
        cat '$dst/hooks/lint.sh'
        jq -r '.hooks.PostToolUse[0].hooks[0].command' '$dst/settings.json'"
    [[ "$output" == *"#!/bin/bash"* ]]
    [[ "$output" == *"$dst/hooks/lint.sh"* ]]
    [[ "$output" != *"$src/hooks/lint.sh"* ]]
}
