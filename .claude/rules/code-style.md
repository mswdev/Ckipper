# Code Style

## Method Size & Complexity

These are **hard limits**, not guidelines:
- **MAXIMUM 25 lines per method/function** (excluding blank lines and closing braces).
- **MAXIMUM 2 levels of control flow nesting** per method. If you need a third level, extract a method.
- **MAXIMUM 3 parameters** per method. Beyond that, introduce a parameter object or rethink the design.

## YOU MUST USE EARLY RETURNS OVER DEEP NESTING

Guard clauses go at the top. The happy path reads straight down.

## Naming Conventions

Names should be **descriptive and unambiguous**. A reader should never have to look at a method body to understand what it does. Avoid abbreviations.

- **Functions/Methods**: language-idiomatic (snake_case in shell/Python, camelCase in JS/TS) — verbs (`getUserById`, `approve_request`, `calculateTotal`)
- **Types/Classes**: PascalCase — nouns (`InvoiceCalculator`, `ClaimValidator`)
- **Booleans**: prefix with `is`, `has`, `can`, `should` (`isEligible`, `has_access`)
- **Collections**: pluralize (`users`, `active_orders`, `pendingItems`)
- **Constants/env vars**: UPPER_SNAKE_CASE (`ALGORITHM`, `KEY_LENGTH`, `MAX_RETRY_COUNT`)
- **Files**: match the language's idiomatic convention (PascalCase for classes, kebab-case for shell scripts, snake_case for Python modules)

## General Rules

- **Use the language's strongest type discipline** — explicit over implicit. No escape hatches (`any`, untyped `unknown`, `eval`) without justification.
- **Prefer async-first APIs** in languages that support them (`async/await` over raw promises/callbacks).
- **One responsibility per file.**
- **NO MAGIC NUMBERS EVER** — ALWAYS EXTRACT TO A NAMED CONSTANT.

## Code Documentation & Comments

All code must include clear, human-readable documentation. Comments should be written so that a junior-level developer or higher can understand what is being done and why.

**Public APIs are documented.** In languages with doc tooling (TSDoc/JSDoc, Python docstrings, Rustdoc, etc.), document every exported function, method, class, and interface — IDEs surface these as tooltips and they enable automated API-doc generation.

**Required information** (using the language's doc syntax):
- Each parameter's purpose and constraints
- Return value and the conditions producing it
- Exceptions/errors the function may raise
- Usage example for non-trivial functions
- Cross-references to related code or docs
- Deprecation notice with a migration path

**Inline comments** should explain "why," not "what." Comment business logic, workarounds, edge cases, and non-obvious decisions — not obvious code.

## Linting

Linting is enforced via `make lint` (locally) and `.github/workflows/ci.yml` (CI). Required tools:

- **shellcheck** — all `.zsh` and `.sh` files. Configured via `.shellcheckrc` at repo root: `enable=all`, `disable=SC1090` (dynamic source paths are intentional in this project). Any other disables require a comment justifying the exception.
- **shfmt** — `shfmt -d -i 4 -ci -s` (4-space indent, indent case, simplify). Diffs MUST be empty in CI.
- **ruff** — Python files. Configured in `pyproject.toml`. Rules: `E`, `F`, `B`, `D` (docstring checks). Line length 100.

Run `make bootstrap` once to install all linters via Homebrew + pip.
