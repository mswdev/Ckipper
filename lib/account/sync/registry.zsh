#!/usr/bin/env zsh
# Declarative registry of syncable types for `ckipper account sync`.
#
# This is the single source of truth for "what can be synced." Adding a new
# syncable type is: append to all three parallel arrays AND implement the
# strategy contract (see lib/account/sync/engine.zsh for the contract).
#
# Mirrors the parallel-array idiom used by lib/config/schema.zsh.

# Human-readable label, shown in pickers and the summary table.
typeset -gA _CKIPPER_SYNC_TYPE_LABEL=(
    [mcp]="MCP servers"
    [settings]="Claude settings"
    [claude-md]="CLAUDE.md (user memory)"
    [agents]="Sub-agents"
    [commands]="Custom slash commands"
    [output-styles]="Output styles"
    [skills]="Skills"
    [statusline]="Status line"
    [hooks]="User hooks"
    [prefs]="Account preferences"
)

# Implementation kind. Drives which strategy module each type's functions
# live in. Allowed values: "structured" (JSON-key merges), "files-flat"
# (flat .md files), "files-dir" (per-directory items), "special" (custom
# logic — statusline split-detection, hooks install-allowlist filter).
typeset -gA _CKIPPER_SYNC_TYPE_KIND=(
    [mcp]=structured  [settings]=structured  [prefs]=structured
    [claude-md]=files-flat  [agents]=files-flat
    [commands]=files-flat   [output-styles]=files-flat
    [skills]=files-dir
    [statusline]=special  [hooks]=special
)

# Space-separated list of bundles the type belongs to. Bundles are aliases
# users may pass to --include / --exclude (see _ckipper_account_sync_resolve_*).
typeset -gA _CKIPPER_SYNC_TYPE_BUNDLES=(
    [mcp]="all customizations claude-config"
    [settings]="all customizations claude-config"
    [claude-md]="all customizations"
    [agents]="all customizations"
    [commands]="all customizations"
    [output-styles]="all customizations"
    [skills]="all customizations"
    [statusline]="all customizations"
    [hooks]="all customizations claude-config"
    [prefs]="all preferences"
)

# Known bundle aliases. Asserted disjoint from type ids by registry_test.
typeset -gra _CKIPPER_SYNC_BUNDLE_ALIASES=(all customizations claude-config preferences)

# Return 0 if $1 is a known sync type id; 1 otherwise.
#
# Args: $1 — candidate type id.
# Returns: 0 if known; 1 otherwise.
_ckipper_account_sync_is_known_type() {
    (( ${+_CKIPPER_SYNC_TYPE_LABEL[$1]} ))
}

# Return 0 if $1 is a known bundle alias; 1 otherwise.
#
# Args: $1 — candidate bundle alias.
# Returns: 0 if known; 1 otherwise.
_ckipper_account_sync_is_known_bundle() {
    local b="$1" alias
    for alias in "${_CKIPPER_SYNC_BUNDLE_ALIASES[@]}"; do
        [[ "$alias" == "$b" ]] && return 0
    done
    return 1
}

# Expand a bundle alias to its constituent type ids (one per line).
# A non-bundle token is echoed back unchanged (so callers can resolve a
# mixed list uniformly).
#
# Args: $1 — bundle alias OR raw type id.
# Returns: 0 always; prints expanded list to stdout, one type id per line.
_ckipper_account_sync_resolve_bundle() {
    local token="$1" t
    if ! _ckipper_account_sync_is_known_bundle "$token"; then
        echo "$token"
        return 0
    fi
    for t in "${(@k)_CKIPPER_SYNC_TYPE_BUNDLES}"; do
        [[ " ${_CKIPPER_SYNC_TYPE_BUNDLES[$t]} " == *" $token "* ]] && echo "$t"
    done
}

# Resolve a comma-separated --include / --exclude pair into a deduplicated
# sorted list of type ids. `include` may mix bundle aliases and bare type
# ids; bundles are expanded first, then `exclude` (also mixed) is subtracted.
#
# Args: $1 — comma-separated include list; $2 — comma-separated exclude list.
# Returns: 0 always; prints the final type ids one per line, lexically sorted.
_ckipper_account_sync_resolve_includes() {
    local include="$1" exclude="$2"
    local -A keep
    local token expanded
    for token in ${(s:,:)include}; do
        [[ -z "$token" ]] && continue
        for expanded in $(_ckipper_account_sync_resolve_bundle "$token"); do
            keep[$expanded]=1
        done
    done
    for token in ${(s:,:)exclude}; do
        [[ -z "$token" ]] && continue
        for expanded in $(_ckipper_account_sync_resolve_bundle "$token"); do
            unset 'keep['"$expanded"']'
        done
    done
    print -l ${(ko)keep}
}
