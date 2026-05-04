#!/usr/bin/env python3
"""Cleanup helpers invoked from ckipper.zsh inside the container."""

import json
import os
import sys

CONFIG_DIR_KEY = "config_dir"
CLAUDE_JSON_FILENAME = ".claude.json"
PROJECTS_KEY = "projects"

SETTINGS_KEYS_TO_SYNC = [
    "disabledMcpServers",
    "enabledMcpjsonServers",
    "disabledMcpjsonServers",
    "allowedTools",
    "hasTrustDialogAccepted",
    "hasClaudeMdExternalIncludesApproved",
    "hasClaudeMdExternalIncludesWarningShown",
    "hasCompletedProjectOnboarding",
]


def all_account_dirs(registry_path: str) -> list:
    """List config_dir entries for every registered account.

    Args:
        registry_path: Absolute path to accounts.json.

    Returns:
        List of config_dir strings; empty if registry is missing.
    """
    if not os.path.exists(registry_path):
        return []
    with open(registry_path) as f:
        data = json.load(f)
    return [
        account[CONFIG_DIR_KEY]
        for account in data.get("accounts", {}).values()
        if account.get(CONFIG_DIR_KEY)
    ]


def _load_settings(claude_json_path: str) -> dict:
    """Load .claude.json. Returns empty dict if missing or unparseable."""
    if not os.path.exists(claude_json_path):
        return {}
    try:
        with open(claude_json_path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def _merge_settings_keys(target: dict, source: dict, keys: list) -> None:
    """Copy specified keys from source dict into target (in place).

    Args:
        target: Dict to copy keys into.
        source: Dict to copy keys from.
        keys: List of key names to copy.
    """
    for key in keys:
        if key in source:
            target[key] = source[key]


def _write_settings(claude_json_path: str, data: dict) -> None:
    """Write settings dict to .claude.json.

    Args:
        claude_json_path: Absolute path to .claude.json.
        data: Settings dict to write.
    """
    with open(claude_json_path, "w") as f:
        json.dump(data, f)


def remove_worktree_from_all(registry_path: str, worktree_path: str) -> None:
    """Strip the given worktree's project entry from every account's .claude.json.

    Args:
        registry_path: Path to accounts.json.
        worktree_path: Absolute worktree path to remove.
    """
    seen = set()
    for cfg_dir in all_account_dirs(registry_path):
        cfg = os.path.join(cfg_dir, CLAUDE_JSON_FILENAME)
        cfg_real = os.path.realpath(cfg)
        if cfg_real in seen:
            continue
        seen.add(cfg_real)
        data = _load_settings(cfg)
        if not data:
            continue
        if worktree_path in data.get(PROJECTS_KEY, {}):
            del data[PROJECTS_KEY][worktree_path]
            _write_settings(cfg, data)
            print(f"Removed worktree entry from {cfg}")


def _find_account_config(registry_path: str, account_name: str) -> str:
    """Return path to .claude.json for the given account, or empty string.

    Args:
        registry_path: Path to accounts.json.
        account_name: Name of the account to look up.

    Returns:
        Absolute path to .claude.json, or empty string if not found.
    """
    if not os.path.exists(registry_path):
        return ""
    with open(registry_path) as f:
        data = json.load(f)
    account = data.get("accounts", {}).get(account_name)
    if not account:
        return ""
    return os.path.join(account[CONFIG_DIR_KEY], CLAUDE_JSON_FILENAME)


def sync_worktree_settings(context: dict) -> None:
    """Sync settings between main repo and a worktree.

    Args:
        context: Dict with keys 'registry_path', 'account_name',
            'main_path', 'worktree_path'.

    Raises:
        KeyError: If context is missing required keys.
    """
    registry_path = context["registry_path"]
    account_name = context["account_name"]
    main_path = context["main_path"]
    worktree_path = context["worktree_path"]

    cfg = _find_account_config(registry_path, account_name)
    if not cfg:
        return

    settings = _load_settings(cfg)
    if not settings:
        return

    main_project = settings.get(PROJECTS_KEY, {}).get(main_path, {})
    if not main_project:
        return

    wt_project = settings.setdefault(PROJECTS_KEY, {}).setdefault(worktree_path, {})
    _merge_settings_keys(wt_project, main_project, SETTINGS_KEYS_TO_SYNC)
    _write_settings(cfg, settings)
    print(f"Synced settings for {worktree_path} in {cfg}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("Usage: cleanup-projects.py <command> <arg1> [arg2] [arg3]")

    cmd = sys.argv[1]
    registry = os.environ.get("CKIPPER_REGISTRY", os.path.expanduser("~/.ckipper/accounts.json"))

    if cmd == "remove":
        remove_worktree_from_all(registry, sys.argv[2])
    elif cmd == "sync":
        if len(sys.argv) < 5:
            sys.exit("Usage: cleanup-projects.py sync <account_name> <main_path> <worktree_path>")
        context = {
            "registry_path": registry,
            "account_name": sys.argv[2],
            "main_path": sys.argv[3],
            "worktree_path": sys.argv[4],
        }
        sync_worktree_settings(context)
    else:
        sys.exit(f"Unknown command: {cmd}")
