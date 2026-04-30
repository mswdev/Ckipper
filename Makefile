.PHONY: bootstrap test test-unit test-integration lint lint-shell lint-zsh lint-py lint-fmt lint-merge-guards install help

help:
	@echo "make bootstrap        - install dev tools (bats, shellcheck, shfmt, ruff, pytest)"
	@echo "make test             - run all tests (bats + pytest)"
	@echo "make test-unit        - bats + pytest, fast suites only"
	@echo "make test-integration - integration tests (BATS_INTEGRATION=1)"
	@echo "make lint             - run all linters"
	@echo "make install          - run ./install.sh"

bootstrap:
	brew install bats-core shellcheck shfmt
	pip install ruff pytest

test: test-unit

test-unit:
	bats --recursive .
	pytest

test-integration:
	BATS_INTEGRATION=1 bats --recursive .

lint: lint-shell lint-zsh lint-fmt lint-py lint-merge-guards

# shellcheck only on .sh files (bash). .zsh files use `zsh -n` for syntax check.
lint-shell:
	shellcheck install.sh
	shellcheck hooks/*.sh
	shellcheck docker/entrypoint.sh docker/init-firewall.sh

lint-zsh:
	zsh -n ckipper.zsh
	@if [ -d lib ]; then \
		find lib -name '*.zsh' -not -name '*_test.bats' | while read -r f; do zsh -n "$$f" || exit 1; done; \
	fi

lint-fmt:
	shfmt -d -i 4 -ci -s install.sh hooks/*.sh docker/entrypoint.sh docker/init-firewall.sh

lint-py:
	ruff check docker/cleanup-projects.py
	@if [ -d lib ]; then find . -name '*.py' -not -name '*_test.py' -not -path './tests/*' -exec ruff check {} +; fi

# Catch leftover references from the w → ckipper merge.
# Each guard MUST return zero matches; if any fires, fix the source rather than the guard.
# `doctor.zsh` is exempted from the W_* check: it intentionally references
# pre-merge variable names to detect stale user config left behind by the
# rename. Any other leftover W_* assignment is a bug.
lint-merge-guards:
	@! grep -rE '\b_w_[a-z]' lib/ ckipper.zsh 2>/dev/null || (echo "lint-merge-guards: leftover _w_* function references in lib/ or ckipper.zsh" >&2 && exit 1)
	@! grep -rE --exclude=doctor.zsh '\bW_[A-Z]' lib/ ckipper.zsh templates/ 2>/dev/null || (echo "lint-merge-guards: leftover W_* globals in lib/, ckipper.zsh, or templates/" >&2 && exit 1)
	@! grep -rE '\b_ckipper_account_' lib/worktree/ 2>/dev/null || (echo "lint-merge-guards: lib/worktree/ contains account-namespace functions" >&2 && exit 1)
	@! grep -rE '\b_ckipper_worktree_' lib/account/ 2>/dev/null || (echo "lint-merge-guards: lib/account/ contains worktree-namespace functions" >&2 && exit 1)

install:
	./install.sh
