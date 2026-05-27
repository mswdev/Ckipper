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
- `_ckipper_config_*` — `lib/config/` (config get/set/unset/list/edit)
- `_ckipper_setup_*` — `lib/setup/` (first-run wizard)
- `_ckipper_run_*` — `lib/run/` (top-level `ckipper run` shortcut)
- `_ckipper_launcher_*` — `lib/launcher/` (bare-`ck` interactive menu)
- `_ckipper_desktop_*` — `lib/desktop/` (Claude Desktop multi-instance management)
- `_ckipper_*` — top-level dispatcher in `ckipper.zsh` (and `_ckipper_doctor`, kept un-namespaced because it's exposed as a top-level command, even though its source lives in `lib/account/`)
- No prefix — public, callable from `.zshrc`: `ckipper`, `ck`

## Booleans

zsh has no native bool. Use string values `"true"`/`"false"` and test with `[[ "$x" = "true" ]]`. (Don't use `0`/`1` integers with `(( x ))`.)

## Module sourcing

Modules under `lib/` are sourced once by `ckipper.zsh` (the single entry script sourced from `~/.zshrc`). Modules MUST NOT source siblings.

The `lib/` tree has two layers:

1. **Feature dirs** — `lib/account/`, `lib/worktree/`, `lib/config/`, `lib/desktop/`. Each owns a coherent slice of subcommand functionality. Feature dirs MUST NOT call into each other (account cannot call worktree, worktree cannot call config, desktop cannot call any other feature, etc.). Shared code goes in `lib/core/` per `file-organization.md`.

2. **Orchestration dirs** — `lib/launcher/`, `lib/setup/`, `lib/run/`. Their entire purpose is to delegate to feature dirs (the bare-`ck` menu, the first-run wizard, the `ckipper run` top-level shortcut). Orchestration dirs MAY call public, namespaced entry points from feature dirs (e.g. `_ckipper_worktree_dispatch`, `_ckipper_account_add`, `_ckipper_worktree_run`). They MUST NOT reach into another orchestration dir's internals.

`lib/core/` is callable from any layer.

CI enforces the namespace separation via `make lint-merge-guards`. The grep-based guards catch any *reference* (definition or call) — feature siblings cannot reach into each other, and orchestration-only namespaces (`_ckipper_setup_*`, `_ckipper_run_*`, `_ckipper_launcher_*`) are pinned to their dirs:

- `grep -rE '\b_w_[a-z]' lib/`        — empty (no leftover renames from the merge)
- `grep -rE '\bW_[A-Z]' lib/`         — empty (no leftover globals from the merge)
- `grep -rE '\b_ckipper_account_' lib/worktree/ lib/config/ lib/desktop/`   — empty (sibling features can't call account)
- `grep -rE '\b_ckipper_worktree_' lib/account/ lib/config/ lib/desktop/`   — empty (sibling features can't call worktree)
- `grep -rE '\b_ckipper_config_' lib/account/ lib/worktree/ lib/setup/ lib/run/ lib/core/ lib/desktop/`   — empty (config namespace is pinned to lib/config/)
- `grep -rE '\b_ckipper_setup_' lib/account/ lib/worktree/ lib/config/ lib/run/ lib/core/ lib/desktop/`   — empty (setup namespace is pinned to lib/setup/)
- `grep -rE '\b_ckipper_run_' lib/account/ lib/worktree/ lib/setup/ lib/config/ lib/core/ lib/desktop/`   — empty (run namespace is pinned to lib/run/)
- `grep -rE '\b_ckipper_launcher_' lib/account/ lib/worktree/ lib/setup/ lib/config/ lib/run/ lib/core/ lib/desktop/`   — empty (launcher namespace is pinned to lib/launcher/)
- `grep -rE '\b_ckipper_desktop_' lib/account/ lib/worktree/ lib/config/ lib/core/`   — empty (sibling features + core can't call desktop; orchestration dirs may delegate)

Orchestration dirs (`lib/launcher/`, `lib/setup/`, `lib/run/`) are *omitted* from the account/worktree/config guards by design — that's the dispatcher exception. Adding them would block the only legal pattern of cross-imports.
