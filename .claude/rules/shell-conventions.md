# Shell Conventions

zsh-specific clarifications of `code-style.md`, `file-organization.md`, and `testing.md`. This file only covers what those rules don't already specify; nothing is repeated.

## Function-line counting

The "25 lines per function" cap counts function-body lines, **excluding** blank lines and lines containing only a closing `}`. Comment lines count.

## Doc-header convention

zsh has no native docstrings. Document every public function with a comment block immediately above its definition with these labelled sections (in this order, each as needed):

```
# <one-line summary, imperative mood, ends with period>
#
# Args: $1 — …, $2 — …
# Returns: 0 on …; non-zero on …
# Errors (stderr): "<exact message>" — <when>
```

Omit `Args:` if the function takes none. Omit `Errors:` if it never writes to stderr.

## Function-name prefixes

Used to encode the dependency direction at a glance and let CI verify it:

- `_core_*` — `lib/core/` (shared primitives)
- `_ckipper_account_*` — `lib/account/` (account subcommands, including sync)
- `_ckipper_desktop_*` — `lib/desktop/` (Claude Desktop multi-instance management)
- `_ckipper_*` — top-level dispatcher in `ckipper.zsh` (and `_ckipper_doctor`, kept un-namespaced because it's exposed as a top-level command, even though its source lives in `lib/account/`)
- No prefix — public, callable from `.zshrc`: `ckipper`, `ck`

## Booleans

zsh has no native bool. Use string values `"true"`/`"false"` and test with `[[ "$x" = "true" ]]`. (Don't use `0`/`1` integers with `(( x ))`.)

## Module sourcing

Modules under `lib/` are sourced once by `ckipper.zsh` (the single entry script sourced from `~/.zshrc`). Modules MUST NOT source siblings.

The feature dirs — `lib/account/` and `lib/desktop/` — each own a coherent slice of subcommand functionality and MUST NOT call into each other. Shared code goes in `lib/core/` per `file-organization.md`. `lib/core/` is callable from any feature dir and calls into none of them. Only the top-level dispatcher in `ckipper.zsh` calls both features (e.g. `ckipper doctor` runs the account and Desktop doctors).

CI enforces the namespace separation via `make lint-merge-guards`:

- `grep -rE '\b_ckipper_account_' lib/desktop/ lib/core/`   — empty (desktop and core can't call account)
- `grep -rE '\b_ckipper_desktop_' lib/account/ lib/core/`   — empty (account and core can't call desktop)
- `grep -rE '^_core_[a-z_]+\(\)' lib/account/ lib/desktop/` — empty (`_core_*` is reserved for lib/core/)
