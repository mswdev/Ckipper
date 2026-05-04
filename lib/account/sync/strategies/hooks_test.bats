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
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
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

@test "hooks_filter_src: literal substring rewrite (not regex) when src path contains a dot" {
    # src path has `.` (regex metachar); a separate command that happens to
    # match the regex but NOT the literal substring must be left alone.
    local src="$TMP_HOME/.claude-personal" dst="$TMP_HOME/.claude-work"
    mkdir -p "$src/hooks" "$dst/hooks"
    touch "$src/hooks/lint.sh"
    # Settings hook command references TWO paths:
    #   A) the literal src path — should be rewritten to dst
    #   B) a different path that matches the src regex (`.` matches `-`)
    #      — must NOT be rewritten
    cat > "$src/settings.json" <<JSON
{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"bash $src/hooks/lint.sh && echo $TMP_HOME/Xclaude-personal/marker"}]}]}}
JSON
    run_in_zsh "_ckipper_account_sync_hooks_filter_src '$src/settings.json' lint.sh '$src' '$dst' \
        | jq -r '.PostToolUse[0].hooks[0].command'"
    # The literal-src half got rewritten…
    [[ "$output" == *"$dst/hooks/lint.sh"* ]]
    # …and the regex-only-matching marker was left untouched.
    [[ "$output" == *"$TMP_HOME/Xclaude-personal/marker"* ]]
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
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_hooks_apply '$src' '$dst' hooks/lint.sh \"\$backup_dir\"
        cat '$dst/hooks/lint.sh'
        jq -r '.hooks.PostToolUse[0].hooks[0].command' '$dst/settings.json'"
    [[ "$output" == *"#!/bin/bash"* ]]
    [[ "$output" == *"$dst/hooks/lint.sh"* ]]
    [[ "$output" != *"$src/hooks/lint.sh"* ]]
}

# Bug F: hooks_apply mutates settings.json (adding the paired .hooks entry)
# but the engine's apply_one only recorded a manifest entry for the script
# file (manifest_rel returns "<id>" for hooks, which is the script relpath).
# The settings.json mutation was untracked, so a rollback after a hook sync
# left the destination with a phantom .hooks entry pointing at a deleted
# script. Fix: hooks_apply explicitly appends a settings.json manifest
# entry alongside the script entry.
@test "hooks_apply records settings.json mutation in the manifest (Bug F)" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/hooks" "$dst/hooks"
    echo "#!/bin/bash" > "$src/hooks/lint.sh"
    cat > "$src/settings.json" <<JSON
{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"bash $src/hooks/lint.sh"}]}]}}
JSON
    echo '{}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_hooks_apply '$src' '$dst' hooks/lint.sh \"\$backup_dir\"
        jq -r '.files[].path' \"\$backup_dir/.ckipper-sync-manifest.json\" | sort | tr '\n' ','"
    [[ "$output" == *"settings.json"* ]]
}

# Bug F end-to-end: rollback after hook sync restores settings.json — without
# the manifest entry from the fix, rollback would leave the .hooks block
# polluted with the synced entry pointing at a (deleted) script.
@test "rollback after hook sync removes script AND restores settings.json (Bug F)" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/hooks" "$dst/hooks"
    echo "#!/bin/bash" > "$src/hooks/lint.sh"
    cat > "$src/settings.json" <<JSON
{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"bash $src/hooks/lint.sh"}]}]}}
JSON
    # Pre-existing settings.json on dst — rollback must restore THIS state.
    echo '{"keep":"this"}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_hooks_apply '$src' '$dst' hooks/lint.sh \"\$backup_dir\"
        # Sanity: post-apply, settings.json has the synced .hooks entry.
        jq -r '.hooks.PostToolUse | length' '$dst/settings.json'
        # Roll back.
        _ckipper_account_sync_rollback_target \"\$backup_dir\" '$dst'
        # The script must be gone…
        [[ -f '$dst/hooks/lint.sh' ]] && echo SCRIPT_KEPT || echo SCRIPT_GONE
        # …and settings.json restored to the pre-sync state (no .hooks block).
        jq -r '.keep' '$dst/settings.json'
        jq -e '.hooks' '$dst/settings.json' >/dev/null 2>&1 && echo STILL_HOOKED || echo CLEAN"
    [[ "$output" == *"SCRIPT_GONE"* ]]
    [[ "$output" == *"this"* ]]
    [[ "$output" == *"CLEAN"* ]]
}
