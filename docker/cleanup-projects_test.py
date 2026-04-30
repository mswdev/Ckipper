"""Tests for cleanup-projects.py."""

import json
import os
from pathlib import Path

import importlib.util

_HERE = Path(__file__).parent
_SPEC = importlib.util.spec_from_file_location(
    "cleanup_projects", _HERE / "cleanup-projects.py"
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)

all_account_dirs = _MOD.all_account_dirs
remove_worktree_from_all = _MOD.remove_worktree_from_all
sync_worktree_settings = _MOD.sync_worktree_settings
_load_settings = _MOD._load_settings
_merge_settings_keys = _MOD._merge_settings_keys


def test_all_account_dirs_returns_config_dirs(tmp_path):
    """Returns config_dir for every registered account."""
    registry = tmp_path / "accounts.json"
    registry.write_text(json.dumps({
        "version": 1, "default": None,
        "accounts": {
            "a": {"config_dir": "/tmp/a"},
            "b": {"config_dir": "/tmp/b"},
        },
    }))

    result = all_account_dirs(str(registry))

    assert sorted(result) == ["/tmp/a", "/tmp/b"]


def test_all_account_dirs_returns_empty_for_missing_registry(tmp_path):
    """Returns empty list when registry does not exist."""
    result = all_account_dirs(str(tmp_path / "nonexistent.json"))

    assert result == []


def test_load_settings_returns_empty_dict_when_missing(tmp_path):
    """Missing .claude.json returns empty dict (not exception)."""
    result = _load_settings(str(tmp_path / "nope.json"))

    assert result == {}


def test_merge_settings_keys_copies_specified_keys():
    """Merge copies only the listed keys from source into target."""
    target = {"a": 1}
    source = {"a": 2, "b": 3, "c": 4}

    _merge_settings_keys(target, source, ["b"])

    assert target == {"a": 1, "b": 3}
    assert "c" not in target


def test_remove_worktree_from_all_strips_project_key(tmp_path):
    """remove_worktree_from_all removes the worktree's entry from each account's .claude.json."""
    account_a = tmp_path / "account-a"
    account_a.mkdir()
    (account_a / ".claude.json").write_text(json.dumps({
        "projects": {"/wt/foo": {"setting": "value"}, "/wt/bar": {}}
    }))

    registry = tmp_path / "accounts.json"
    registry.write_text(json.dumps({
        "version": 1, "default": None,
        "accounts": {"a": {"config_dir": str(account_a)}},
    }))

    remove_worktree_from_all(str(registry), "/wt/foo")

    after = json.loads((account_a / ".claude.json").read_text())
    assert "/wt/foo" not in after.get("projects", {})
    assert "/wt/bar" in after.get("projects", {})


def test_sync_worktree_settings_with_dict_context(tmp_path):
    """sync_worktree_settings accepts a context dict (refactored from 4 positional args)."""
    main = tmp_path / "main"
    wt = tmp_path / "wt"
    main.mkdir()
    wt.mkdir()
    account = tmp_path / "account"
    account.mkdir()

    main_claude = main / ".claude.json"
    wt_claude = wt / ".claude.json"
    main_claude.write_text(json.dumps({"projects": {str(main): {"key": "from_main"}}}))

    registry = tmp_path / "accounts.json"
    registry.write_text(json.dumps({
        "version": 1, "default": None,
        "accounts": {"acct": {"config_dir": str(account)}},
    }))

    context = {
        "registry_path": str(registry),
        "account_name": "acct",
        "main_path": str(main),
        "worktree_path": str(wt),
    }

    # Should not raise
    sync_worktree_settings(context)
