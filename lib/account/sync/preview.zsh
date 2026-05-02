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

# Print the divider line for the summary table.
#
# Returns: 0 always.
_core_account_sync_print_divider() {
    printf '%*s\n' "$_CKIPPER_SYNC_DIVIDER_WIDTH" '' | tr ' ' '─'
}

# Print the per-item line with badge + display + summary.
#
# Args: $1 — change status; $2 — display; $3 — summary.
# Returns: 0; suppresses unchanged rows.
_core_account_sync_render_row() {
    local cmp_status="$1" display="$2" summary="$3"
    case "$cmp_status" in
        new)       printf '    %s %-26s (%s)\n' "$_CKIPPER_SYNC_BADGE_NEW" "$display" "${summary:-new}" ;;
        overwrite) printf '    %s %-26s (%s)\n' "$_CKIPPER_SYNC_BADGE_OVERWRITE" "$display" "${summary:-overwrite}" ;;
        unchanged) ;;
    esac
}

# Render the summary table. Reads a change-set on stdin (TSV rows), groups
# by type, and prints the §6.1 layout to stdout. The 4th positional arg
# is a path to a precomputed summaries file (one "type\tid\tsummary" per
# line) — built by the engine before this is called so we don't re-call
# every strategy's summary function inside the renderer.
#
# Args: $1 — src name; $2 — dst name; $3 — backup_dir path; $4 — summaries file.
# Returns: 0 always.
_core_account_sync_render_summary() {
    local src_name="$1" dst_name="$2" backup_dir="$3" summaries="$4"
    echo ""
    echo "Sync $src_name → $dst_name"
    _core_account_sync_print_divider
    local current_type=""
    local type id display change_status
    while IFS=$'\t' read -r type id display change_status; do
        [[ -z "$type" ]] && continue
        if [[ "$type" != "$current_type" ]]; then
            echo "  ${_CKIPPER_SYNC_TYPE_LABEL[$type]:-$type}"
            current_type="$type"
        fi
        local summary=""
        if [[ -f "$summaries" ]]; then
            summary=$(awk -F'\t' -v t="$type" -v i="$id" '$1==t && $2==i {print $3; exit}' "$summaries")
        fi
        _core_account_sync_render_row "$change_status" "$display" "$summary"
    done
    _core_account_sync_print_divider
    echo "Backup → $backup_dir"
}

# Count totals from the change-set on stdin.
#
# Returns: 0; prints "<total> <new> <overwrite>" on a single line.
_core_account_sync_count_changes() {
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
_core_account_sync_drill_down_items() {
    awk -F'\t' '$4 == "overwrite" { print $1 "\t" $2 "\t" $3 }'
}

# Open the drill-down loop (gum-driven). User picks an item; we print its
# full diff via the strategy's <type>_diff function. Loops until the user
# picks "Back" or hits EOF.
#
# Args: $1 — src dir; $2 — dst dir; $3 — src name; $4 — dst name; $5 — items file.
# Returns: 0 always.
_core_account_sync_drill_down_loop() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4" items_file="$5"
    [[ ! -s "$items_file" ]] && { echo "No items to drill into."; return 0; }
    while true; do
        local choice
        choice=$(_core_account_sync_drill_down_pick "$items_file") || return 0
        [[ "$choice" == "Back" || -z "$choice" ]] && return 0
        _core_account_sync_drill_down_show "$choice" "$src_dir" "$dst_dir" "$src_name" "$dst_name"
        echo ""
        echo "(Press enter to return to picker)"
        local _ack; read -r _ack
    done
}

# Pick one drill-down item. Uses gum if available; otherwise prints
# numbered list.
#
# Args: $1 — items file (TSV).
# Returns: gum exit; prints "<display>" or "Back".
_core_account_sync_drill_down_pick() {
    local items_file="$1"
    local -a labels=("Back")
    local type id display
    while IFS=$'\t' read -r type id display; do
        labels+=("[$type] $display")
    done < "$items_file"
    _core_prompt_choose "View diff for which item?" "${labels[@]}"
}

# Render the diff for one selected item. Strips the leading "[type] " marker
# from the picker label and looks the row back up.
#
# Args: $1 — picker choice (e.g. "[mcp] github"); $2..$5 — src/dst dir/name.
# Returns: 0; prints the strategy's diff output.
_core_account_sync_drill_down_show() {
    local choice="$1" src_dir="$2" dst_dir="$3" src_name="$4" dst_name="$5"
    local type="${choice#\[}"; type="${type%%]*}"
    local display="${choice#*] }"
    local id="$display"
    local diff_fn; diff_fn=$(_core_account_sync_strategy_fn "$type" diff)
    local arg_a="$src_dir" arg_b="$dst_dir"
    [[ "$type" == "prefs" ]] && { arg_a="$src_name"; arg_b="$dst_name"; }
    "$diff_fn" "$arg_a" "$arg_b" "$id"
}
