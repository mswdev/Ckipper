# Contributing to Ckipper

Thanks for considering a contribution!

## Quick start

```sh
make bootstrap   # installs bats-core, shellcheck, shfmt, gum
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

- `lib/core/`    — shared primitives (`style.zsh`, `help.zsh`, `prompt.zsh`, registry, keychain, utils, fuzzy). Function prefix: `_core_*`.
- `lib/account/` — `ckipper account` subcommands, sync, and doctor. Function prefix: `_ckipper_account_*`.
- `lib/desktop/` — `ckipper desktop` subcommands. Function prefix: `_ckipper_desktop_*`. **Must NOT call `_ckipper_account_*` functions** (and vice versa — sibling cross-import).
- Tests are colocated with source: `foo.zsh` + `foo_test.bats`.

CI guards in `make lint-merge-guards` enforce that each prefix only appears in its owning directory.

## Test-mode prompt fallback

`lib/core/prompt.zsh` honors `CKIPPER_NO_GUM=1` to fall back to pure-zsh `read` / numeric-pick. Tests set this env var so they don't depend on the gum binary or a TTY.

## Testing

- **Shell:** bats-core. Hand-written stubs under `tests/lib/stubs/`. No mocking libraries.
- **Test what matters:** business logic, decision points, file I/O contracts. Skip trivial wrappers.

## Reporting bugs / feature requests

Open an issue on GitHub. For security vulnerabilities, see [`SECURITY.md`](SECURITY.md) — please do NOT open a public issue.
