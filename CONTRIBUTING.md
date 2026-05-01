# Contributing to Ckipper

Thanks for considering a contribution!

## Quick start

```sh
make bootstrap   # installs bats-core, shellcheck, shfmt, ruff, pytest
make test        # run all tests
make lint        # run all linters
```

## Workflow

1. Branch off `develop`. Branch name: `feature/{ticket-or-slug}-{short-description}`.
2. Make changes. Tests required for any decision-heavy logic — see [`.claude/rules/testing.md`](.claude/rules/testing.md).
3. `make test && make lint` must pass before you request review.
4. Open a **draft** PR targeting `develop`. The author marks it "Ready for review" when they're happy.

## Code style

We follow the rules in [`.claude/rules/`](.claude/rules/) — please read them. Highlights:

- **25-line function cap** (excluding blank lines and `}`-only lines). HARD LIMIT.
- **2-level nesting cap.** Use early returns / guard clauses.
- **3-parameter cap.** Beyond that, introduce a context object or rethink the design.
- **No magic numbers.** Extract to `readonly UPPER_SNAKE_CASE` constants.
- **No abbreviations.** `idx` → `index`, `ans` → `user_choice`, `tmp` → `*_tmpfile`.
- **Doc-headers on every public function.** See [`.claude/rules/shell-conventions.md`](.claude/rules/shell-conventions.md).

## File organization

- `lib/core/` — shared primitives (registry, keychain, utils, fuzzy). Used by both account and worktree namespaces.
- `lib/account/` — `ckipper account` subcommands. Function prefix: `_ckipper_account_*`.
- `lib/worktree/` — `ckipper worktree` subcommands. Function prefix: `_ckipper_worktree_*`. **Must NOT call `_ckipper_account_*` functions** (sibling cross-import). CI enforces this via `make lint-merge-guards`.
- Tests are colocated with source: `foo.zsh` + `foo_test.bats`.

## Adding a new config key

1. Add the key to all four arrays in `lib/config/schema.zsh` — `_CKIPPER_SCHEMA_TYPE`, `_DEFAULT`, `_SCOPE`, `_DESCRIPTION`.
2. The key is now usable via `ck config get/set/unset/list` and appears in the wizard automatically.
3. If the key affects worktree-creation behavior, update `lib/worktree/worktree.zsh` to read it via `_core_config_get`.
4. Add a test in `lib/config/schema_test.bats` to cover the new declaration.

## Module structure

- `lib/core/`        — shared primitives (`style.zsh`, `help.zsh`, `prompt.zsh`, `config.zsh`, registry, keychain, utils, fuzzy)
- `lib/account/`     — account namespace (`_ckipper_account_*`)
- `lib/worktree/`    — worktree namespace (`_ckipper_worktree_*`)
- `lib/config/`      — config namespace (`_ckipper_config_*`)
- `lib/setup/`       — wizard (`_ckipper_setup_*`)
- `lib/run/`         — top-level `run` shortcut (`_ckipper_run_*`)
- `lib/launcher/`    — bare `ck` interactive menu (`_ckipper_launcher_*`)

CI guards in `make lint-merge-guards` enforce that each prefix only appears in its owning directory.

## Test-mode prompt fallback

`lib/core/prompt.zsh` honors `CKIPPER_NO_GUM=1` to fall back to pure-zsh `read` / numeric-pick. Tests set this env var so they don't depend on the gum binary or a TTY.

## Testing

- **Shell:** bats-core. Hand-written stubs under `tests/lib/stubs/`. No mocking libraries.
- **Python:** pytest.
- **Test what matters:** business logic, decision points, file I/O contracts. Skip trivial wrappers.

## Reporting bugs / feature requests

Open an issue on GitHub. For security vulnerabilities, see [`SECURITY.md`](SECURITY.md) — please do NOT open a public issue.
