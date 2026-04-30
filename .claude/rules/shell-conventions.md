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
- `_ckipper_*` — `lib/account/` (account subcommands; will be renamed `_ckipper_account_*` in a follow-up phase)
- `_w_*` — `lib/w/` (w() helpers)
- No prefix — public, callable from `.zshrc`: `ckipper`, `ck`, `w`

## Booleans

zsh has no native bool. Use string values `"true"`/`"false"` and test with `[[ "$x" = "true" ]]`. (Don't use `0`/`1` integers with `(( x ))`.)

## Module sourcing

Modules under `lib/` are sourced once by an entry script (`ckipper.zsh` or `w-function.zsh`). Modules MUST NOT source siblings. Cross-feature imports between `lib/w/` and `lib/account/` are forbidden — extract shared code to `lib/core/` (per `file-organization.md`'s shared-parent rule).

CI enforces this with `grep -rE '\b_ckipper_' lib/w/`.
