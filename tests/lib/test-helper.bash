# Common test helpers loaded at the top of every *_test.bats file.
# Usage: load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

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
    export PATH="$REPO_ROOT/tests/lib/stubs:$PATH"
    mkdir -p "$CKIPPER_DIR"
}

teardown_isolated_env() {
    [[ -n "$TMP_HOME" && -d "$TMP_HOME" ]] && rm -rf "$TMP_HOME"
}

# Source a Ckipper file with $REPO_ROOT as the lookup base.
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
