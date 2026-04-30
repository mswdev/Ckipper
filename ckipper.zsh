#!/usr/bin/env zsh
# Ckipper main dispatcher.
#
# Sources shared primitives from lib/core/, account-management subcommands
# from lib/account/, and worktree subcommands from lib/worktree/, then
# exposes the top-level `ckipper` command (with `ck` short alias).

# Ckipper (pronounced "skipper") — multi-account Claude Code manager
# Sourced from ~/.zshrc.

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
CKIPPER_REGISTRY_VERSION=1

CKIPPER_REPO_DIR="${0:A:h}"

# Core primitives
source "$CKIPPER_REPO_DIR/lib/core/utils.zsh"
source "$CKIPPER_REPO_DIR/lib/core/registry.zsh"
source "$CKIPPER_REPO_DIR/lib/core/keychain.zsh"
source "$CKIPPER_REPO_DIR/lib/core/fuzzy.zsh"

# Account-namespace modules
source "$CKIPPER_REPO_DIR/lib/account/account-management.zsh"
source "$CKIPPER_REPO_DIR/lib/account/aliases.zsh"
source "$CKIPPER_REPO_DIR/lib/account/plugin-repair.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync.zsh"
source "$CKIPPER_REPO_DIR/lib/account/doctor.zsh"
source "$CKIPPER_REPO_DIR/lib/account/dispatcher.zsh"

# Worktree-namespace modules
source "$CKIPPER_REPO_DIR/lib/worktree/dispatcher.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/args.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/run.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/build-image.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/normal-mode.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/docker-mode.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/ports.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/resolve-account.zsh"
source "$CKIPPER_REPO_DIR/lib/worktree/worktree.zsh"

# Top-level commands. Used both for routing and for fuzzy-suggest.
_CKIPPER_COMMANDS=(account worktree doctor help)

# Dispatch a top-level ckipper command.
#
# Args:
#   $1     — top-level command (account, worktree, doctor, help, -h, --help,
#             empty, or short alias acct/wt)
#   $2..$N — arguments forwarded to the namespace dispatcher
#
# Returns: 0 on success; 1 on unknown command.
#
# Errors (stderr):
#   "Unknown command: '<cmd>'. Did you mean: '<match>'? ..."
ckipper() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        acct) cmd="account" ;;
        wt)   cmd="worktree" ;;
    esac
    case "$cmd" in
        account)  _ckipper_account_dispatch "$@" ;;
        worktree) _ckipper_worktree_dispatch "$@" ;;
        doctor)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_help_text_doctor
                return 0
            fi
            _ckipper_doctor "$@"
            ;;
        ""|help|-h|--help) _ckipper_help ;;
        *) _ckipper_unknown "$cmd"; return 1 ;;
    esac
}

# Print the closest top-level command match (or a bare unknown-command line)
# and point the user at help. Always writes to stderr.
#
# Args: $1 — the unknown command the user typed.
# Returns: 0 always.
_ckipper_unknown() {
    local cmd="$1" suggestion
    suggestion=$(_core_fuzzy_suggest "$cmd" "${_CKIPPER_COMMANDS[@]}")
    if [[ -n "$suggestion" ]]; then
        echo "Unknown command: '$cmd'. Did you mean: '$suggestion'?" >&2
    else
        echo "Unknown command: '$cmd'." >&2
    fi
    echo "Run 'ckipper help' for available commands." >&2
}

# Print the top-level ckipper usage summary.
#
# Returns: 0 always.
_ckipper_help() {
    cat <<'EOF'
ckipper (pronounced "skipper") — multi-account Claude Code manager

Usage:
  ckipper account <subcommand>   Manage Claude accounts (alias: acct)
  ckipper worktree <subcommand>  Manage git worktrees (alias: wt)
  ckipper doctor                 Diagnostic check of accounts and tooling
  ckipper help                   Show this overview

Companion commands (sourced via aliases.zsh):
  claude-<name> [args...]        Auto-generated launcher per registered account
  <name> [args...]               Bare-name shortcut (skipped if it would shadow
                                 an existing command, builtin, alias, or word)

Run `ckipper <namespace> help` (e.g. `ckipper account help`) for the
subcommand list, and `ckipper <namespace> <subcommand> --help` for per-
subcommand details.

Short alias: `ck` is the same as `ckipper`.
EOF
}

# Print help text for the top-level `doctor` command.
#
# Returns: 0 always.
_ckipper_help_text_doctor() {
    cat <<'EOF'
ckipper doctor

Run a diagnostic checklist on registered accounts and ckipper tooling:
  - Registry validity (version, JSON shape)
  - Per-account: config dir presence, .claude.json/settings.json/hooks/
  - Keychain entries reachable on macOS
  - ~/.zshrc sources ckipper.zsh
  - Stub ~/.claude state is absent

Exits 0 if every check passes (or only INFOs/WARNs); exits 1 if any FAIL.
EOF
}

# Short alias: 'ck' for 'ckipper'.
ck() { ckipper "$@"; }
