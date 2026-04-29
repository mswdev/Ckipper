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

- `lib/core/` — shared primitives (registry, keychain, utils). Used by both ckipper and w.
- `lib/ckipper/` — ckipper-specific subcommands.
- `lib/w/` — w-specific helpers. **Must NOT call `_ckipper_*` functions** (sibling cross-import). CI enforces this.
- Tests are colocated with source: `foo.zsh` + `foo_test.bats`.

## Testing

- **Shell:** bats-core. Hand-written stubs under `tests/lib/stubs/`. No mocking libraries.
- **Python:** pytest.
- **Test what matters:** business logic, decision points, file I/O contracts. Skip trivial wrappers.

## Reporting bugs / feature requests

Open an issue on GitHub. For security vulnerabilities, see [`SECURITY.md`](SECURITY.md) — please do NOT open a public issue.
