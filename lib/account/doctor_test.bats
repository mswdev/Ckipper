#!/usr/bin/env bats
# Unit tests for lib/account/doctor.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/account/ modules).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run a zsh expression with the full ckipper environment sourced.
run_helper() {
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

# ── _ckipper_doctor_check ─────────────────────────────────────────────

@test "doctor_check PASS prints PASS label without incrementing counters" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check PASS "all good"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "fail=0" ]]
    [[ "$output" =~ "warn=0" ]]
}

@test "doctor_check WARN prints WARN label and increments warn counter" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check WARN "something fishy"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "warn=1" ]]
}

@test "doctor_check FAIL prints FAIL label and increments fail counter" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check FAIL "broken"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "FAIL" ]]
    [[ "$output" =~ "fail=1" ]]
}

# ── _ckipper_doctor_summary ───────────────────────────────────────────

@test "doctor_summary returns 0 when no FAILs or WARNs" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_summary'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "all checks passed" ]]
}

@test "doctor_summary returns 0 when only WARNs (no FAILs)" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=2
        _ckipper_doctor_summary'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
}

@test "doctor_summary returns 1 when there are FAILs" {
    run_helper '_CKIPPER_DOCTOR_FAIL=1; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_summary'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "FAIL" ]]
}

# ── _ckipper_doctor_accounts ──────────────────────────────────────────

@test "doctor_accounts emits a WARN when the registry has no accounts" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_accounts'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "no accounts" ]]
}

@test "doctor_accounts lists each registered account by name" {
    local acc_dir="$TMP_HOME/.claude-work"
    mkdir -p "$acc_dir"
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"'"$acc_dir"'","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_accounts'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

# ── _ckipper_doctor_tooling ───────────────────────────────────────────

@test "doctor_tooling emits PASS when ckipper dir exists" {
    # CKIPPER_DIR is already created by setup_isolated_env.
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_tooling'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "exists" ]]
}
