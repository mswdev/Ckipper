#!/usr/bin/env bats
# Unit tests for lib/account/sync/preview.zsh — summary table + drill-down.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_NO_GUM=1 TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/core/style.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/preview.zsh\"; $*"
}

@test "_ckipper_account_sync_render_summary groups by type with status badges" {
    run_in_zsh '
        printf "mcp\tgithub\tgithub\tnew\n" >/tmp/cs.$$
        printf "mcp\tvibma\tvibma\toverwrite\n" >>/tmp/cs.$$
        printf "claude-md\tCLAUDE.md\tCLAUDE.md\tnew\n" >>/tmp/cs.$$
        cat /tmp/cs.$$ \
          | _ckipper_account_sync_render_summary src dst /tmp/backup-dir-stub /tmp/no-summaries
        rm -f /tmp/cs.$$'
    [[ "$output" == *"MCP servers"* ]]
    [[ "$output" == *"[+]"* ]]
    [[ "$output" == *"github"* ]]
    [[ "$output" == *"[~]"* ]]
    [[ "$output" == *"vibma"* ]]
    [[ "$output" == *"CLAUDE.md (user memory)"* ]]
    [[ "$output" == *"Backup →"* ]]
}

@test "_ckipper_account_sync_render_summary suppresses unchanged rows by default" {
    run_in_zsh '
        printf "mcp\tgithub\tgithub\tnew\n" >/tmp/cs.$$
        printf "mcp\tunchanged-srv\tunchanged-srv\tunchanged\n" >>/tmp/cs.$$
        cat /tmp/cs.$$ \
          | _ckipper_account_sync_render_summary src dst /tmp/backup-dir-stub /tmp/no-summaries
        rm -f /tmp/cs.$$'
    [[ "$output" != *"unchanged-srv"* ]]
}

@test "_ckipper_account_sync_count_changes returns total + new + overwrite" {
    run_in_zsh '
        printf "mcp\tgithub\tgithub\tnew\n" >/tmp/cs.$$
        printf "mcp\tvibma\tvibma\toverwrite\n" >>/tmp/cs.$$
        printf "settings\tmodel\tmodel\tnew\n" >>/tmp/cs.$$
        cat /tmp/cs.$$ | _ckipper_account_sync_count_changes
        rm -f /tmp/cs.$$'
    [[ "$output" == *"3 2 1"* ]]
}

@test "_ckipper_account_sync_drill_down_items emits only [~] (overwrite) rows" {
    run_in_zsh '
        printf "mcp\tgithub\tgithub\tnew\n" >/tmp/cs.$$
        printf "mcp\tvibma\tvibma\toverwrite\n" >>/tmp/cs.$$
        printf "settings\tmodel\tmodel\toverwrite\n" >>/tmp/cs.$$
        cat /tmp/cs.$$ | _ckipper_account_sync_drill_down_items
        rm -f /tmp/cs.$$'
    [[ "$output" != *"github"* ]]
    [[ "$output" == *"vibma"* ]]
    [[ "$output" == *"model"* ]]
}

@test "_ckipper_account_sync_drill_down_resolve_id recovers id from (type, display)" {
    run_in_zsh '
        printf "agents\tagents/foo.md\tfoo.md\n" >/tmp/items.$$
        printf "mcp\tgithub\tgithub\n" >>/tmp/items.$$
        result=$(_ckipper_account_sync_drill_down_resolve_id /tmp/items.$$ agents foo.md)
        echo "agents:$result"
        result=$(_ckipper_account_sync_drill_down_resolve_id /tmp/items.$$ mcp github)
        echo "mcp:$result"
        rm -f /tmp/items.$$'
    [[ "$output" == *"agents:agents/foo.md"* ]]
    [[ "$output" == *"mcp:github"* ]]
}
