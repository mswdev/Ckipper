#!/usr/bin/env zsh
# Preview UX for sync — summary table renderer + drill-down picker.
#
# The summary table groups change-set rows by type and prints a one-line
# entry per item with a status badge. The drill-down picker (interactive
# only, gum-driven) lets the user select an [~] item and see its full
# diff via the strategy's <type>_diff function.

readonly _CKIPPER_SYNC_BADGE_NEW="[+]"
readonly _CKIPPER_SYNC_BADGE_OVERWRITE="[~]"
readonly _CKIPPER_SYNC_DIVIDER_WIDTH=45

# Per-target context (declared here too because preview_test.bats sources
# only this module). See engine.zsh for the full key list. Re-declaration
# without `=()` is a no-op so we don't reset state set by earlier modules.
typeset -gA _SYNC_CTX

# Print the divider line for the summary table.
#
# Returns: 0 always.
_ckipper_account_sync_print_divider() {
    printf '%*s\n' "$_CKIPPER_SYNC_DIVIDER_WIDTH" '' | tr ' ' '─'
}

# Print the per-item line with badge + display + summary.
#
# Args: $1 — change status; $2 — display; $3 — summary.
# Returns: 0; suppresses unchanged rows.
_ckipper_account_sync_render_row() {
    local cmp_status="$1" display="$2" summary="$3"
    case "$cmp_status" in
        new)       printf '    %s %-26s (%s)\n' "$_CKIPPER_SYNC_BADGE_NEW" "$display" "${summary:-new}" ;;
        overwrite) printf '    %s %-26s (%s)\n' "$_CKIPPER_SYNC_BADGE_OVERWRITE" "$display" "${summary:-overwrite}" ;;
        unchanged) ;;
    esac
}

# Render the summary table. Reads a change-set on stdin (TSV rows), groups
# by type, and prints the preview layout to stdout. The 4th positional arg
# is a path to a precomputed summaries file (one "type\tid\tsummary" per
# line) — built by the engine before this is called so we don't re-call
# every strategy's summary function inside the renderer.
#
# Args: $1 — src name; $2 — dst name; $3 — backup_dir path; $4 — summaries file.
# Returns: 0 always.
_ckipper_account_sync_render_summary() {
    local src_name="$1" dst_name="$2" backup_dir="$3" summaries="$4"
    local -A summary_map
    if [[ -f "$summaries" ]]; then
        local s_type s_id s_text
        while IFS=$'\t' read -r s_type s_id s_text; do
            summary_map["${s_type}"$'\t'"${s_id}"]="$s_text"
        done < "$summaries"
    fi
    echo ""
    echo "Sync $src_name → $dst_name"
    _ckipper_account_sync_print_divider
    local current_type="" type id display change_status
    while IFS=$'\t' read -r type id display change_status; do
        [[ -z "$type" ]] && continue
        if [[ "$type" != "$current_type" ]]; then
            echo "  ${_CKIPPER_SYNC_TYPE_LABEL[$type]:-$type}"
            current_type="$type"
        fi
        _ckipper_account_sync_render_row "$change_status" "$display" "${summary_map["${type}"$'\t'"${id}"]}"
    done
    _ckipper_account_sync_print_divider
    echo "Backup → $backup_dir"
}

# Count totals from the change-set on stdin.
#
# Returns: 0; prints "<total> <new> <overwrite>" on a single line.
_ckipper_account_sync_count_changes() {
    awk -F'\t' '
        $4 == "new" { n++; total++ }
        $4 == "overwrite" { o++; total++ }
        END { printf "%d %d %d\n", total+0, n+0, o+0 }
    '
}

# Filter a change-set on stdin to only [~] (overwrite) rows. The drill-
# down picker only makes sense for overwrites (new items have no
# destination value to diff against).
#
# Returns: 0; prints "<type>\t<id>\t<display>" per line for overwrites.
_ckipper_account_sync_drill_down_items() {
    awk -F'\t' '$4 == "overwrite" { print $1 "\t" $2 "\t" $3 }'
}

# Open the drill-down loop (gum-driven). User picks an item; we print its
# full diff via the strategy's <type>_diff function. Loops until the user
# picks "Back" or hits EOF.
#
# Reads _SYNC_CTX[items] for the items-file path; drill_down_show reads
# the rest of the per-target dirs/names directly.
#
# Returns: 0 always.
_ckipper_account_sync_drill_down_loop() {
    local items_file="${_SYNC_CTX[items]}"
    [[ ! -s "$items_file" ]] && { echo "No overwrites to drill into."; return 0; }
    # Hoist `local choice` and `local _ack` out of the loop: re-declaring
    # `local var` (no =value) on a subsequent iteration causes zsh to
    # print `var='prior_value'`, which would surface as terminal noise.
    local choice="" _ack=""
    while true; do
        choice=$(_ckipper_account_sync_drill_down_pick "$items_file") || return 0
        [[ "$choice" == "Back" || -z "$choice" ]] && return 0
        _ckipper_account_sync_drill_down_show "$choice"
        echo ""
        echo "(Press enter to return to picker)"
        read -r _ack
    done
}

# Pick one drill-down item. Uses gum if available; otherwise prints
# numbered list. The label encodes the type so the show function can
# look up the id from the items file.
#
# Args: $1 — items file (TSV: type\tid\tdisplay).
# Returns: gum exit; prints chosen label or "Back".
_ckipper_account_sync_drill_down_pick() {
    local items_file="$1"
    local -a labels=("Back")
    local type id display
    while IFS=$'\t' read -r type id display; do
        labels+=("[$type] $display")
    done < "$items_file"
    _core_prompt_choose "View diff for which item?" "${labels[@]}"
}

# Render the diff for one selected item. Looks the row up by (type, display)
# in the items file to recover the original id (which may differ from
# display, e.g. files-flat: id=agents/foo.md, display=foo.md).
#
# Reads items file path and src/dst dirs/names from _SYNC_CTX.
#
# Args: $1 — picker choice (e.g. "[mcp] github").
# Returns: 0; prints the strategy's diff output.
_ckipper_account_sync_drill_down_show() {
    local choice="$1"
    local items_file="${_SYNC_CTX[items]}"
    local type="${choice#\[}"; type="${type%%]*}"
    local display="${choice#*] }"
    local id; id=$(_ckipper_account_sync_drill_down_resolve_id "$items_file" "$type" "$display")
    local diff_fn; diff_fn=$(_ckipper_account_sync_strategy_fn "$type" diff)
    local arg_a="${_SYNC_CTX[src_dir]}" arg_b="${_SYNC_CTX[dst_dir]}"
    (( ${+_CKIPPER_SYNC_TYPE_USES_NAMES[$type]} )) && { arg_a="${_SYNC_CTX[src_name]}"; arg_b="${_SYNC_CTX[dst_name]}"; }
    "$diff_fn" "$arg_a" "$arg_b" "$id"
}

# Recover the original id for a (type, display) pair by looking it up
# in the items file. Falls back to display when no row matches (defensive
# default — keeps drill-down working even if the items file is stale).
#
# Args: $1 — items file; $2 — type; $3 — display.
# Returns: 0; prints the id (or display on miss).
_ckipper_account_sync_drill_down_resolve_id() {
    local items_file="$1" type="$2" display="$3"
    local resolved
    resolved=$(awk -F'\t' -v t="$type" -v d="$display" \
        '$1 == t && $3 == d { print $2; exit }' "$items_file")
    echo "${resolved:-$display}"
}
