#!/usr/bin/env zsh
# Single source of truth for Ckipper's user-configurable settings.
#
# Consumed by:
#   - lib/config/   — user-facing get/set/unset/list
#   - lib/setup/    — wizard prompts
#   - lib/account/doctor.zsh — schema verification
#
# To add a new key: append to all four arrays below. The dispatcher and
# wizard pick it up automatically.

# Type of each key. Currently supported: "string", "bool", "int", "path", "int_array".
typeset -gA _CKIPPER_SCHEMA_TYPE=(
    [projects_dir]="path"
    [worktrees_dir]="path"
    [ports]="int_array"
    [default_branch]="string"
    [dep_install_cmd]="string"
    [notify_bell]="bool"
    [aliases_auto_source]="bool"
    [always_docker]="bool"
    [always_firewall]="bool"
    [ssh_forward]="bool"
)

# Default value (used when key is unset / on schema migration).
typeset -gA _CKIPPER_SCHEMA_DEFAULT=(
    [projects_dir]="$HOME/Developer"
    [worktrees_dir]=""
    [ports]="3000"
    [default_branch]=""
    [dep_install_cmd]="npm install"
    [notify_bell]="true"
    [aliases_auto_source]="true"
    [always_docker]="false"
    [always_firewall]="false"
    [ssh_forward]="true"
)

# Scope: "global" (lives in ~/.ckipper/docker/ckipper-config.zsh) or
# "account" (lives in ~/.ckipper/accounts.json under accounts.<n>.preferences).
typeset -gA _CKIPPER_SCHEMA_SCOPE=(
    [projects_dir]="global"
    [worktrees_dir]="global"
    [ports]="global"
    [default_branch]="global"
    [dep_install_cmd]="global"
    [notify_bell]="global"
    [aliases_auto_source]="global"
    [always_docker]="account"
    [always_firewall]="account"
    [ssh_forward]="account"
)

# One-line description shown by `ckipper config list` and the wizard.
typeset -gA _CKIPPER_SCHEMA_DESCRIPTION=(
    [projects_dir]="Base directory containing your git projects."
    [worktrees_dir]="Where worktrees are created (default: \$projects_dir/.worktrees)."
    [ports]="Comma-separated ports to forward from container to host."
    [default_branch]="Fallback base branch when origin/HEAD is unset."
    [dep_install_cmd]="Command run after worktree creation. Empty = skip."
    [notify_bell]="Install notify-bell hook into account dirs."
    [aliases_auto_source]="install.sh auto-adds aliases.zsh source line to .zshrc."
    [always_docker]="Default --docker on for this account."
    [always_firewall]="Default --firewall on for this account."
    [ssh_forward]="Forward host ~/.ssh into containers run with this account."
)
