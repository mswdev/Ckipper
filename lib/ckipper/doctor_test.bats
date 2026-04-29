#!/usr/bin/env bats
# Unit tests for lib/ckipper/doctor.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/ckipper/ modules).

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
