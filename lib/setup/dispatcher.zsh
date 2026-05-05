#!/usr/bin/env zsh
# Top-level entry for `ckipper setup`. Orchestrates prereqs → summary →
# customization → account add → image build → final summary.
#
# Depends on:
#   - lib/core/style.zsh    (`_core_style_header`)
#   - lib/core/prompt.zsh   (`_core_prompt_confirm`, `_core_prompt_input`)
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
    _ckipper_setup_offer_existing_sync
    _ckipper_setup_offer_aliases_source
    _ckipper_setup_offer_image_build
    _ckipper_setup_print_completion_summary "$_CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS"
    _ckipper_setup_wait_for_acknowledgement
}

# Offer a between-accounts sync when the user has 2+ accounts already and
# the wizard's add-account step did not just run one (the post-add path
# already offers the sync inline). Without this, a re-run of `ckipper setup`
# on an established multi-account install never surfaces the sync feature.
#
# Returns: 0 always.
_ckipper_setup_offer_existing_sync() {
    local count
    count=$(jq -r '.accounts | length' "$CKIPPER_REGISTRY" 2>/dev/null || echo 0)
    (( count < 2 )) && return 0
    if ! _core_prompt_confirm "Sync settings between two existing accounts?"; then
        return 0
    fi
    _ckipper_account_sync_dispatch
}

# Print the post-setup completion screen: bordered gum-styled card with a
# build-status line and two columns of commands (getting-started and
# maintenance). The whole thing is one `gum style` block so it visually
# belongs to the same wizard as the gum-rendered prompts above it. A
# build failure is easy to miss after 5 minutes of streaming docker
# output; the colored status line is the primary signal.
#
# Falls back to plain ANSI rendering when CKIPPER_NO_GUM is set.
#
# Args: $1 — image build status: `ok` | `failed` | `skipped`.
# Returns: 0 always.
_ckipper_setup_print_completion_summary() {
    local image_status="$1"
    if _ckipper_setup_completion_use_gum; then
        _ckipper_setup_render_completion_gum "$image_status"
    else
        _ckipper_setup_render_completion_plain "$image_status"
    fi
}

# Mirror of `_core_prompt_use_gum` — kept private so the completion path
# does not pull `_core_prompt_*` into its dependency surface.
#
# Returns: 0 if gum should drive rendering; 1 for the plain fallback.
_ckipper_setup_completion_use_gum() {
    [[ "$CKIPPER_NO_GUM" == "1" ]] && return 1
    command -v gum >/dev/null 2>&1
}

# Render the completion screen via `gum style`. Pre-builds the inner
# content as a multi-line string so the border wraps the whole block.
#
# Args: $1 — image status (`ok` | `failed` | `skipped`).
# Returns: 0 always.
_ckipper_setup_render_completion_gum() {
    local image_status="$1"
    local content
    content=$(_ckipper_setup_completion_inner "$image_status")
    gum style \
        --border rounded \
        --padding "1 2" \
        --border-foreground "$_CKIPPER_SETUP_PROMPTS_BORDER_FG" \
        "$content"
}

# Build the multi-line text content that goes inside the bordered card.
# The image-status line uses gum's foreground colors directly so the
# border block stays a single styled call. Sections are separated by
# blank lines for visual rhythm inside the card.
#
# Args: $1 — image status.
# Returns: 0 always; prints the multi-line content to stdout.
_ckipper_setup_completion_inner() {
    local image_status="$1"
    gum style --bold --foreground "$_CKIPPER_SETUP_PROMPTS_BORDER_FG" "Setup complete"
    echo
    _ckipper_setup_render_image_status_gum "$image_status"
    echo
    gum style --bold "Getting started:"
    echo "  ckipper run <project> <branch>     Bundle worktree + Claude"
    echo "  ck                                 Interactive menu"
    echo "  claude-<account>                   Per-account launcher (e.g. claude-personal)"
    echo
    gum style --bold "Maintenance:"
    echo "  ckipper config list                Review every setting"
    echo "  ckipper doctor                     Diagnose installation issues"
    echo "  ckipper worktree rebuild-image     Rebuild ckipper-dev Docker image"
    echo "  ckipper account sync               Copy settings between accounts"
}

# Plain-text completion screen for non-gum environments (CI, tests). Same
# information, no border or color.
#
# Args: $1 — image status.
# Returns: 0 always.
_ckipper_setup_render_completion_plain() {
    local image_status="$1"
    _core_style_header "Setup complete"
    _ckipper_setup_render_image_status "$image_status"
    echo "Getting started:"
    echo "  ckipper run <project> <branch>     Bundle worktree + Claude in one step"
    echo "  ck                                 Interactive menu"
    echo "  claude-<account>                   Per-account launcher (e.g. claude-personal)"
    echo ""
    echo "Maintenance:"
    echo "  ckipper config list                Review every setting"
    echo "  ckipper doctor                     Diagnose installation issues"
    echo "  ckipper worktree rebuild-image     Rebuild ckipper-dev Docker image"
    echo "  ckipper account sync               Copy settings between accounts"
    echo ""
}

# Render the docker-build-status line for the gum path using gum's
# foreground color codes (gum-color 46 = bright green, 196 = red, 244 =
# dim gray) so it nests cleanly inside the surrounding `gum style` block.
#
# Args: $1 — `ok` | `failed` | `skipped`.
# Returns: 0 always.
_ckipper_setup_render_image_status_gum() {
    case "$1" in
        ok)      gum style --foreground 46  "✓ Docker image: built successfully." ;;
        failed)  gum style --foreground 196 "✗ Docker image: build FAILED — re-run: ckipper worktree rebuild-image" ;;
        skipped) gum style --foreground 244 "○ Docker image: skipped — build later: ckipper worktree rebuild-image" ;;
    esac
}

# Plain-text image-status line (no gum). Uses the existing _core_style
# color palette so terminals that support ANSI still get a coloured
# banner; the no-color path falls through to plain text via
# _core_style_color's enablement check.
#
# Args: $1 — `ok` | `failed` | `skipped`.
# Returns: 0 always.
_ckipper_setup_render_image_status() {
    case "$1" in
        ok)      _core_style_color green "Docker image: built successfully." ;;
        failed)  _core_style_color red   "Docker image: build FAILED — re-run with: ckipper worktree rebuild-image" ;;
        skipped) _core_style_color dim   "Docker image: skipped — build later with: ckipper worktree rebuild-image" ;;
    esac
    echo ""
}

# Pause until the user presses Enter, so the "Setup complete" banner does
# not disappear off-screen behind the next shell prompt — particularly
# important when the docker build output preceded it. Skipped on
# non-interactive stdin (CI, piped installers).
#
# Returns: 0 always.
_ckipper_setup_wait_for_acknowledgement() {
    [[ -t 0 ]] || return 0
    local _ack=""
    read -r "_ack?Press ENTER to finish setup. "
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
        "  4. Offers to sync settings between two existing accounts (≥ 2 accounts)." \
        "  5. Offers to wire per-account launchers (claude-<account>) into ~/.zshrc." \
        "  6. Offers to build the ckipper-dev Docker image." \
        "  7. Prints a Setup Complete summary; press ENTER to finish." \
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
    local key value
    for key in "${picked[@]}"; do
        [[ -z "$key" ]] && continue
        # If the per-key prompt returns non-zero the user cancelled it
        # (Esc/Ctrl-C on gum). Skip the key rather than writing an empty
        # override, which would silently blank out the value.
        if ! value=$(_ckipper_setup_prompts_one_key "$key"); then
            continue
        fi
        updates[$key]="$value"
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
    if ! name=$(_core_prompt_input "Account name" "$_CKIPPER_SETUP_DEFAULT_ACCOUNT_NAME"); then
        return 0
    fi
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

# Offer to build/rebuild the ckipper-dev Docker image now. Records the
# outcome in _CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS so the completion
# summary can render a banner — without that signal, a failed build is
# easy to miss in the 5+ minutes of streaming docker output and the user
# would only discover it later when `--docker` runs hit "image not found."
#
# Sets _CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS to one of: ok, failed, skipped.
# Returns: 0 always (failures are surfaced via the status global, not rc,
#   so the wizard always finishes the post-build flow).
_ckipper_setup_offer_image_build() {
    typeset -g _CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS="skipped"
    if ! _core_prompt_confirm "Build the Docker image now? (slow; ~5 min)"; then
        return 0
    fi
    if _ckipper_worktree_build_image; then
        _CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS="ok"
    else
        _CKIPPER_SETUP_LAST_IMAGE_BUILD_STATUS="failed"
    fi
}

# Offer to add the per-account aliases source line to ~/.zshrc. The
# launchers (`claude-<account>`, bare `<account>`) only exist when the
# user's shell sources `~/.ckipper/aliases.zsh`. install.sh prints the
# suggestion but never appends it; setup-only re-runs (post-install)
# never see the suggestion at all. This step closes that loop, with an
# idempotency check so re-runs don't duplicate the line.
#
# Returns: 0 always.
_ckipper_setup_offer_aliases_source() {
    local zshrc="$HOME/.zshrc"
    [[ -f "$zshrc" ]] || return 0
    grep -q 'ckipper/aliases\.zsh' "$zshrc" 2>/dev/null && return 0
    if ! _core_prompt_confirm "Add per-account launchers (claude-<account>) to ~/.zshrc?"; then
        return 0
    fi
    {
        echo ""
        echo "# Ckipper — per-account launchers (claude-<account>, bare <account>)"
        echo '[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh'
    } >> "$zshrc"
    echo "Added the source line. Open a new shell (or run 'source ~/.zshrc')."
}
