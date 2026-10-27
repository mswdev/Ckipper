#!/usr/bin/env zsh
# Ckipper (pronounced "skipper") — multi-account Claude Code and Claude
# Desktop manager. Sourced from ~/.zshrc.
#
# Sources shared primitives from lib/core/, account subcommands from
# lib/account/, and Desktop subcommands from lib/desktop/, then exposes the
# top-level `ckipper` command (with `ck` short alias).

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
CKIPPER_REGISTRY_VERSION=4
CKIPPER_DESKTOP_REGISTRY="$CKIPPER_DIR/desktop.json"
CKIPPER_DESKTOP_REGISTRY_VERSION=1

CKIPPER_REPO_DIR="${0:A:h}"

# Core primitives
source "$CKIPPER_REPO_DIR/lib/core/utils.zsh"
source "$CKIPPER_REPO_DIR/lib/core/registry.zsh"
source "$CKIPPER_REPO_DIR/lib/core/keychain.zsh"
source "$CKIPPER_REPO_DIR/lib/core/fuzzy.zsh"
source "$CKIPPER_REPO_DIR/lib/core/style.zsh"
source "$CKIPPER_REPO_DIR/lib/core/help.zsh"
source "$CKIPPER_REPO_DIR/lib/core/prompt.zsh"

# Account-namespace modules
source "$CKIPPER_REPO_DIR/lib/account/account-management.zsh"
source "$CKIPPER_REPO_DIR/lib/account/cleanup.zsh"
source "$CKIPPER_REPO_DIR/lib/account/aliases.zsh"
# Sync subsystem — registry, backup, shared helpers, engine, preview,
# interactive, dispatcher, then the strategy modules.
source "$CKIPPER_REPO_DIR/lib/account/sync/registry.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/backup.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/_shared.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/engine.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/preview.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/interactive.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/dispatcher.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/strategies/structured.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/strategies/files_flat.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/strategies/files_dir.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/strategies/statusline.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync/strategies/hooks.zsh"
source "$CKIPPER_REPO_DIR/lib/account/doctor.zsh"
source "$CKIPPER_REPO_DIR/lib/account/dispatcher.zsh"

# Desktop-namespace modules
source "$CKIPPER_REPO_DIR/lib/desktop/help.zsh"
source "$CKIPPER_REPO_DIR/lib/desktop/bundle.zsh"
source "$CKIPPER_REPO_DIR/lib/desktop/instance-management.zsh"
source "$CKIPPER_REPO_DIR/lib/desktop/launcher.zsh"
source "$CKIPPER_REPO_DIR/lib/desktop/doctor.zsh"
source "$CKIPPER_REPO_DIR/lib/desktop/dispatcher.zsh"

# Top-level commands. Used both for routing and for fuzzy-suggest.
_CKIPPER_COMMANDS=(account desktop doctor help)

# Commands that existed before Ckipper was slimmed down → a hint pointing at
# what replaces them. Used by _ckipper_unknown so muscle memory gets a precise
# answer instead of a generic "Unknown command".
typeset -gA _CKIPPER_REMOVED_COMMANDS=(
    [worktree]="Claude Code manages worktrees itself: claude-<account> --worktree <name>"
    [wt]="Claude Code manages worktrees itself: claude-<account> --worktree <name>"
    [run]="Claude Code manages worktrees itself: claude-<account> --worktree <name>"
    [config]="Ckipper has no settings of its own any more."
    [setup]="Register an account directly: ckipper account add <name>"
)

# Dispatch a top-level ckipper command. Runs every subcommand under zsh's
# default options (`emulate -L zsh`, restored on return), so settings in the
# caller's shell — e.g. NO_BARE_GLOB_QUAL in Claude Code's Bash tool, or
# KSH_ARRAYS — cannot change how Ckipper's globs and arrays behave.
#
# Args:
#   $1     — top-level command (account, desktop, doctor, help, -h, --help,
#             empty, or short alias acct/dt)
#   $2..$N — arguments forwarded to the namespace dispatcher
#
# Returns: 0 on success; 1 on unknown command.
#
# Errors (stderr):
#   "Unknown command: '<cmd>'. Did you mean: '<match>'? ..."
ckipper() {
    emulate -L zsh
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        acct) cmd="account" ;;
        dt)   cmd="desktop" ;;
    esac
    case "$cmd" in
        account) _ckipper_account_dispatch "$@" ;;
        desktop) _ckipper_desktop_dispatch "$@" ;;
        doctor)  _ckipper_doctor_all "$@" ;;
        ""|help|-h|--help) _ckipper_help ;;
        *) _ckipper_unknown "$cmd"; return 1 ;;
    esac
}

# Run the account doctor and the Desktop doctor, or print doctor help.
#
# Args: $1 — optional `--help`/`-h`.
# Returns: 0 if neither doctor reported a FAIL; 1 otherwise.
_ckipper_doctor_all() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        _ckipper_help_text_doctor
        return 0
    fi
    local rc=0
    _ckipper_doctor "$@" || rc=1
    _ckipper_desktop_doctor || rc=1
    return $rc
}

# Print a hint for a removed command, or fall through to the standard
# unknown-command + fuzzy-suggest path. Always writes to stderr.
#
# Args: $1 — the unknown command the user typed.
# Returns: 0 always.
_ckipper_unknown() {
    local cmd="$1"
    if (( ${+_CKIPPER_REMOVED_COMMANDS[$cmd]} )); then
        echo "'ckipper $cmd' was removed. ${_CKIPPER_REMOVED_COMMANDS[$cmd]}" >&2
        echo "Run 'ckipper help' for the current command list." >&2
        return 0
    fi
    _core_unknown_command "$cmd" \
        "Run 'ckipper help' for available commands." \
        "${_CKIPPER_COMMANDS[@]}"
}

# Print the top-level ckipper usage summary.
#
# Returns: 0 always.
_ckipper_help() {
    _core_help_render 'ckipper (pronounced "skipper") — multi-account Claude Code and Desktop manager' \
        "" \
        "Usage:" \
        "  ckipper account <subcommand>   Manage Claude Code accounts (alias: acct)" \
        "  ckipper desktop <subcommand>   Manage Claude Desktop instances (alias: dt)" \
        "  ckipper doctor                 Diagnostic check of accounts and tooling" \
        "  ckipper help                   Show this overview" \
        "" \
        "Companion commands (sourced via aliases.zsh):" \
        "  claude-<name> [args...]        Auto-generated launcher per registered account" \
        "  <name> [args...]               Bare-name shortcut (skipped if it would shadow" \
        "                                 an existing command, builtin, alias, or word)" \
        "" \
        "Run \`ckipper <namespace> help\` (e.g. \`ckipper account help\`) for the" \
        "subcommand list, and \`ckipper <namespace> <subcommand> --help\` for per-" \
        "subcommand details." \
        "" \
        "Short alias: \`ck\` is the same as \`ckipper\`."
}

# Print help text for the top-level `doctor` command.
#
# Returns: 0 always.
_ckipper_help_text_doctor() {
    _core_help_render "ckipper doctor [--fix]" \
        "" \
        "Run a diagnostic checklist on registered accounts and ckipper tooling:" \
        "  - Registry validity (version, JSON shape)" \
        "  - Per-account: config dir, .claude.json, settings.json, plugin paths" \
        "  - Keychain entries reachable on macOS" \
        "  - ~/.zshrc sources ckipper.zsh and aliases.zsh" \
        "  - Per-desktop-instance: data dir present, .app bundle valid (macOS only)" \
        "" \
        "--fix rewrites stale plugin metadata paths in place." \
        "" \
        "Exits 0 if every check passes (or only INFOs/WARNs); exits 1 if any FAIL."
}

# Short alias: 'ck' for 'ckipper'.
ck() { ckipper "$@"; }

# ── Tab completion ───────────────────────────────────────────────────
# Ensure completions directory is in fpath.
[[ -d ~/.zsh/completions ]] || mkdir -p ~/.zsh/completions
fpath=(~/.zsh/completions $fpath)

# Bump this when the heredoc body below changes so existing installs
# regenerate the cached completion file. The version is embedded as a literal
# comment in the generated file and matched here.
CKIPPER_COMPLETION_VERSION=10
if [[ ! -f ~/.zsh/completions/_ckipper ]] \
    || ! grep -q "# ckipper-completion-version=$CKIPPER_COMPLETION_VERSION" ~/.zsh/completions/_ckipper 2>/dev/null; then
    # Note: `_ckipper()` below is a zsh tab-completion definition embedded in
    # a heredoc. It uses zsh's _arguments DSL and must remain a single
    # function for tab completion to work. The 25-line cap in code-style.md
    # does not apply to zsh completion definitions (this is data written to
    # a completion file, not maintained shell logic).
    cat > ~/.zsh/completions/_ckipper << 'COMPEOF'
#compdef ckipper ck
# ckipper-completion-version=10

_ckipper() {
    local registry="${CKIPPER_REGISTRY:-$HOME/.ckipper/accounts.json}"
    local desktop_registry="${CKIPPER_DESKTOP_REGISTRY:-$HOME/.ckipper/desktop.json}"
    local -a top_commands account_subs desktop_subs accounts desktop_instances

    top_commands=(
        'account:Manage Claude Code accounts'
        'acct:Short alias for account'
        'desktop:Manage Claude Desktop instances'
        'dt:Short alias for desktop'
        'doctor:Diagnostic check of accounts and tooling'
        'help:Show top-level help'
    )
    account_subs=(
        'add:Register a new account'
        'list:Show registered accounts'
        'default:Set the default account'
        'remove:Unregister an account'
        'rename:Rename an account in place'
        'sync:Copy state between accounts (interactive or via --include)'
        'help:Show account-namespace help'
    )
    desktop_subs=(
        'add:Register a new Desktop instance'
        'list:Show registered instances'
        'remove:Unregister a Desktop instance'
        'rename:Rename a Desktop instance in place'
        'login:Quit all Claude.app, launch only this one'
        'launch:Open a registered instance'
        'help:Show desktop-namespace help'
    )
    [[ -f "$registry" ]] && accounts=( $(jq -r '.accounts | keys[]' "$registry" 2>/dev/null) )
    [[ -f "$desktop_registry" ]] && desktop_instances=( $(jq -r '.instances | keys[]' "$desktop_registry" 2>/dev/null) )

    _arguments -C \
        '1: :->cmd' \
        '2: :->sub' \
        '3: :->arg3' \
        '*:: :->args' \
        && return 0

    case $state in
        cmd)
            _describe -t commands 'ckipper command' top_commands && return 0
            ;;
        sub)
            case "${words[2]}" in
                account|acct) _describe -t subcommands 'account subcommand' account_subs && return 0 ;;
                desktop|dt)   _describe -t subcommands 'desktop subcommand' desktop_subs && return 0 ;;
            esac
            ;;
        arg3)
            case "${words[2]}/${words[3]}" in
                account/default|acct/default|account/remove|acct/remove|account/rename|acct/rename|account/sync|acct/sync)
                    _describe -t accounts 'account name' accounts && return 0
                    ;;
                desktop/remove|dt/remove|desktop/rename|dt/rename|desktop/login|dt/login|desktop/launch|dt/launch)
                    _describe -t instances 'desktop instance name' desktop_instances && return 0
                    ;;
            esac
            ;;
        args)
            case "${words[2]}/${words[3]}" in
                account/sync|acct/sync)
                    local -a sync_flags
                    sync_flags=(
                        '--include:Comma-separated types or named bundle (all/customizations/claude-config)'
                        '--exclude:Subtract from --include'
                        '--dry-run:Print summary; no writes'
                        '--yes:Skip the confirm prompt; apply directly'
                        '--force:Bypass the destination-Claude-running refusal'
                    )
                    _describe -t accounts 'sync target' accounts
                    _describe -t flags 'sync flag' sync_flags
                    ;;
            esac
            ;;
    esac
}

_ckipper "$@"
COMPEOF
fi
