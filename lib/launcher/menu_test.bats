#!/usr/bin/env bats
# Module-level tests for lib/launcher/menu.zsh.
#
# The launcher is a discoverability surface — every menu entry forwards to a
# top-level command. These tests exercise the discrete pieces (banner,
# route-by-label, route_run's empty-projects guard, the menu's Quit arm) but
# intentionally do NOT cover the full menu → run → resolve-account → docker
# path: that requires too much fixture setup and is already covered by the
# orchestration tests in lib/worktree/run_test.bats.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$TMP_HOME/Developer"
}

teardown() {
    teardown_isolated_env
}

# Helper: run a launcher fragment in a zsh subshell. Sources style + prompt +
# the launcher; CKIPPER_NO_GUM=1 forces the pure-zsh fallback so stdin-driven
# choices are deterministic. CKIPPER_PROJECTS_DIR points at the (empty)
# fixture under $TMP_HOME/Developer so route_run finds nothing by default.
#
# Args: $1 — stdin payload; $2 — zsh command to execute after the sources.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_launcher() {
    local stdin="$1" zsh_cmd="$2"
    run env CKIPPER_NO_GUM=1 \
            CKIPPER_PROJECTS_DIR="${CKIPPER_PROJECTS_DIR:-$TMP_HOME/Developer}" \
            HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/prompt.zsh\"
            source \"$REPO_ROOT/lib/launcher/menu.zsh\"
            $zsh_cmd
        " <<<"$stdin"
}

@test "_ckipper_launcher_banner prints Ckipper header and tagline" {
    _run_launcher "" "_ckipper_launcher_banner"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Ckipper" ]]
    [[ "$output" =~ "Multi-account" ]]
}

@test "_ckipper_launcher_route Quit returns 0 without dispatching" {
    _run_launcher "" "_ckipper_launcher_route Quit"

    [ "$status" -eq 0 ]
}

@test "_ckipper_launcher_menu Quit selection returns 0" {
    # "Quit" is the 11th option in _CKIPPER_LAUNCHER_OPTIONS.
    _run_launcher "11" "_ckipper_launcher_menu"

    [ "$status" -eq 0 ]
}

@test "_ckipper_launcher_route_run errors when no projects exist" {
    _run_launcher "" "_ckipper_launcher_route_run 2>&1"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "No projects" ]]
}

@test "_ckipper_launcher_route returns 1 on unknown label" {
    _run_launcher "" "_ckipper_launcher_route 'Not a real option'"

    [ "$status" -eq 1 ]
}
