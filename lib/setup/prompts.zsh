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
#   - lib/config/schema.zsh   (`_CKIPPER_SCHEMA_*` arrays)
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

# Pipe-separated row builder for the summary table. Resolves the effective
# value via _core_config_get and the source marker via _core_config_read_global
# (empty return ⇒ default; otherwise ⇒ user override).
#
# Args: $1 — schema key.
# Returns: 0 always; prints "<key>|<value>|<source>" to stdout.
_ckipper_setup_prompts_summary_row() {
    local key="$1"
    local value source raw
    value=$(_core_config_get "$key")
    raw=$(_core_config_read_global "$key")
    if [[ -z "$raw" ]]; then
        source="$_CKIPPER_SETUP_PROMPTS_SOURCE_DEFAULT"
    else
        source="$_CKIPPER_SETUP_PROMPTS_SOURCE_USER"
    fi
    printf '%s|%s|%s\n' "$key" "$value" "$source"
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

# Render the "detected configuration" summary table. Emits a styled header,
# followed by a SETTING | VALUE | SOURCE row per global-scoped key. Account
# keys are skipped because their effective value depends on which account the
# wizard is about to configure.
#
# Returns: 0 always.
_ckipper_setup_prompts_summary() {
    _core_style_header "$_CKIPPER_SETUP_PROMPTS_HEADER"
    local key
    {
        while IFS= read -r key; do
            _ckipper_setup_prompts_summary_row "$key"
        done < <(_ckipper_setup_prompts_global_keys)
    } | _core_style_table SETTING VALUE SOURCE
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
    local ans=""
    read -r "ans?Customize all? (y/N): "
    [[ "$ans" =~ ^[yY] ]] || return 0
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
        _ckipper_setup_prompts_global_keys \
            | gum choose --no-limit --header "Pick keys to customize"
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
