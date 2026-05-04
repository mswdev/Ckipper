#!/usr/bin/env zsh
# Top-level entry for `ckipper setup`. Orchestrates prereqs → summary →
# customization → account add → image build → final summary.
#
# Depends on:
#   - lib/core/style.zsh    (`_core_style_header`)
#   - lib/core/prompt.zsh   (`_core_prompt_confirm`, `_core_prompt_input`,
#                             `_core_prompt_spin`)
#   - lib/setup/prereqs.zsh (`_ckipper_setup_prereqs`)
#   - lib/setup/prompts.zsh (`_ckipper_setup_prompts_*`)
#   - lib/setup/apply.zsh   (`_ckipper_setup_apply_global`,
#                             `_ckipper_setup_apply_account`)
#   - lib/account/account-management.zsh (`_ckipper_account_add`)
#   - lib/worktree/build-image.zsh       (`_ckipper_worktree_build_image`)

# Default account name suggested when the wizard offers to register one.
readonly _CKIPPER_SETUP_DEFAULT_ACCOUNT_NAME="personal"

# Run the setup wizard. Idempotent — every prompt defaults to the current
# value, so re-runs can flip a single setting without redoing the whole flow.
#
# Args: $1 — optional `--help`/`-h` flag; remaining args are reserved.
# Returns: 0 on success or `--help`; 1 if prereqs fail.
_ckipper_setup() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        _ckipper_setup_help
        return 0
    fi
    _core_style_header "Welcome to Ckipper"
    echo "This wizard will configure Ckipper to fit your workflow."
    echo ""
    _ckipper_setup_prereqs || return 1
    _ckipper_setup_prompts_summary
    if _core_prompt_confirm "Customize any settings?"; then
        _ckipper_setup_run_customize_loop
    else
        echo "Using current values."
    fi
    _ckipper_setup_offer_account
    _ckipper_setup_offer_image_build
    _core_style_header "Setup complete"
    echo "Run 'ckipper config list' to review settings."
    echo "Run 'ckipper run <project> <branch>' to start working."
}

# Print top-level setup help.
#
# Returns: 0 always.
_ckipper_setup_help() {
    _core_help_render "ckipper setup — interactive wizard to configure Ckipper" \
        "" \
        "Re-runnable: every prompt defaults to your current value, so you can flip" \
        "a single setting without redoing the whole flow." \
        "" \
        "The wizard:" \
        "  1. Verifies prereqs (gum, jq, docker) and offers to brew-install missing." \
        "  2. Shows your current global config and lets you customize any subset." \
        "  3. Offers to register a Claude account and configure its preferences." \
        "  4. Offers to build the ckipper-dev Docker image." \
        "" \
        "Usage:" \
        "  ckipper setup            Run the wizard." \
        "  ckipper setup --help     Show this help."
}

# Customize-loop: pick a subset of global keys, prompt fresh values for each,
# then commit the batch via `_ckipper_setup_apply_global`.
#
# Returns: 0 on success; 1 if any individual write fails validation.
_ckipper_setup_run_customize_loop() {
    local -a picked
    picked=( ${(f)"$(_ckipper_setup_prompts_pick_keys)"} )
    typeset -A updates
    local key
    for key in "${picked[@]}"; do
        [[ -z "$key" ]] && continue
        updates[$key]=$(_ckipper_setup_prompts_one_key "$key")
    done
    _ckipper_setup_apply_global updates
}

# Offer to add an account — phrased differently depending on whether any are
# already registered. A jq read failure (missing/malformed registry) falls
# through to the empty-registry branch.
#
# Returns: 0 always.
_ckipper_setup_offer_account() {
    local count
    count=$(jq -r '.accounts | length' "$CKIPPER_REGISTRY" 2>/dev/null || echo 0)
    if [[ "$count" -gt 0 ]]; then
        if _core_prompt_confirm "You have $count registered account(s). Add another?"; then
            _ckipper_setup_add_account
        fi
        return 0
    fi
    if _core_prompt_confirm "Register a Claude account now?"; then
        _ckipper_setup_add_account
    fi
}

# Walk through `ckipper account add`, then prompt for the three per-account
# preferences and persist them to the registry. If account add fails (user
# aborted, name taken, etc.) the preference prompts are skipped.
#
# `prefs` is declared `typeset -A` here and populated by
# `_ckipper_setup_collect_account_prefs` via zsh's dynamic scoping — the
# helper writes into the parent-frame array without an indirect-name
# parameter dance.
#
# Returns: 0 always (per-step failures are surfaced via the underlying calls).
_ckipper_setup_add_account() {
    local name
    name=$(_core_prompt_input "Account name" "$_CKIPPER_SETUP_DEFAULT_ACCOUNT_NAME")
    _ckipper_account_add "$name" || return 0
    typeset -A prefs
    _ckipper_setup_collect_account_prefs "$name"
    _ckipper_setup_apply_account "$name" prefs
    _ckipper_setup_offer_initial_sync "$name"
}

# After a successful 2nd-or-later account add, offer to sync from an existing
# account into the freshly-added one. Skips when no other accounts exist.
#
# Args: $1 — newly-added account name.
# Returns: 0 always (cancellation is silent).
_ckipper_setup_offer_initial_sync() {
    local new_account="$1"
    local count
    count=$(jq -r '.accounts | length' "$CKIPPER_REGISTRY" 2>/dev/null || echo 0)
    (( count < 2 )) && return 0
    if ! _core_prompt_confirm "Sync settings from an existing account into '$new_account'?"; then
        return 0
    fi
    local -a others
    others=( ${(f)"$(_ckipper_account_sync_list_accounts_except "$new_account")"} )
    (( ${#others} == 0 )) && return 0
    local source_name
    source_name=$(_core_prompt_choose "Sync from which account?" "${others[@]}")
    [[ -z "$source_name" ]] && return 0
    _ckipper_account_sync_dispatch "$source_name" "$new_account"
}

# Map a single y/N confirmation to a "true"/"false" entry in the parent-scope
# `prefs` associative array. Kept as a one-liner so the three preference
# prompts in `_collect_account_prefs` stay readable.
#
# Args: $1 — schema key (e.g. always_docker); $2 — prompt label.
# Returns: the underlying `_core_prompt_confirm` exit status.
_ckipper_setup_pref_confirm() {
    local key="$1" label="$2"
    if _core_prompt_confirm "$label"; then
        prefs[$key]=true
    else
        prefs[$key]=false
    fi
}

# Prompt for the three per-account preferences and write them into the
# parent-frame `prefs` associative array. Relies on zsh's dynamic scoping —
# `prefs` must be declared (via `typeset -A`) in the caller's frame.
#
# Args: $1 — account name (used in prompt labels).
# Returns: 0 always.
_ckipper_setup_collect_account_prefs() {
    local account="$1"
    _ckipper_setup_pref_confirm always_docker \
        "Default --docker on for '$account'?"
    _ckipper_setup_pref_confirm always_firewall \
        "Default --firewall on for '$account'?"
    _ckipper_setup_pref_confirm ssh_forward \
        "Forward host ~/.ssh into '$account' containers?"
}

# Offer to build/rebuild the ckipper-dev Docker image now. Wraps the build in
# a gum spinner when available; the underlying helper streams docker output
# directly when running without gum.
#
# Returns: 0 always.
_ckipper_setup_offer_image_build() {
    if _core_prompt_confirm "Build the Docker image now? (slow; ~5 min)"; then
        _core_prompt_spin "Building ckipper-dev image" _ckipper_worktree_build_image
    fi
}
