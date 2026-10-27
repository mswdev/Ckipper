# Security Policy

## Reporting a vulnerability

Please do **NOT** open a public GitHub issue for security vulnerabilities.

Instead, report privately via [GitHub Security Advisories](https://github.com/mswdev/Ckipper/security/advisories/new).

We aim to acknowledge reports within 72 hours and to provide a fix or mitigation timeline within 7 days.

## Scope

In scope:
- Credential handling (Keychain access, file permissions on the registry and generated files).
- Path traversal or shell injection in CLI tools.

Out of scope:
- Issues requiring physical access to the host.
- Claude Code's own permission and sandboxing behavior — report those to Anthropic.

## Supported versions

This is a single-version-stream project. The latest release on `main` is the only supported version.
