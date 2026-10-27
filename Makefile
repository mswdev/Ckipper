.PHONY: bootstrap test test-unit test-integration lint lint-shell lint-zsh lint-fmt lint-merge-guards install help

help:
	@echo "make bootstrap        - install dev tools (bats, shellcheck, shfmt, gum)"
	@echo "make test             - run all tests (bats)"
	@echo "make test-unit        - bats, fast suites only"
	@echo "make test-integration - integration tests (BATS_INTEGRATION=1)"
	@echo "make lint             - run all linters"
	@echo "make install          - run ./install.sh"

bootstrap:
	brew install bats-core shellcheck shfmt gum

test: test-unit

test-unit:
	bats --recursive .

test-integration:
	BATS_INTEGRATION=1 bats --recursive .

lint: lint-shell lint-zsh lint-fmt lint-merge-guards

# shellcheck only on .sh files (bash). .zsh files use `zsh -n` for syntax check.
lint-shell:
	shellcheck install.sh

lint-zsh:
	zsh -n ckipper.zsh
	@find lib -name '*.zsh' | while read -r f; do zsh -n "$$f" || exit 1; done

lint-fmt:
	shfmt -d -i 4 -ci -s install.sh

# Enforce the dependency direction from .claude/rules/shell-conventions.md.
# Each guard MUST return zero matches; if one fires, fix the source rather
# than the guard.
lint-merge-guards:
	@! grep -rE '\b_ckipper_account_' lib/desktop/ lib/core/ 2>/dev/null || (echo "lint-merge-guards: account-namespace reference outside lib/account/ (sibling features and core must not import it)" >&2 && exit 1)
	@! grep -rE '\b_ckipper_desktop_' lib/account/ lib/core/ 2>/dev/null || (echo "lint-merge-guards: desktop-namespace reference outside lib/desktop/ (sibling features and core must not import it)" >&2 && exit 1)
	@! grep -rE '^_core_[a-z_]+\(\)' lib/account/ lib/desktop/ --include='*.zsh' 2>/dev/null || (echo "lint-merge-guards: _core_* function defined outside lib/core/ (see .claude/rules/shell-conventions.md — _core_* is reserved for lib/core/)" >&2 && exit 1)

install:
	./install.sh
