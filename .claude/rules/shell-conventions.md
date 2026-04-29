# Shell Conventions

This document specifies how the language-agnostic rules in `code-style.md`, `file-organization.md`, and `testing.md` apply to zsh code in this project.

## Function-line counting

The "25 lines per function" cap (`code-style.md`) counts:

- Lines inside the function body.
- Excluding blank lines and lines containing ONLY a closing `}`.
- Including comment lines (so verbose inline commentary still counts).

Example:

```zsh
my_function() {
    # 1 line
    local x=1                  # 2 lines
                               # blank line — does NOT count
    echo "$x"                  # 3 lines
}                              # closing brace — does NOT count
```

This function is 3 lines.

## Doc-header convention

Every public function (and every helper extracted from one) gets a doc-header comment block immediately above its definition:

```zsh
# <One-line summary in imperative mood, ending with a period.>
#
# Args:
#   $1 — <name and constraints>
#   $2 — <name and constraints>
#
# Returns:
#   0 on <success condition>; non-zero on <failure conditions>.
#
# Errors (stderr):
#   "<exact error message>" — <when this is printed>
my_function() {
```

For helpers with no args, omit the `Args:` block. The `Errors:` block is required only when the function writes to stderr.

## Naming

- **Public functions** (callable from outside the file or from .zshrc): no leading underscore. Examples: `ckipper`, `ck`, `w`.
- **Module-internal functions**: prefix indicates the module:
  - `_core_*` — `lib/core/`
  - `_ckipper_*` — `lib/ckipper/`
  - `_w_*` — `lib/w/`
- **Constants**: `readonly UPPER_SNAKE_CASE` at top of file. No magic numbers.
- **Variables**: snake_case, descriptive (no `tmp`/`idx`/`ans`).
- **Booleans**: prefix with `is_`, `has_`, `can_`, `should_`. Use string values `"true"`/`"false"` (zsh has no native bool); test with `[[ ... = true ]]`.

## Module sourcing

Modules under `lib/` are sourced once by an entry script (`ckipper.zsh` or `w-function.zsh`). Modules MUST NOT source siblings. Cross-feature imports (`lib/w/` → `lib/ckipper/` or vice versa) are FORBIDDEN. If two features need shared code, it goes in `lib/core/` (per `file-organization.md`'s "shared modules pulled to common parent" rule).

CI enforces this:

```sh
grep -r '_ckipper_' lib/w/ && exit 1 || exit 0
```

## Magic numbers

Per `code-style.md`, no magic numbers. Constants live at the top of the module file that uses them, declared `readonly`:

```zsh
readonly KEYCHAIN_TIMEOUT_SECONDS=10
readonly REGISTRY_FILE_PERMS=600
```

The literals `0`, `1`, and `-1` are exempt when used in idiomatic contexts (exit status, array indexing, error sentinels).
