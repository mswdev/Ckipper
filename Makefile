.PHONY: bootstrap test test-unit test-integration lint lint-shell lint-zsh lint-py lint-fmt install help

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

lint: lint-shell lint-zsh lint-fmt lint-py

# shellcheck only on .sh files (bash). .zsh files use `zsh -n` for syntax check.
lint-shell:
	shellcheck install.sh
	shellcheck hooks/*.sh
	shellcheck docker/entrypoint.sh docker/init-firewall.sh

lint-zsh:
	zsh -n ckipper.zsh
	zsh -n w-function.zsh
	@if [ -d lib ]; then \
		find lib -name '*.zsh' -not -name '*_test.bats' | while read -r f; do zsh -n "$$f" || exit 1; done; \
	fi

lint-fmt:
	shfmt -d -i 4 -ci -s install.sh hooks/*.sh docker/entrypoint.sh docker/init-firewall.sh

lint-py:
	ruff check docker/cleanup-projects.py
	@if [ -d lib ]; then find . -name '*.py' -not -name '*_test.py' -not -path './tests/*' -exec ruff check {} +; fi

install:
	./install.sh
