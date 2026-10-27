#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/hooks.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/hooks.zsh\"; $*"
}

@test "hooks_enumerate lists every script in the source hooks dir" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/hooks"
    echo "x" > "$src/hooks/lint-on-save.sh"
    echo "x" > "$src/hooks/format.sh"

    run_in_zsh "_ckipper_account_sync_hooks_enumerate '$src' | cut -f1 | sort | tr '\n' ','"

    [[ "$output" == *"hooks/format.sh,hooks/lint-on-save.sh,"* ]]
}

@test "hooks_enumerate emits nothing when the hooks dir is empty" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/hooks"

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

# Regression: `*(N)` broke under NO_BARE_GLOB_QUAL (Claude Code's Bash tool).
@test "hooks_enumerate works when the caller set no_bare_glob_qual" {
    local src="$TMP_HOME/src"
    mkdir -p "$src/hooks"
    echo "x" > "$src/hooks/lint.sh"

    run_in_zsh "setopt no_bare_glob_qual; _ckipper_account_sync_hooks_enumerate '$src' | cut -f1"

    [ "$status" -eq 0 ]
    [ "$output" = "hooks/lint.sh" ]
}

# Regression: re-syncing a changed hook appended a second identical entry,
# so the hook ran twice (and once more per re-sync).
@test "hooks_merge_settings replaces an existing entry for the same command instead of duplicating it" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src/hooks" "$dst/hooks"
    echo x > "$src/hooks/lint.sh"
    echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash '"$src"'/hooks/lint.sh"}]}]}}' > "$src/settings.json"
    echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash '"$dst"'/hooks/lint.sh"}]},{"matcher":"Edit","hooks":[{"type":"command","command":"other"}]}]}}' > "$dst/settings.json"

    run_in_zsh "_ckipper_account_sync_hooks_merge_settings '$src' '$dst' hooks/lint.sh"

    [ "$status" -eq 0 ]
    [ "$(jq '[.hooks.PreToolUse[].hooks[] | select(.command | contains("lint.sh"))] | length' "$dst/settings.json")" = "1" ]
    [ "$(jq '[.hooks.PreToolUse[].hooks[] | select(.command == "other")] | length' "$dst/settings.json")" = "1" ]
}
