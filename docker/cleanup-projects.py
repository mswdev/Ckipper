#!/usr/bin/env python3
"""Remove or sync a worktree path entry from per-account .claude.json files."""
import json
import os
import sys


def all_account_dirs(registry):
    if not os.path.exists(registry):
        return []
    with open(registry) as f:
        d = json.load(f)
    return [a["config_dir"] for a in d.get("accounts", {}).values() if a.get("config_dir")]


def remove_worktree_from_all(registry, wt_path):
    seen = set()
    for cfg_dir in all_account_dirs(registry):
        cfg = os.path.join(cfg_dir, ".claude.json")
        cfg_real = os.path.realpath(cfg)
        if cfg_real in seen:
            continue
        seen.add(cfg_real)
        if not os.path.exists(cfg):
            continue
        with open(cfg) as f:
            d = json.load(f)
        if wt_path in d.get("projects", {}):
            del d["projects"][wt_path]
            with open(cfg, "w") as f:
                json.dump(d, f)
            print(f"Removed worktree entry from {cfg}")


def sync_worktree_settings(registry, account_name, main_path, wt_path):
    if not os.path.exists(registry):
        return
    with open(registry) as f:
        d = json.load(f)
    acc = d.get("accounts", {}).get(account_name)
    if not acc:
        return
    cfg = os.path.join(acc["config_dir"], ".claude.json")
    if not os.path.exists(cfg):
        return
    with open(cfg) as f:
        cd = json.load(f)
    main = cd.get("projects", {}).get(main_path, {})
    if not main:
        return
    keys = [
        "disabledMcpServers",
        "enabledMcpjsonServers",
        "disabledMcpjsonServers",
        "allowedTools",
        "hasTrustDialogAccepted",
        "hasClaudeMdExternalIncludesApproved",
        "hasClaudeMdExternalIncludesWarningShown",
        "hasCompletedProjectOnboarding",
    ]
    wt = cd.setdefault("projects", {}).setdefault(wt_path, {})
    for k in keys:
        if k in main:
            wt[k] = main[k]
    with open(cfg, "w") as f:
        json.dump(cd, f)
    print(f"Synced settings for {wt_path} in {cfg}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    registry = os.environ.get("CKIPPER_REGISTRY", os.path.expanduser("~/.ckipper/accounts.json"))
    if cmd == "remove":
        remove_worktree_from_all(registry, sys.argv[2])
    elif cmd == "sync":
        sync_worktree_settings(registry, sys.argv[2], sys.argv[3], sys.argv[4])
