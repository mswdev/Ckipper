#!/usr/bin/env bats
# Unit and integration tests for lib/account/groups.zsh.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Run a zsh expression with the full ckipper environment sourced.
run_helper() {
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="linux" CKIPPER_FORCE=1 CKIPPER_NO_GUM=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

# Register accounts (no groups) with empty config dirs under $TMP_HOME.
# Args: account names.
seed_accounts() {
    local registry='{"version":4,"default":null,"accounts":{}}' name
    for name in "$@"; do
        mkdir -p "$TMP_HOME/.claude-$name"
        registry=$(jq --arg n "$name" --arg d "$TMP_HOME/.claude-$name" \
            '.accounts[$n] = {config_dir: $d, registered_at: "t"}' <<<"$registry")
    done
    echo "$registry" > "$CKIPPER_REGISTRY"
    chmod 600 "$CKIPPER_REGISTRY"
}

# ── group assignment ──────────────────────────────────────────────────

@test "the first account in a group becomes its master" {
    seed_accounts personal personal-2

    run_helper 'ckipper account group personal personal && ckipper account group personal-2 personal'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.groups.personal.master' "$CKIPPER_REGISTRY")" = "personal" ]
    [ "$(jq -r '.accounts["personal-2"].group' "$CKIPPER_REGISTRY")" = "personal" ]
}

@test "--master moves the master role to another member" {
    seed_accounts personal personal-2
    run_helper 'ckipper account group personal personal && ckipper account group personal-2 personal'

    run_helper 'ckipper account group personal-2 personal --master'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.groups.personal.master' "$CKIPPER_REGISTRY")" = "personal-2" ]
}

@test "moving the master to another group clears the old group's master" {
    seed_accounts personal
    run_helper 'ckipper account group personal personal'

    run_helper 'ckipper account group personal work'

    [ "$(jq -r '.groups.personal.master' "$CKIPPER_REGISTRY")" = "null" ]
    [ "$(jq -r '.groups.work.master' "$CKIPPER_REGISTRY")" = "personal" ]
}

@test "account group rejects bad usage, bad group names and unknown accounts" {
    seed_accounts personal

    run_helper 'ckipper account group personal'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Usage: ckipper account group" ]]

    run_helper 'ckipper account group personal "Bad Group"'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Group name must match" ]]

    run_helper 'ckipper account group nobody personal'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "removing a group master clears the group's master" {
    seed_accounts personal personal-2
    run_helper 'ckipper account group personal personal && ckipper account group personal-2 personal'

    run_helper 'ckipper account remove personal <<< $'"'"'n\nn'"'"

    [ "$(jq -r '.groups.personal.master' "$CKIPPER_REGISTRY")" = "null" ]
    [ "$(jq -r '.accounts["personal-2"].group' "$CKIPPER_REGISTRY")" = "personal" ]
}

@test "renaming a group master keeps it the master under its new name" {
    seed_accounts personal
    run_helper 'ckipper account group personal personal'

    run_helper 'ckipper account rename personal home'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.groups.personal.master' "$CKIPPER_REGISTRY")" = "home" ]
    [ "$(jq -r '.accounts.home.group' "$CKIPPER_REGISTRY")" = "personal" ]
}

@test "account list shows each account's group and marks the master" {
    seed_accounts personal personal-2 aff
    run_helper 'ckipper account group personal personal && ckipper account group personal-2 personal'

    run_helper 'ckipper account list'

    [[ "$output" =~ personal\ \(master\) ]]
    [[ "$(grep '^aff ' <<<"$output")" =~ " - " ]]
}

# ── sync guard ────────────────────────────────────────────────────────

@test "sync refuses to cross groups" {
    seed_accounts personal aff
    run_helper 'ckipper account group personal personal && ckipper account group aff aff'
    echo '{"env":{"CLAUDE_CODE_REMOTE_MEMORY_DIR":"/personal-mem"}}' > "$TMP_HOME/.claude-personal/settings.json"
    echo '{"env":{"CLAUDE_CODE_REMOTE_MEMORY_DIR":"/work-mem"}}' > "$TMP_HOME/.claude-aff/settings.json"

    run_helper 'ckipper account sync personal aff --include all --yes'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "different groups (personal vs aff)" ]]
    [ "$(jq -r '.env.CLAUDE_CODE_REMOTE_MEMORY_DIR' "$TMP_HOME/.claude-aff/settings.json")" = "/work-mem" ]
}

@test "sync refuses an ungrouped account and says how to fix it" {
    seed_accounts personal stray
    run_helper 'ckipper account group personal personal'

    run_helper 'ckipper account sync personal stray --include mcp --dry-run'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "'stray' is not in a group" ]]
    [[ "$output" =~ "ckipper account group stray <group>" ]]
}

@test "sync within a group still runs" {
    seed_accounts personal personal-2
    run_helper 'ckipper account group personal personal && ckipper account group personal-2 personal'
    echo '{"mcpServers":{"github":{"command":"gh"}}}' > "$TMP_HOME/.claude-personal/.claude.json"

    run_helper 'ckipper account sync personal personal-2 --include mcp --yes'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.mcpServers.github.command' "$TMP_HOME/.claude-personal-2/.claude.json")" = "gh" ]
}

# ── plugin seeding ────────────────────────────────────────────────────

@test "seed_plugins copies installed plugins and rewrites the master's paths" {
    local master="$TMP_HOME/.claude-master" dir="$TMP_HOME/.claude-new"
    mkdir -p "$master/plugins/cache/mkt/p/1.0" "$master/plugins/data/p" "$master/plugins/synced/x" "$dir"
    echo x > "$master/plugins/cache/mkt/p/1.0/plugin.json"
    printf '{"version":2,"plugins":{"p@mkt":[{"installPath":"%s/plugins/cache/mkt/p/1.0"}]}}' "$master" > "$master/plugins/installed_plugins.json"
    printf '{"mkt":{"installLocation":"%s/plugins/marketplaces/mkt"}}' "$master" > "$master/plugins/known_marketplaces.json"

    run_helper "_ckipper_account_seed_plugins '$master' '$dir'"

    [ "$status" -eq 0 ]
    [ -f "$dir/plugins/cache/mkt/p/1.0/plugin.json" ]
    [ "$(jq -r '.plugins["p@mkt"][0].installPath' "$dir/plugins/installed_plugins.json")" = "$dir/plugins/cache/mkt/p/1.0" ]
    [ "$(jq -r '.mkt.installLocation' "$dir/plugins/known_marketplaces.json")" = "$dir/plugins/marketplaces/mkt" ]
    [ ! -e "$dir/plugins/data" ]
    [ ! -e "$dir/plugins/synced" ]
}

@test "seed_plugins keeps entries the new account already has" {
    local master="$TMP_HOME/.claude-master" dir="$TMP_HOME/.claude-new"
    mkdir -p "$master/plugins" "$dir/plugins"
    printf '{"official":{"installLocation":"%s/plugins/marketplaces/official"},"extra":{"installLocation":"%s/plugins/marketplaces/extra"}}' "$master" "$master" > "$master/plugins/known_marketplaces.json"
    printf '{"official":{"installLocation":"%s/plugins/marketplaces/official","lastUpdated":"mine"}}' "$dir" > "$dir/plugins/known_marketplaces.json"

    run_helper "_ckipper_account_seed_plugins '$master' '$dir'"

    [ "$(jq -r '.official.lastUpdated' "$dir/plugins/known_marketplaces.json")" = "mine" ]
    [ "$(jq -r '.extra.installLocation' "$dir/plugins/known_marketplaces.json")" = "$dir/plugins/marketplaces/extra" ]
}

# ── account add --group ───────────────────────────────────────────────

# Put a fake `claude` on PATH that "logs in" by writing on-disk credentials
# and a .claude.json into $CLAUDE_CONFIG_DIR, the way the real /login would.
install_fake_login_claude() {
    mkdir -p "$TMP_HOME/bin"
    cat > "$TMP_HOME/bin/claude" <<'SH'
#!/bin/sh
echo '{}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
echo '{"oauthAccount":{"emailAddress":"new@example.com"}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
SH
    chmod +x "$TMP_HOME/bin/claude"
    export PATH="$TMP_HOME/bin:$PATH"
}

@test "account add --group seeds the new account from the group master" {
    seed_accounts personal
    run_helper 'ckipper account group personal personal'
    local master="$TMP_HOME/.claude-personal"
    echo '{"mcpServers":{"github":{"command":"gh"}}}' > "$master/.claude.json"
    echo '{"env":{"CLAUDE_CODE_REMOTE_MEMORY_DIR":"/personal-mem"},"verbose":false}' > "$master/settings.json"
    mkdir -p "$master/skills/humanizer" "$master/skills/synced/claude-ai" "$master/plugins"
    echo x > "$master/skills/humanizer/SKILL.md"
    printf '{"mkt":{"installLocation":"%s/plugins/marketplaces/mkt"}}' "$master" > "$master/plugins/known_marketplaces.json"
    install_fake_login_claude

    run_helper 'ckipper account add personal-2 --group personal <<< ""'

    [ "$status" -eq 0 ]
    local dir="$TMP_HOME/.claude-personal-2"
    [ "$(jq -r '.accounts["personal-2"].group' "$CKIPPER_REGISTRY")" = "personal" ]
    [ "$(jq -r '.mcpServers.github.command' "$dir/.claude.json")" = "gh" ]
    [ "$(jq -r '.oauthAccount.emailAddress' "$dir/.claude.json")" = "new@example.com" ]
    [ "$(jq -r '.env.CLAUDE_CODE_REMOTE_MEMORY_DIR' "$dir/settings.json")" = "/personal-mem" ]
    [ "$(jq -r 'has("_comment")' "$dir/settings.json")" = "false" ]
    [ -f "$dir/skills/humanizer/SKILL.md" ]
    [ ! -e "$dir/skills/synced" ]
    [ "$(jq -r '.mkt.installLocation' "$dir/plugins/known_marketplaces.json")" = "$dir/plugins/marketplaces/mkt" ]
}

@test "account add --group with a new group makes the account its master and copies nothing" {
    seed_accounts
    install_fake_login_claude

    run_helper 'ckipper account add work --group work <<< ""'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.groups.work.master' "$CKIPPER_REGISTRY")" = "work" ]
    [ ! -f "$TMP_HOME/.claude-work/settings.json" ]
}

@test "account add --adopt --group joins the group without copying" {
    seed_accounts personal
    run_helper 'ckipper account group personal personal'
    echo '{"verbose":true}' > "$TMP_HOME/.claude-personal/settings.json"
    mkdir -p "$TMP_HOME/.claude-personal-3"

    run_helper 'ckipper account add personal-3 --adopt --group personal'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.accounts["personal-3"].group' "$CKIPPER_REGISTRY")" = "personal" ]
    [ ! -f "$TMP_HOME/.claude-personal-3/settings.json" ]
}

@test "account add rejects an unknown option" {
    seed_accounts

    run_helper 'ckipper account add work --grup work'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown option: --grup" ]]
}
