# Common test helpers loaded at the top of every *_test.bats file.
# Usage: load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"
#         (for files colocated with their source — BATS_TEST_DIRNAME points to
#          the same dir as the .bats file, so the relative path from there.)

# Repo root (resolved from any test file location).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Set up a clean per-test temp HOME and prepend stubs to PATH.
setup_isolated_env() {
    TMP_HOME="$(mktemp -d -t ckipper-test-XXXXXX)"
    export TMP_HOME
    export HOME="$TMP_HOME"
    export CKIPPER_DIR="$TMP_HOME/.ckipper"
    export CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
    # Prepend stubs so `security`, `pgrep`, `docker`, `lsof` are intercepted.
    export PATH="$REPO_ROOT/tests/lib/stubs:$PATH"
    # Override OSTYPE in ckipper: "linux" skips all macOS Keychain branches.
    export _CKIPPER_TEST_OSTYPE="linux"
    # Bypass the "Claude is running" guard so real Claude.app on the host
    # does not abort test runs (pgrep stub also handles this, but belt+suspenders).
    export CKIPPER_FORCE=1
    mkdir -p "$CKIPPER_DIR"
}

teardown_isolated_env() {
    [[ -n "$TMP_HOME" && -d "$TMP_HOME" ]] && rm -rf "$TMP_HOME"
}

# Run a ckipper subcommand in an isolated zsh subshell.
# Usage: run_ckipper <subcommand> [args...]
#
# ckipper.zsh is a zsh-only file (uses read "?..." prompt syntax, setopt, etc.)
# and CANNOT be sourced from bash. Tests must spawn a zsh subprocess for every
# ckipper invocation. This helper packages the required env-var forwarding and
# source incantation so individual @test blocks stay readable.
#
# CKIPPER_NO_GUM=1 is forwarded so prompt fallbacks read from stdin instead of
# trying to launch gum (which would block tests on hosts where gum is
# installed). Override per-test by setting CKIPPER_NO_GUM= before the call.
#
# After calling, $status / $output / $lines are set exactly as with bats `run`.
run_ckipper() {
    local zsh_cmd="source \"$REPO_ROOT/ckipper.zsh\"; ckipper $*"
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-linux}" \
        CKIPPER_FORCE="${CKIPPER_FORCE:-1}" \
        CKIPPER_NO_GUM="${CKIPPER_NO_GUM:-1}" \
        _CKIPPER_DESKTOP_SYSTEM_APP="${_CKIPPER_DESKTOP_SYSTEM_APP:-}" \
        _CKIPPER_TEST_CLAUDE_APP="${_CKIPPER_TEST_CLAUDE_APP:-}" \
        _CKIPPER_TEST_LSREGISTER="${_CKIPPER_TEST_LSREGISTER:-}" \
        PGREP_STUB_MATCH="${PGREP_STUB_MATCH:-0}" \
        zsh -c "$zsh_cmd"
}

# Source a Ckipper file with $REPO_ROOT as the lookup base.
# NOTE: Only usable when the test file itself runs under zsh (i.e., when
# running bats tests from zsh). Because bats runs under bash, zsh-only source
# files (ckipper.zsh) cannot be sourced this way. Use run_ckipper for those.
source_ckipper_file() {
    local rel_path="$1"
    source "$REPO_ROOT/$rel_path"
}

# Install a fake /Applications/Claude.app under the per-test $TMP_HOME and
# point the desktop module at it via the documented env override. Required
# before any `desktop add`/`login`/`launch` test because the real flows
# refuse when the system Claude.app is missing.
#
# Sets _CKIPPER_TEST_OSTYPE so the desktop dispatcher macOS-guard passes
# and _CKIPPER_DESKTOP_SYSTEM_APP / _CKIPPER_TEST_CLAUDE_APP to point at
# the fake bundle. Both vars are exported so child zsh subprocesses (the
# ones run_ckipper spawns) inherit them.
_install_fake_claude_app() {
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
    export _CKIPPER_DESKTOP_SYSTEM_APP="$TMP_HOME/FakeClaude.app"
    export _CKIPPER_TEST_CLAUDE_APP="$TMP_HOME/FakeClaude.app"
    mkdir -p "$_CKIPPER_DESKTOP_SYSTEM_APP/Contents/MacOS"
    mkdir -p "$_CKIPPER_DESKTOP_SYSTEM_APP/Contents/Resources"
}

# Assert a file exists.
assert_file_exists() {
    [[ -f "$1" ]] || { echo "Expected file: $1" >&2; return 1; }
}

# Assert a file's mode (octal).
assert_file_mode() {
    local path="$1" expected="$2" actual
    actual="$(stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null)"
    [[ "$actual" = "$expected" ]] || { echo "Expected mode $expected, got $actual on $path" >&2; return 1; }
}
