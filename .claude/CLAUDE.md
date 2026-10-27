# CLAUDE.md

See @README.md for project overview.

> **Product:** Ckipper — lightweight multi-account manager for Claude Code and Claude Desktop.
> **Repo:** Single-package zsh project. Top-level layout in §1.

## Quick Reference

**Core Rules:**
- @.claude/rules/code-style.md — Naming, complexity limits, documentation
- @.claude/rules/testing.md — Test structure, what to test, quality gates
- @.claude/rules/security.md — Security requirements
- @.claude/rules/file-organization.md — Directory structure, file caps, dependency direction

**Package Rules:** *(add package-specific rule files as needed)*
<!-- Example:
- @.claude/rules/backend/api.md — API layer rules
- @.claude/rules/frontend/webapp.md — Frontend rules
-->

## How to Use These Instructions

1. **Always follow** the core philosophy and code standards
2. **Consult package-specific rules** when working in individual packages
3. **Package rules extend, not override** shared standards (e.g., a backend package adds validation requirements but doesn't remove the 25-line method limit)

## 1. Project Overview

Ckipper is a zsh-based wrapper for the [Claude Code CLI](https://claude.ai/cli) that provides:

- **Multi-account isolation** — separate `~/.claude-<account>/` config dirs per registered account. Claude Code keeps each config dir's login under its own macOS Keychain entry.
- **Per-account launchers** — auto-generated `claude-<account>` (and bare `<account>`) shell functions that set `CLAUDE_CONFIG_DIR`, plus a guard that stops bare `claude` from logging into the unmanaged `~/.claude/`.
- **Sync** — `ckipper account sync` copies MCP servers, settings, skills, agents, commands, hooks and more between accounts, with backups and undo.
- **Claude Desktop instances** — generated `.app` wrappers that run the system Claude.app against isolated user-data dirs.
- **Doctor** — `ckipper doctor` checks the registry, each account, Keychain entries, shell setup and Desktop instances.

Worktrees and sandboxing are left to Claude Code itself (`claude --worktree`, auto mode).

**Top-level layout:**

```
ckipper.zsh                  # ckipper CLI entry (sourced from .zshrc)
lib/core/                    # shared primitives (registry, keychain, prompt, style, fuzzy)
lib/account/                 # ckipper account subcommands + doctor (feature dir)
lib/account/sync/            # ckipper account sync engine and strategies
lib/desktop/                 # ckipper desktop subcommands (feature dir)
tests/                       # bats test helpers and stubs
install.sh                   # one-shot installer (copies to ~/.ckipper/)
.claude/                     # rules + project Claude config
```

`lib/` feature dirs (per `.claude/rules/shell-conventions.md`) own subcommand functionality and MUST NOT call into each other; shared code lives in `lib/core/`.

## 2. Core Engineering Philosophy

1. **KISS** — Keep It Simple, Stupid. The simplest solution that works is the best solution.
2. **Clarity over cleverness** — No tricks, no golf, no "elegant" one-liners that require a comment to explain.
3. **Functional decomposition** — Break problems into small, named, single-purpose functions.
4. **Object-Oriented Design** — Model the domain with clear objects, well-defined boundaries, and explicit contracts.
5. **Test what matters** — Unit tests are not optional. If logic makes a decision, it gets a test. ALWAYS WRITE TESTS.
6. **SOLID Principles** — Follow SOLID programming principles.

## 3. Code Review Checklist

Before approving any PR, verify:
- [ ] **Can I understand every method without reading its callees?** If no, the names need work.
- [ ] **There are NO MAGIC NUMBERS**
- [ ] **Is every method <= 25 lines?** NO EXCEPTIONS.
- [ ] **Is nesting <= 2 levels deep?** Extract if not.
- [ ] **Does each module/class have a single, obvious responsibility?**
- [ ] **Are there tests for every decision point in the logic?**
- [ ] **Is there any cleverness that should be replaced with clarity?**
- [ ] **Would a new teammate understand this in 5 minutes?**
- [ ] **Do new entry points (CLI, scripts, API endpoints) validate input at trust boundaries?**
- [ ] **Do exported functions have clear documentation when behavior isn't obvious from name and signature?**
- [ ] **Do route handlers and service methods log their outcomes (success, not-found, error)?**
- [ ] **Do error paths surface to monitoring — never swallowed silently?**

## 4. Infrastructure & Services

CI runs `make lint` + `make test-unit` on `macos-latest` via `.github/workflows/ci.yml`.

## 5. Git Workflow

**Branch naming:** `feature/{ticket-or-slug}-{short-description}` (e.g., `feature/123-user-auth`)
**Commit messages:** Reference the ticket if applicable (e.g., `#123: Implement user auth flow`)
**Always use feature branches + PRs.** NEVER commit directly to `main` or `develop`.
**ALWAYS create PRs as drafts** (`gh pr create --draft`). The author decides when to mark "Ready for review."
**PR description:** Link to the ticket if applicable, describe what changed and why, list affected files.

## 6. AI-Specific Instructions

- **Read and ingest before you edit.** Always read relevant source files before proposing changes. NEVER speculate about code you haven't inspected.
- **These rules are authoritative over observed codebase patterns.** If existing code violates a rule in this document or `.claude/rules/`, that is technical debt — not a convention to follow. Never justify bad practices because you see them elsewhere in the repo. When in doubt, follow the rules, not the code.
- **Follow existing design patterns that comply with these rules.** Study the relevant package and match the established architecture, file placement, and naming. If a convention exists and does not violate these rules, use it. If you have a clear technical reason to deviate, explain the rationale.
- **Reuse existing utility functions**
- **Reuse existing UI components**
- **Verify schema and queries against source files.** Check your ORM schema for table/column structure before writing code that references them.
- **Check existing types before creating new ones** to avoid duplication. Create new types when genuinely needed for new features.
- **Flag security concerns proactively** (exposed secrets, SQL injection, missing auth, etc.).
- **Use parallel tool calls** for independent operations (e.g., reading multiple files, running lint and test simultaneously).
- **Package context awareness:** When working in a specific package, prioritize that package's rule file.
