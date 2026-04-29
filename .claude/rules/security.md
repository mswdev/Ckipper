# Security

## No-Touch Zones

These files require **explicit approval** before any modification:

<!-- Customize per project. Examples: -->
<!-- - `src/crypto/Cryptographer.ts` — Encryption logic -->
<!-- - `src/billing/Calculator.ts` — Financial math -->
<!-- - `prisma/schema.prisma` — Database schema -->

- Any `.env*` files, deployment configs, or CI/CD workflows
- Database migration files
- Authentication/authorization configuration
- Cryptography or encryption modules
- Financial calculation modules
- Files handling user secrets or credentials

## Security Rules

- **NEVER hardcode secrets in source code**
- **NEVER run destructive operations without confirmation** (DROP, TRUNCATE, DELETE without WHERE, `rm -rf`, force-push)
- **Validate all input at trust boundaries** — NEVER TRUST UNTRUSTED INPUT (CLI args, env vars, files, network requests; use Joi/Zod/equivalent for HTTP)
- **Flag security concerns proactively** — exposed secrets, injection (SQL, shell, command), missing auth, XSS, CSRF, etc.
- **Use lossless types for sensitive data** — money in minor units (cents) as integers, never floats; times in epoch ms or ISO 8601
