#!/usr/bin/env zsh
# Dispatcher for `ckipper account sync` and `ckipper account sync undo`.
#
# Owns argument parsing and high-level mode routing. Delegates to:
#   - lib/account/sync/engine.zsh    (build_change_set, apply_target)
#   - lib/account/sync/preview.zsh   (render_summary, drill_down_loop)
#   - lib/account/sync/interactive.zsh (pickers when args are missing)
#   - lib/account/sync/registry.zsh  (resolve_includes, type validation)
#   - lib/core/registry.zsh          (_core_account_dir)

typeset -g _SYNC_FROM=""
typeset -ga _SYNC_TARGETS=()
typeset -g _SYNC_INCLUDE=""
typeset -g _SYNC_EXCLUDE=""
typeset -g _SYNC_DRY_RUN="false"
typeset -g _SYNC_YES="false"
typeset -g _SYNC_FORCE="false"

# Per-target sync context. Populated once per target by run_one_target (and
# augmented by apply_target with backup_dir). Engine/preview/finalize helpers
# read from this map instead of taking 5–8 positional arguments, per the
# .claude/rules/code-style.md 3-parameter cap. Keys: src_dir, dst_dir,
# src_name, dst_name, backup_dir, changeset, summaries, items.
#
# Re-declaration without `=()` is a no-op so engine.zsh's matching
# declaration (sourced first in production) keeps any state set there;
# reset between sync invocations is handled by reset_args, not by the
# declaration line.
typeset -gA _SYNC_CTX

# Reset all module-level _SYNC_* holders. Called at the top of every
# parse_args invocation so re-running the dispatcher in the same shell
# doesn't see stale state from the previous call.
#
# Returns: 0 always.
_ckipper_account_sync_reset_args() {
    _SYNC_FROM=""; _SYNC_TARGETS=()
    _SYNC_INCLUDE=""; _SYNC_EXCLUDE=""
    _SYNC_DRY_RUN="false"; _SYNC_YES="false"; _SYNC_FORCE="false"
    _SYNC_CTX=()
}

# Append a positional arg to _SYNC_FROM (first time) or _SYNC_TARGETS (every
# subsequent positional). Extracted from parse_args so the case body stays
# at 2 levels of nesting per .claude/rules/code-style.md.
#
# Args: $1 — positional value.
# Returns: 0 always.
_ckipper_account_sync_accumulate_positional() {
    [[ -z "$_SYNC_FROM" ]] && { _SYNC_FROM="$1"; return 0; }
    _SYNC_TARGETS+=("$1")
}

# Parse `ckipper account sync` arguments into module-level _SYNC_* vars.
# Positional: <from> [<to>...]. Flags: --include/--exclude/--dry-run/--yes/--force.
#
# Args: $@ — raw argv after `ckipper account sync` is stripped.
# Returns: 0 on success; 1 on unknown flag; 2 if --help printed.
# Errors (stderr): "Unknown flag: <flag>" — when an unrecognized --foo appears.
_ckipper_account_sync_parse_args() {
    _ckipper_account_sync_reset_args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --include) _SYNC_INCLUDE="$2"; shift 2 ;;
            --exclude) _SYNC_EXCLUDE="$2"; shift 2 ;;
            --dry-run) _SYNC_DRY_RUN="true"; shift ;;
            --yes)     _SYNC_YES="true";     shift ;;
            --force)   _SYNC_FORCE="true";   shift ;;
            -h|--help) _ckipper_account_sync_help_text; return 2 ;;
            --*) echo "Unknown flag: $1" >&2; return 1 ;;
            *) _ckipper_account_sync_accumulate_positional "$1"; shift ;;
        esac
    done
    return 0
}

# Top-level dispatcher. Routes to undo if first arg is "undo"; otherwise
# falls through to the sync flow.
#
# Args: $@ — args after `ckipper account sync`.
# Returns: 0 on success; 1 on user-visible failure.
_ckipper_account_sync_dispatch() {
    if [[ "$1" == "undo" ]]; then
        shift
        _ckipper_account_sync_undo_dispatch "$@"
        return $?
    fi
    _ckipper_account_sync_parse_args "$@"
    local rc=$?
    (( rc == 2 )) && return 0
    (( rc != 0 )) && return $rc
    _ckipper_account_sync_run
}

# Resolve missing positionals via interactive pickers, then run the engine
# for each target.
#
# Returns: 0 on success across all targets; 1 if any target failed.
_ckipper_account_sync_run() {
    if [[ -z "$_SYNC_FROM" ]]; then
        _SYNC_FROM=$(_ckipper_account_sync_pick_source) || return 1
    fi
    if (( ${#_SYNC_TARGETS} == 0 )); then
        _SYNC_TARGETS=( ${(f)"$(_ckipper_account_sync_pick_targets "$_SYNC_FROM")"} )
        (( ${#_SYNC_TARGETS} == 0 )) && return 1
    fi
    _ckipper_account_sync_validate_accounts || return 1
    local -a types
    types=( ${(f)"$(_ckipper_account_sync_resolve_types)"} )
    (( ${#types} == 0 )) && { echo "No types selected." >&2; return 1; }
    _ckipper_account_sync_run_targets types
}

# Walk every target and apply the resolved type list.
#
# Args: $1 — name of array variable holding type ids.
# Returns: 0 if every target succeeded; 1 if any failed.
_ckipper_account_sync_run_targets() {
    local types_var="$1"
    local -a types_local; types_local=( "${(@P)types_var}" )
    local rc=0 target
    for target in "${_SYNC_TARGETS[@]}"; do
        _ckipper_account_sync_validate_pair "$_SYNC_FROM" "$target" || { rc=1; continue; }
        _ckipper_account_sync_run_one_target "$target" "${types_local[@]}" || rc=1
    done
    return $rc
}

# Validate that source + every target are registered accounts.
#
# Returns: 0 if all registered; 1 if any unknown (error printed by _core_account_dir).
_ckipper_account_sync_validate_accounts() {
    _core_account_dir "$_SYNC_FROM" >/dev/null || return 1
    local t
    for t in "${_SYNC_TARGETS[@]}"; do
        _core_account_dir "$t" >/dev/null || return 1
    done
}

# Resolve --include/--exclude into a final type list. Empty include with
# no flags drops to interactive type picker.
#
# Returns: 0; prints type ids one per line.
_ckipper_account_sync_resolve_types() {
    if [[ -z "$_SYNC_INCLUDE" && "$_SYNC_YES" != "true" && "$_SYNC_DRY_RUN" != "true" ]]; then
        _ckipper_account_sync_pick_types
        return 0
    fi
    [[ -z "$_SYNC_INCLUDE" ]] && _SYNC_INCLUDE="all"
    _ckipper_account_sync_resolve_includes "$_SYNC_INCLUDE" "$_SYNC_EXCLUDE"
}

# One-target slice: build change set, render preview, prompt, apply.
#
# Args: $1 — target name; $2..$N — types.
# Returns: 0 on success; 1 on failure.
_ckipper_account_sync_run_one_target() {
    local target="$1"; shift
    local src_dir dst_dir
    src_dir=$(_core_account_dir "$_SYNC_FROM")
    dst_dir=$(_core_account_dir "$target")
    # Dry-run is read-only; the running-Claude refusal exists to prevent
    # races with writes, so let preview-only invocations through.
    if [[ "$_SYNC_DRY_RUN" != "true" ]]; then
        _ckipper_account_sync_assert_dst_idle "$dst_dir" "$_SYNC_FORCE" || return 1
    fi
    local changeset summaries items
    changeset=$(mktemp); summaries=$(mktemp); items=$(mktemp)
    _SYNC_CTX=(
        src_dir "$src_dir" dst_dir "$dst_dir"
        src_name "$_SYNC_FROM" dst_name "$target"
        changeset "$changeset" summaries "$summaries" items "$items"
    )
    _ckipper_account_sync_build_change_set "$src_dir" "$dst_dir" \
        "$_SYNC_FROM" "$target" "$@" > "$changeset"
    _ckipper_account_sync_build_summaries "$src_dir" "$dst_dir" \
        "$_SYNC_FROM" "$target" < "$changeset" > "$summaries"
    _ckipper_account_sync_drill_down_items < "$changeset" > "$items"
    _ckipper_account_sync_show_preview "$target" "$dst_dir" "$changeset" "$summaries"
    local action="apply"
    if [[ "$_SYNC_DRY_RUN" != "true" && "$_SYNC_YES" != "true" ]]; then
        action=$(_ckipper_account_sync_preview_prompt)
    fi
    [[ "$_SYNC_DRY_RUN" == "true" ]] && action="dry-run"
    _ckipper_account_sync_finalize "$action"
}

# Render the §6.1 preview block — header, summary table, change count.
#
# Args: $1 — target; $2 — dst_dir; $3 — changeset file; $4 — summaries file.
# Returns: 0 always.
_ckipper_account_sync_show_preview() {
    local target="$1" dst_dir="$2" changeset="$3" summaries="$4"
    local backup_path
    backup_path=$(_ckipper_account_sync_backup_dir_path "$dst_dir" "$_SYNC_FROM")
    _ckipper_account_sync_render_summary "$_SYNC_FROM" "$target" \
        "$backup_path" "$summaries" < "$changeset"
    local counts; counts=$(_ckipper_account_sync_count_changes < "$changeset")
    local total new ow; read -r total new ow <<< "$counts"
    echo "$total changes ($new new, $ow overwrite)."
}

# Apply / View changes / Abort prompt, with View looping back through
# the drill-down picker until Apply or Abort.
#
# Reads _SYNC_CTX[dst_name] for the prompt label. Callers capture this
# function's stdout via $() to read the action token, so two precautions
# keep "$action" clean: (1) drill_down_loop is redirected to stderr — its
# diff output and "press enter" prompts are user-facing terminal output,
# not data; (2) `local choice` is declared once outside the loop, because
# re-declaring `local choice` inside the loop after the first iteration
# causes zsh to print the prior value as `choice='...'`, which would also
# leak into "$action".
#
# Returns: 0; prints "apply" | "abort".
_ckipper_account_sync_preview_prompt() {
    local target="${_SYNC_CTX[dst_name]}"
    local choice=""
    while true; do
        choice=$(_core_prompt_choose "Apply changes to $target?" "Apply" "View changes" "Abort")
        case "$choice" in
            Apply) echo "apply"; return 0 ;;
            Abort|"") echo "abort"; return 0 ;;
            "View changes") _ckipper_account_sync_drill_down_loop >&2 ;;
        esac
    done
}

# Run the chosen action, clean up tmpfiles, return the apply rc. Reads the
# tmpfile paths and apply args from _SYNC_CTX.
#
# Args: $1 — action.
# Returns: 0 unless action=apply and the apply failed.
_ckipper_account_sync_finalize() {
    local action="$1"
    local rc=0
    if [[ "$action" == "apply" ]]; then
        _ckipper_account_sync_apply_target \
            "${_SYNC_CTX[src_dir]}" "${_SYNC_CTX[dst_dir]}" \
            "${_SYNC_CTX[src_name]}" "${_SYNC_CTX[dst_name]}" \
            < "${_SYNC_CTX[changeset]}"
        rc=$?
    fi
    rm -f "${_SYNC_CTX[changeset]}" "${_SYNC_CTX[summaries]}" "${_SYNC_CTX[items]}"
    return $rc
}

# Help text for `ckipper account sync`.
#
# Returns: 0 always.
_ckipper_account_sync_help_text() {
    _core_help_render "ckipper account sync [<from>] [<to>...] [options]" \
        "" \
        "Sync state between registered Claude accounts. Empty positionals drop" \
        "into interactive pickers (gum-driven)." \
        "" \
        "Options:" \
        "  --include <types>    Comma-separated types or named bundle:" \
        "                         all | customizations | claude-config | preferences" \
        "                         Type tokens: mcp, settings, claude-md, agents," \
        "                         commands, output-styles, skills, statusline," \
        "                         hooks, prefs" \
        "  --exclude <types>    Subtract from --include." \
        "  --dry-run            Print summary, exit (no prompt, no writes)." \
        "  --yes                Skip the confirm prompt; apply directly." \
        "  --force              Bypass the running-Claude refusal." \
        "" \
        "Subcommand:" \
        "  ckipper account sync undo <account> [--pick | --list]" \
        "" \
        "Examples:" \
        "  ckipper account sync                       (full wizard)" \
        "  ckipper account sync personal work --include mcp" \
        "  ckipper account sync personal work --include all --yes" \
        "  ckipper account sync personal work client1 --include customizations"
}

# Undo subcommand dispatcher.
#
# Force is read from a LOCAL var, not the module-level _SYNC_FORCE. The
# previous design read _SYNC_FORCE directly, which leaked across
# invocations: a prior `sync ... --force` left _SYNC_FORCE="true" in the
# shell, and a subsequent `sync undo` (without --force) inherited it,
# silently bypassing the running-Claude refusal. parse_args resets
# _SYNC_FORCE on the sync path, but the undo path skips parse_args.
#
# Args: $1 — account name; flags: --pick | --list | --force.
# Returns: 0 on success; 1 on user-visible failure.
# Errors (stderr): "Usage: ckipper account sync undo <account>" — when the
#   account positional is missing; "Unknown flag: <flag>" — when an
#   unrecognized --foo is passed.
_ckipper_account_sync_undo_dispatch() {
    local account="$1"; shift 2>/dev/null
    [[ -z "$account" ]] && { echo "Usage: ckipper account sync undo <account>" >&2; return 1; }
    local dst_dir; dst_dir=$(_core_account_dir "$account") || return 1
    local mode="latest" force="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pick) mode="pick"; shift ;;
            --list) mode="list"; shift ;;
            --force) force="true"; shift ;;
            *) echo "Unknown flag: $1" >&2; return 1 ;;
        esac
    done
    _ckipper_account_sync_assert_dst_idle "$dst_dir" "$force" || return 1
    _ckipper_account_sync_undo_run "$account" "$dst_dir" "$mode"
}

# Run the chosen undo mode (latest / pick / list).
#
# Args: $1 — account name; $2 — dst_dir; $3 — mode (latest|pick|list).
# Returns: 0 on success; 1 on failure or no backups.
_ckipper_account_sync_undo_run() {
    local account="$1" dst_dir="$2" mode="$3"
    local -a backups
    backups=( ${(f)"$(_ckipper_account_sync_manifest_list_backups "$dst_dir")"} )
    if (( ${#backups} == 0 )); then
        echo "No backups for $account."
        return 1
    fi
    local target_backup="${backups[1]}"
    if [[ "$mode" == "list" ]]; then
        printf '%s\n' "${backups[@]}"
        return 0
    fi
    if [[ "$mode" == "pick" ]]; then
        target_backup=$(_core_prompt_choose "Pick a backup to restore" "${backups[@]}")
        [[ -z "$target_backup" ]] && return 1
    fi
    _ckipper_account_sync_undo_from_backup "$target_backup" "$dst_dir"
}
