#!/usr/bin/env bats
# Unit tests for lib/account/sync/strategies/structured.zsh.

load "${BATS_TEST_DIRNAME}/../../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; $*"
}

@test "_ckipper_account_sync_json_validate accepts valid JSON" {
    local f="$TMP_HOME/ok.json"
    echo '{"a": 1}' > "$f"
    run_in_zsh "_ckipper_account_sync_json_validate '$f' && echo OK"
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_json_validate rejects invalid JSON" {
    local f="$TMP_HOME/bad.json"
    echo '{"a": 1' > "$f"
    run_in_zsh "_ckipper_account_sync_json_validate '$f'"
    [ "$status" -ne 0 ]
}

@test "_ckipper_account_sync_json_atomic_write writes via tmp + mv" {
    local f="$TMP_HOME/out.json"
    run_in_zsh "_ckipper_account_sync_json_atomic_write '$f' '{\"x\":42}'; cat '$f'"
    [[ "$output" == *'"x": 42'* ]]
}

@test "_ckipper_account_sync_json_atomic_write refuses to commit invalid JSON" {
    local f="$TMP_HOME/out2.json"
    run_in_zsh "_ckipper_account_sync_json_atomic_write '$f' 'not-json'"
    [ "$status" -ne 0 ]
    [[ ! -f "$f" ]]
}

# ── MCP strategy ─────────────────────────────────────────────────────────

@test "mcp_enumerate lists every server name" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"mcpServers":{"github":{"command":"x"},"vibma":{"command":"y"}}}' > "$src/.claude.json"
    run_in_zsh "_ckipper_account_sync_mcp_enumerate '$src' | sort"
    [[ "$output" == *"github"* ]]
    [[ "$output" == *"vibma"* ]]
}

@test "mcp_enumerate emits empty when no .claude.json" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    run_in_zsh "_ckipper_account_sync_mcp_enumerate '$src' | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "mcp_compare: new when destination lacks the server" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run_in_zsh "_ckipper_account_sync_mcp_compare '$src' '$dst' github"
    [[ "$output" == *"new"* ]]
}

@test "mcp_compare: unchanged when both sides match" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    local both='{"mcpServers":{"github":{"command":"x","args":["a"]}}}'
    echo "$both" > "$src/.claude.json"
    echo "$both" > "$dst/.claude.json"
    run_in_zsh "_ckipper_account_sync_mcp_compare '$src' '$dst' github"
    [[ "$output" == *"unchanged"* ]]
}

@test "mcp_compare: overwrite when contents differ" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"new"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"github":{"command":"old"}}}' > "$dst/.claude.json"
    run_in_zsh "_ckipper_account_sync_mcp_compare '$src' '$dst' github"
    [[ "$output" == *"overwrite"* ]]
}

@test "mcp_apply merges into destination preserving other servers" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"other":{"command":"y"}},"foo":"bar"}' > "$dst/.claude.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_mcp_apply '$src' '$dst' github \"\$backup_dir\"
        jq '.mcpServers | keys | sort | join(\",\")' '$dst/.claude.json'
        jq -r '.foo' '$dst/.claude.json'"
    [[ "$output" == *'"github,other"'* ]]
    [[ "$output" == *"bar"* ]]
}

# ── Settings strategy ────────────────────────────────────────────────────

@test "settings_enumerate emits top-level keys" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"statusLine":{"command":"x"},"env":{"FOO":"1"},"model":"opus"}' > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_settings_enumerate '$src' | cut -f1 | sort | tr '\n' ','"
    [[ "$output" == *"env.FOO"* ]]
    [[ "$output" == *"model"* ]]
    [[ "$output" == *"statusLine.command"* ]]
}

@test "settings_enumerate excludes the .hooks block" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"statusLine":{"command":"x"},"hooks":{"PreToolUse":[]}}' > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_settings_enumerate '$src' | cut -f1"
    [[ "$output" != *"hooks"* ]]
    [[ "$output" == *"statusLine"* ]]
}

@test "settings_enumerate produces nested jq paths for object-typed values" {
    local src="$TMP_HOME/src"
    mkdir -p "$src"
    echo '{"permissions":{"allow":["Bash(ls:*)"],"deny":["Bash(rm:*)"]}}' > "$src/settings.json"
    run_in_zsh "_ckipper_account_sync_settings_enumerate '$src' | cut -f1 | sort | tr '\n' ','"
    [[ "$output" == *"permissions.allow,permissions.deny,"* ]]
}

@test "settings_compare: new when path missing in destination" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"model":"opus"}' > "$src/settings.json"
    echo '{}' > "$dst/settings.json"
    run_in_zsh "_ckipper_account_sync_settings_compare '$src' '$dst' model"
    [[ "$output" == *"new"* ]]
}

@test "settings_compare: unchanged when values match" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"model":"opus"}' > "$src/settings.json"
    echo '{"model":"opus"}' > "$dst/settings.json"
    run_in_zsh "_ckipper_account_sync_settings_compare '$src' '$dst' model"
    [[ "$output" == *"unchanged"* ]]
}

@test "settings_apply writes nested path without disturbing siblings" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$src/settings.json"
    echo '{"permissions":{"deny":["Bash(rm:*)"]},"unrelated":"keep"}' > "$dst/settings.json"
    run_in_zsh "
        backup_dir=\$(_ckipper_account_sync_backup_create '$dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_settings_apply '$src' '$dst' 'permissions.allow' \"\$backup_dir\"
        jq -c '.permissions.allow' '$dst/settings.json'
        jq -c '.permissions.deny' '$dst/settings.json'
        jq -r '.unrelated' '$dst/settings.json'"
    [[ "$output" == *'["Bash(ls:*)"]'* ]]
    [[ "$output" == *'["Bash(rm:*)"]'* ]]
    [[ "$output" == *"keep"* ]]
}

# ── Prefs strategy ───────────────────────────────────────────────────────

setup_prefs_registry() {
    cat > "$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"src","accounts":{
    "src":{"config_dir":"$TMP_HOME/src","keychain_service":null,"registered_at":"t","preferences":{"always_docker":true,"always_firewall":false,"ssh_forward":true}},
    "dst":{"config_dir":"$TMP_HOME/dst","keychain_service":null,"registered_at":"t","preferences":{"always_docker":false,"always_firewall":false,"ssh_forward":false}}
}}
JSON
    chmod 600 "$CKIPPER_REGISTRY"
}

@test "prefs_enumerate lists the 3 schema keys" {
    setup_prefs_registry
    run_in_zsh "
        source \"$REPO_ROOT/lib/config/schema.zsh\"
        _ckipper_account_sync_prefs_enumerate 'src' | cut -f1 | sort | tr '\n' ','"
    [[ "$output" == *"always_docker,always_firewall,ssh_forward,"* ]]
}

@test "prefs_compare: new when destination has no override (default value)" {
    setup_prefs_registry
    run_in_zsh "
        source \"$REPO_ROOT/lib/config/schema.zsh\"
        source \"$REPO_ROOT/lib/core/config.zsh\"
        _ckipper_account_sync_prefs_compare 'src' 'dst' always_docker"
    [[ "$output" == *"overwrite"* ]]
}

@test "prefs_compare: unchanged when values match" {
    setup_prefs_registry
    run_in_zsh "
        source \"$REPO_ROOT/lib/config/schema.zsh\"
        source \"$REPO_ROOT/lib/core/config.zsh\"
        _ckipper_account_sync_prefs_compare 'src' 'dst' always_firewall"
    [[ "$output" == *"unchanged"* ]]
}

@test "prefs_apply writes the source value to the destination's registry entry" {
    setup_prefs_registry
    run_in_zsh "
        source \"$REPO_ROOT/lib/config/schema.zsh\"
        source \"$REPO_ROOT/lib/core/registry.zsh\"
        source \"$REPO_ROOT/lib/core/config.zsh\"
        backup_dir=\$(_ckipper_account_sync_backup_create '$TMP_HOME/dst' src)
        _ckipper_account_sync_manifest_init \"\$backup_dir\" src dst
        _ckipper_account_sync_prefs_apply 'src' 'dst' always_docker \"\$backup_dir\"
        jq '.accounts.dst.preferences.always_docker' '$CKIPPER_REGISTRY'"
    [[ "$output" == *"true"* ]]
}
