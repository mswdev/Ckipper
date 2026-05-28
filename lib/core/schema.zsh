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

# One-line description shown by `ckipper config list` and the wizard. For bool
# keys the description states what `true` does (the active behavior), so the
# user can read it and decide; `false` is just the inverse.
typeset -gA _CKIPPER_SCHEMA_DESCRIPTION=(
    [projects_dir]="Path. Base directory containing your git projects."
    [worktrees_dir]="Path. Where worktrees live. Empty = \$projects_dir/.worktrees."
    [ports]="Comma-separated int list. Container ports to forward to the host."
    [default_branch]="String. Fallback base branch when origin/HEAD is unset (e.g. main, develop)."
    [dep_install_cmd]="String. Command run after worktree creation. Empty = skip dep install."
    [notify_bell]="Bool. true = play a terminal bell on Stop / Notification hooks."
    [aliases_auto_source]="Bool. true = installer auto-adds the per-account aliases source line to ~/.zshrc."
    [always_docker]="Bool. true = run Claude in Docker by default for this account (override with --no-docker)."
    [always_firewall]="Bool. true = enable the egress firewall by default for this account (override with --no-firewall)."
    [ssh_forward]="Bool. true = mount host ~/.ssh into containers launched for this account."
)
