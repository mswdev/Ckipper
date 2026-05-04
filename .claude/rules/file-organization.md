# File Organization

## Directory Size Limits

These are **hard limits**, not guidelines:
- **MAXIMUM 10 source files per directory.** Count only source files — colocated test and story files do NOT count toward the cap. If a directory has 10 source files, the next file MUST go in a subdirectory. No exceptions.
- **Colocate test and story files with their source files.** `parser.py` and `parser_test.py` (and any colocated stories/fixtures) belong together in the same directory.

When a directory approaches the cap, group related files into subdirectories by **domain**, **feature**, or **concern** — not by file type. Colocated tests and stories move with their source files into the subdirectory.

## Directory Grouping

When a directory needs subdirectories, group by **domain or feature**, not by file type. Keep related code together — all claim files in one place, not scattered across `types/`, `validators/`, and `handlers/`.

**Exception:** Top-level `src/` directories MAY be organized by architectural layer (e.g., `api/`, `db/`, `event/`) when they represent distinct system boundaries. Within those layers, group by domain.

## Dependency Direction

Imports flow **downward and inward**, never upward or sideways across features.

- **Parent directories MUST NOT import from child route/feature directories.** Shared code lives at the nearest common ancestor.
- **Sibling feature directories MUST NOT import from each other.** If two features need the same code, extract it to their shared parent or a `_shared/` directory.
- **Shared modules are pulled up, never reached into.** If two features both need a utility, it belongs in their common parent — not in one reaching into the other.

## DO NOT MIMIC EXISTING BAD PATTERNS

- **NEVER add files to a directory that already exceeds the 10-file cap.** Flag it to the user and propose a restructuring.
- **When creating new files, follow these rules from scratch** — do not pattern-match against nearby directories that may be poorly organized.

## Code Review Checklist

Before approving any PR, verify:
- [ ] **Is every directory under the 10-file cap (source files only)?**
- [ ] **Are test and story files colocated with their source files?**
- [ ] **Are subdirectories grouped by domain/feature, not by file type?**
- [ ] **Do imports flow downward — no parent importing from child, no sibling cross-imports?**
