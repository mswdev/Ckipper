#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/statusline.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/statusline.zsh\"; $*"
}

@test "statusline_enumerate emits a single entry when statusLine is set" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"statusLine":{"command":"/usr/bin/echo hi"}}' > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_statusline_enumerate '$src' | cut -f1"
    [[ "$output" == *"statusLine"* ]]
}

@test "statusline_enumerate empty when statusLine missing" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{}' > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_statusline_enumerate '$src' | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "statusline_internal_script_path detects script inside src dir" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo "{\"statusLine\":{\"command\":\"$src/my-statusline.sh\"}}" > "$src/settings.json"
    echo "#!/bin/bash" > "$src/my-statusline.sh"
    run_in_zsh "_ckipper_account_sync_statusline_internal_path '$src'"
    [[ "$output" == *"$src/my-statusline.sh"* ]]
}

@test "statusline_internal_script_path returns empty when external" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"statusLine":{"command":"/usr/bin/echo hi"}}' > "$src/settings.json"
    run_in_zsh "out=\$(_ckipper_account_sync_statusline_internal_path '$src'); echo \"[\$out]\""
    [[ "$output" == *"[]"* ]]
}

@test "statusline_internal_script_path detects interpreter-prefix command" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo "#!/bin/bash" > "$src/my-statusline.sh"
    # The common real-world form: "bash <path>" with an interpreter prefix.
    echo "{\"statusLine\":{\"command\":\"bash $src/my-statusline.sh\"}}" > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_statusline_internal_path '$src'"
    [[ "$output" == *"$src/my-statusline.sh"* ]]
}

@test "statusline_apply: interpreter-prefix internal — copy + rewrite path" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo "#!/bin/bash" > "$src/my-statusline.sh"
    chmod +x "$src/my-statusline.sh"
    echo "{\"statusLine\":{\"command\":\"bash $src/my-statusline.sh\"}}" > "$src/settings.json"
    echo '{}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_statusline_apply '$src' '$dst' statusLine \"\$backup_dir\"
        jq -r '.statusLine.command' '$dst/settings.json'
        ls '$dst/my-statusline.sh' && echo COPIED"
    [[ "$output" == *"bash $dst/my-statusline.sh"* ]]
    [[ "$output" == *"COPIED"* ]]
    [[ "$output" != *"$src/my-statusline.sh"* ]]
}

@test "statusline_apply: external script — settings only, no file copy" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"statusLine":{"command":"/usr/bin/echo hi"}}' > "$src/settings.json"
    echo '{}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_statusline_apply '$src' '$dst' statusLine \"\$backup_dir\"
        jq -r '.statusLine.command' '$dst/settings.json'
        ls '$dst' | grep -c statusline.sh || true"
    [[ "$output" == *"/usr/bin/echo hi"* ]]
    [[ "$output" == *"0"* ]]
}

@test "statusline_apply: internal script — copy file + rewrite reference" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo "#!/bin/bash" > "$src/my-statusline.sh"
    chmod +x "$src/my-statusline.sh"
    echo "{\"statusLine\":{\"command\":\"$src/my-statusline.sh\"}}" > "$src/settings.json"
    echo '{}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_statusline_apply '$src' '$dst' statusLine \"\$backup_dir\"
        jq -r '.statusLine.command' '$dst/settings.json'
        ls '$dst/my-statusline.sh' && echo COPIED"
    [[ "$output" == *"$dst/my-statusline.sh"* ]]
    [[ "$output" == *"COPIED"* ]]
}
