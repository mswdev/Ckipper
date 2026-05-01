#!/usr/bin/env zsh
# Config-namespace dispatcher and help text.
#
# Routes `ckipper config <subcommand>` to the matching _ckipper_config_*
# handler, prints overview help, and suggests the closest subcommand on a
# typo via _core_unknown_command (which handles the fuzzy match + help line).

# Known config subcommands. Used both for routing and for fuzzy-suggest.
_CKIPPER_CONFIG_SUBCOMMANDS=(get set unset list edit help)

# Dispatch a `config` subcommand.
#
# Args:
#   $1     — subcommand name (get, set, unset, list, edit, help, -h, --help, or empty)
#   $2..$N — arguments forwarded to the subcommand handler
#
# Returns: handler exit status; 1 on unknown subcommand.
#
# Errors (stderr):
#   "Unknown command: '<cmd>'. Did you mean: '<match>'? ..." (via _core_unknown_command)
_ckipper_config_dispatch() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        get)              _ckipper_config_get "$@" ;;
        set)              _ckipper_config_set "$@" ;;
        unset)            _ckipper_config_unset "$@" ;;
        list)             _ckipper_config_list "$@" ;;
        edit)             _ckipper_config_edit "$@" ;;
        ""|help|-h|--help) _ckipper_config_help ;;
        *) _ckipper_config_unknown "$cmd"; return 1 ;;
    esac
}

# Print the unknown-subcommand line plus a help pointer. Always writes to stderr.
#
# Args: $1 — the unknown subcommand the user typed.
# Returns: 0 always.
_ckipper_config_unknown() {
    _core_unknown_command "$1" \
        "Run 'ckipper config help' for available commands." \
        "${_CKIPPER_CONFIG_SUBCOMMANDS[@]}"
}

# Print the config-namespace usage summary.
#
# Returns: 0 always.
_ckipper_config_help() {
    cat <<'EOF'
ckipper config — read and write Ckipper configuration

Usage:
  ckipper config get [--account <name>] <key>           Print the resolved value
  ckipper config set [--account <name>] <key> [value]   Set a key (prompts if value omitted)
  ckipper config unset [--account <name>] <key>         Remove an override (revert to default)
  ckipper config list [--account <name>] [--format=fmt] List every key (table | json | env)
  ckipper config edit [--account <name>]                Open the underlying file in $EDITOR

Scope:
  Global keys live in ~/.ckipper/docker/ckipper-config.zsh.
  Account-scoped keys live under accounts.<name>.preferences in the registry
  and require --account on set/unset.
EOF
}
