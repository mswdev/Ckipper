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
        zsh -c "$zsh_cmd"
}

# Run the w() function in an isolated zsh subshell.
# Usage: run_w [args...]
run_w() {
    local zsh_cmd="source \"$REPO_ROOT/w-function.zsh\"; w $*"
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-linux}" \
        CKIPPER_FORCE="${CKIPPER_FORCE:-1}" \
        zsh -c "$zsh_cmd"
}

# Source a Ckipper file with $REPO_ROOT as the lookup base.
# NOTE: Only usable when the test file itself runs under zsh (i.e., when
# running bats tests from zsh). Because bats runs under bash, zsh-only source
# files (ckipper.zsh, w-function.zsh) cannot be sourced this way.
# Use run_ckipper / run_w instead for those files.
source_ckipper_file() {
    local rel_path="$1"
    source "$REPO_ROOT/$rel_path"
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
