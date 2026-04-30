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
- `_ckipper_account_*` — `lib/account/` (account subcommands)
- `_ckipper_worktree_*` — `lib/worktree/` (worktree subcommands)
- `_ckipper_*` — top-level dispatcher in `ckipper.zsh` (and `_ckipper_doctor`, kept un-namespaced because it's exposed as a top-level command, even though its source lives in `lib/account/`)
- No prefix — public, callable from `.zshrc`: `ckipper`, `ck`

## Booleans

zsh has no native bool. Use string values `"true"`/`"false"` and test with `[[ "$x" = "true" ]]`. (Don't use `0`/`1` integers with `(( x ))`.)

## Module sourcing

Modules under `lib/` are sourced once by `ckipper.zsh` (the single entry script sourced from `~/.zshrc`). Modules MUST NOT source siblings. Cross-feature imports between `lib/account/` and `lib/worktree/` are forbidden — extract shared code to `lib/core/` (per `file-organization.md`'s shared-parent rule).

CI enforces the namespace separation with the four guards from `make lint-merge-guards`:

- `grep -rE '\b_w_[a-z]' lib/`   — must be empty (no leftover renames from the merge)
- `grep -rE '\bW_[A-Z]' lib/`    — must be empty (no leftover globals from the merge)
- `grep -rE '\b_ckipper_account_' lib/worktree/`   — must be empty (worktree mustn't reach into account)
- `grep -rE '\b_ckipper_worktree_' lib/account/`   — must be empty (account mustn't reach into worktree)
