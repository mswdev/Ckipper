# Security Policy

## Reporting a vulnerability

Please do **NOT** open a public GitHub issue for security vulnerabilities.

Instead, report privately via:
- GitHub Security Advisories: https://github.com/whmoro/claude-docker-sandbox/security/advisories/new
- Email: matt@msw.dev

We aim to acknowledge reports within 72 hours and to provide a fix or mitigation timeline within 7 days.

## Scope

In scope:
- Credential handling (Keychain access, container injection, file permissions).
- Hook bypass where the bypass affects security (note that `bash-guardrails.sh` is a UX guardrail by design, not a security boundary).
- Container escape vectors in the Docker sandbox.
- Path traversal or shell injection in CLI tools.

Out of scope:
- Bypasses of `bash-guardrails.sh` via `bash -c`/heredocs/eval — this is documented, intentional, and not a security boundary.
- Issues requiring physical access to the host.

## Supported versions

This is a single-version-stream project. The latest release on `main` is the only supported version.
