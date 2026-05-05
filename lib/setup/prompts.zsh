#!/usr/bin/env zsh
# Wizard default-and-tweak flow for `ckipper setup`.
#
# Renders the user's current global configuration as a "detected" summary,
# then lets them pick a subset of keys to override and walks them through a
# fresh prompt for each chosen key. Account-scoped keys are intentionally
# omitted — they're prompted later, once the wizard knows which account
# `setup` is configuring.
#
# Depends on:
#   - lib/core/schema.zsh   (`_CKIPPER_SCHEMA_*` arrays)
#   - lib/core/config.zsh     (`_core_config_get`, `_core_config_read_global`)
#   - lib/core/style.zsh      (`_core_style_header`, `_core_style_divider`,
#                              `_core_style_table`)
#   - lib/core/prompt.zsh     (`_core_prompt_input`, `_core_prompt_confirm`)
#
# All three public entry points (`_summary`, `_pick_keys`, `_one_key`) write
# user-facing chrome to stderr and the machine-readable result to stdout, so
# callers can pipe the chosen keys / values without scraping prompt labels.

# Marker rendered in the SOURCE column when a global key has no override.
readonly _CKIPPER_SETUP_PROMPTS_SOURCE_DEFAULT="(default)"

# Marker rendered when a global key has been customized in ckipper-config.zsh.
readonly _CKIPPER_SETUP_PROMPTS_SOURCE_USER="(your config)"

# Sentinel CKIPPER_NO_GUM value that forces the pure-zsh fallback path.
readonly _CKIPPER_SETUP_PROMPTS_NO_GUM_SENTINEL="1"

# Header rendered above the summary table.
readonly _CKIPPER_SETUP_PROMPTS_HEADER="Detected configuration"

# Header for the multi-select picker. Mentions SPACE explicitly because the
# preceding y/N "customize?" prompt and the source-account picker are both
# single-select Enter — without the hint, users press Enter on the first
# row and silently advance with no overrides.
readonly _CKIPPER_SETUP_PROMPTS_PICKER_HEADER="Pick keys to customize (SPACE to mark, ENTER to confirm)"

# Width of the SETTING column in the card-style summary. 22 chars covers
# every key in the current schema (longest is `aliases_auto_source` at 19)
# with a 3-char gutter before the value.
readonly _CKIPPER_SETUP_PROMPTS_KEY_WIDTH=22

# Render one schema key as a two-line "card": `<key padded> <value> <source>`
# on line 1 and the dim-colored description indented on line 2. Account
# keys are filtered out by the caller, so we don't have to handle scope here.
#
# Args: $1 — schema key.
# Returns: 0 always; writes two lines (no trailing blank) to stdout.
_ckipper_setup_prompts_summary_card() {
    local key="$1"
    local value source raw description display_value
    value=$(_core_config_get "$key")
    raw=$(_core_config_read_global "$key")
    if [[ -z "$raw" ]]; then
        source="$_CKIPPER_SETUP_PROMPTS_SOURCE_DEFAULT"
    else
        source="$_CKIPPER_SETUP_PROMPTS_SOURCE_USER"
    fi
    # Empty values render as a discoverable placeholder rather than blank
    # space, which otherwise reads like "the field is broken."
    display_value="$value"
    [[ -z "$display_value" ]] && display_value="(empty)"
    description="${_CKIPPER_SCHEMA_DESCRIPTION[$key]}"
    printf '%-*s %s  %s\n' \
        "$_CKIPPER_SETUP_PROMPTS_KEY_WIDTH" "$key" "$display_value" "$source"
    [[ -n "$description" ]] && _core_style_color dim "  $description"
}

# Print every global-scoped key one per line in lexical order. Used by the
# summary, the customize-all fallback, and any future wizard step that needs
# the canonical list of user-facing keys.
#
# Returns: 0 always; prints sorted global keys to stdout.
_ckipper_setup_prompts_global_keys() {
    local key
    for key in "${(@kon)_CKIPPER_SCHEMA_TYPE}"; do
        [[ "${_CKIPPER_SCHEMA_SCOPE[$key]}" == "global" ]] && print -- "$key"
    done
}

# Render the "detected configuration" summary as a stack of cards: each
# global key gets a `<key> <value> <source>` line followed by a dim
# description, separated by blank lines. Replaces an earlier table-based
# rendering whose alternating wide-row + indented-description rhythm read
# as visually noisy and where long values overflowed the column padding.
# Account-scoped keys are intentionally skipped — their effective value
# depends on which account the wizard is about to configure.
#
# Returns: 0 always.
_ckipper_setup_prompts_summary() {
    _core_style_header "$_CKIPPER_SETUP_PROMPTS_HEADER"
    local key first=1
    while IFS= read -r key; do
        (( first )) || echo
        first=0
        _ckipper_setup_prompts_summary_card "$key"
    done < <(_ckipper_setup_prompts_global_keys)
    _core_style_divider
}

# Decide whether to use gum for the picker. Mirrors `_core_prompt_use_gum` but
# kept private to avoid leaking gum-detection details out of this module.
#
# Returns: 0 if gum should drive the picker; 1 for the pure-zsh fallback.
_ckipper_setup_prompts_use_gum() {
    [[ "$CKIPPER_NO_GUM" == "$_CKIPPER_SETUP_PROMPTS_NO_GUM_SENTINEL" ]] && return 1
    command -v gum >/dev/null 2>&1
}

# Pure-zsh fallback for `_pick_keys`: ask whether the user wants to customize
# everything; on "y", echo every global key. On any other answer, echo
# nothing. The y/n prompt label is written to stderr so stdout stays
# pipeable.
#
# Returns: 0 always.
_ckipper_setup_prompts_pick_keys_fallback() {
    _core_prompt_confirm "Customize all?" || return 0
    _ckipper_setup_prompts_global_keys
}

# Prompt the user to choose which global keys they want to override. With gum
# present, drives a multi-select via `gum choose --no-limit`; without it,
# falls back to a single y/N "customize everything" question.
#
# Returns: 0 on success (including a deliberate "no" answer). Stdout: chosen
#   keys, one per line, in schema order.
_ckipper_setup_prompts_pick_keys() {
    if _ckipper_setup_prompts_use_gum; then
        local key
        while IFS= read -r key; do
            printf '%s — %s\n' "$key" "${_CKIPPER_SCHEMA_DESCRIPTION[$key]}"
        done < <(_ckipper_setup_prompts_global_keys) \
            | gum choose --no-limit --header "$_CKIPPER_SETUP_PROMPTS_PICKER_HEADER" \
            | awk '{print $1}'
        return 0
    fi
    _ckipper_setup_prompts_pick_keys_fallback
}

# Prompt for a fresh value for a single global key. Bool-typed keys take a
# y/N confirmation that maps to "true" / "false"; every other type uses the
# free-form input prompt with the current value as the default. The schema
# description is printed to stderr first so the user has context before the
# prompt.
#
# Args: $1 — schema key (must be present in `_CKIPPER_SCHEMA_TYPE`).
# Returns: 0 always; prints the chosen value to stdout.
_ckipper_setup_prompts_one_key() {
    local key="$1"
    local current type description
    current=$(_core_config_get "$key")
    type="${_CKIPPER_SCHEMA_TYPE[$key]}"
    description="${_CKIPPER_SCHEMA_DESCRIPTION[$key]}"
    print -u2 -- "$description"
    if [[ "$type" == "bool" ]]; then
        if _core_prompt_confirm "Enable $key? (current: $current)"; then
            echo "true"
        else
            echo "false"
        fi
        return 0
    fi
    _core_prompt_input "$key" "$current"
}
