#!/usr/bin/env zsh
# Worktree list, remove, and create operations for `ckipper worktree`.

readonly _CKIPPER_WT_FIND_MAX_DEPTH=3

# Directory names pruned during the worktree-list scan. Branches can contain
# slashes (e.g. `feature/foo`), so we cannot bound the search by depth — but
# we CAN skip the heavy build/cache trees that inflate scan time without
# containing real worktrees. Empirically takes a 6 GB / 380k-file worktrees
# tree from ~700 ms to ~30 ms. Also prunes `.git` directories (the parent
# repo's, not the worktree's `.git` *file*) so we don't descend into git's
# internal storage. Add new entries as the worktrees tree grows.
readonly _CKIPPER_WT_PRUNE_DIRS=(
    .git node_modules .next .nuxt dist build target
    .venv venv __pycache__ vendor .turbo .cache
)

# Print all worktrees under $CKIPPER_WORKTREES_DIR, grouped by project.
#
# Reads CKIPPER_PROJECTS_DIR and CKIPPER_WORKTREES_DIR globals.
_ckipper_worktree_list_worktrees() {
    _core_style_header "All Worktrees"
    [[ ! -d "$CKIPPER_WORKTREES_DIR" ]] && return 0

    local previous_project_for_grouping=""
    # Hoist loop locals out of the body: re-declaring `local var` (no =value)
    # on a subsequent iteration causes zsh to print `var='prior_value'`,
    # leaking lines onto the worktree list.
    local wt_dir="" rel="" project="" after_first="" branch=""
    _ckipper_worktree_find_worktree_git_files \
        | sort \
        | while IFS= read -r git_metadata_file; do
            wt_dir="${git_metadata_file:h}"
            rel="${wt_dir#$CKIPPER_WORKTREES_DIR/}"
            project="${rel%%/*}"
            after_first="${rel#*/}"
            [[ "$after_first" == "$rel" ]] && continue

            IFS=$'\t' read -r project branch < <(_ckipper_worktree_get_project_and_branch "$project" "$after_first")

            if [[ "$project" != "$previous_project_for_grouping" ]]; then
                previous_project_for_grouping="$project"
                echo ""
                _core_style_color cyan "[$project]"
            fi
            echo "  • $branch"
        done
}

# Emit the `.git` files of every worktree under $CKIPPER_WORKTREES_DIR,
# pruning known-heavy directories (see _CKIPPER_WT_PRUNE_DIRS) so the scan
# does not descend into node_modules / dist / build / etc. Worktrees mark
# their root with a `.git` *file* (a gitdir reference), not a directory —
# we test for `-type f` to filter accordingly.
#
# Args: none.
# Returns: 0 always; prints absolute paths to `.git` files, one per line.
_ckipper_worktree_find_worktree_git_files() {
    local -a prune_args=()
    local d
    for d in "${_CKIPPER_WT_PRUNE_DIRS[@]}"; do
        (( ${#prune_args} > 0 )) && prune_args+=(-o)
        prune_args+=(-name "$d")
    done
    find "$CKIPPER_WORKTREES_DIR" \
        \( -type d \( "${prune_args[@]}" \) -prune \) \
        -o \( -type f -name .git -print \) 2>/dev/null
}

# Resolve project and branch from path components for nested-project worktrees.
#
# Args:
#   $1 — initial project name (first path component)
#   $2 — path after the first component
#
# Returns: 0 always. Prints "<project>\t<branch>" (tab-separated) to stdout.
#
# Caller usage:
#   IFS=$'\t' read -r project branch < <(_ckipper_worktree_get_project_and_branch "$proj" "$rest")
_ckipper_worktree_get_project_and_branch() {
    local initial_project="$1"
    local after_first="$2"

    local second="${after_first%%/*}"
    local rest="${after_first#*/}"

    if [[ -d "$CKIPPER_PROJECTS_DIR/$initial_project/$second/.git" ]]; then
        printf '%s\t%s' "$initial_project/$second" "$rest"
    else
        printf '%s\t%s' "$initial_project" "$after_first"
    fi
}

# Remove a worktree and delete its branch. Empty-args validation lives in the
# dispatcher (`_ckipper_worktree_route_rm`); this function expects non-empty
# `project` and `worktree`.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — worktree/branch name
#
# Reads CKIPPER_WT_FLAG_FORCE, CKIPPER_WORKTREES_DIR, CKIPPER_PROJECTS_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Invalid project path: ..." / "Invalid branch name: ..." — when args fail validation
#   "Worktree not found: <path>" — when the worktree directory does not exist
#   "Failed to remove worktree. Use --force if it has uncommitted changes." — on git error
_ckipper_worktree_remove_worktree() {
    local project="$1"
    local worktree="$2"

    _ckipper_worktree_validate_project_name "$project" || return 1
    _ckipper_worktree_validate_branch_name "$worktree" || return 1

    local wt_path="$CKIPPER_WORKTREES_DIR/$project/$worktree"
    if [[ ! -d "$wt_path" ]]; then
        echo "Worktree not found: $wt_path" >&2
        return 1
    fi

    local force_flag=""
    [[ "$CKIPPER_WT_FLAG_FORCE" = "true" ]] && force_flag="--force"

    (cd "$CKIPPER_PROJECTS_DIR/$project" && git worktree remove $force_flag -- "$wt_path" && git branch -D -- "$worktree" 2>/dev/null) || {
        echo "Failed to remove worktree. Use --force if it has uncommitted changes." >&2
        return 1
    }

    _ckipper_worktree_cleanup_project_registry "$wt_path"
}

# Remove a worktree path from the project registry if the cleanup script exists.
#
# Args:
#   $1 — absolute path to the worktree that was removed
#
# Returns: 0 always (failure is non-fatal).
_ckipper_worktree_cleanup_project_registry() {
    local wt_path="$1"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" remove "$wt_path" 2>/dev/null || true
    fi
}

# Create a worktree for the given project and branch (idempotent if it already exists).
# Sets CKIPPER_WT_PATH to the resolved worktree path.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch name
#
# Reads CKIPPER_PROJECTS_DIR, CKIPPER_WORKTREES_DIR, CKIPPER_WT_ACTIVE_ACCOUNT, CKIPPER_WT_ACTIVE_CONFIG_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Invalid project path: ..." / "Invalid branch name: ..." — when args fail validation
#   "Project not found: <path>" — when the project directory does not exist
#   "Error: <path> exists but is not a valid worktree." — when dir exists but lacks .git file
_ckipper_worktree_create_worktree() {
    local project="$1"
    local worktree="$2"

    _ckipper_worktree_validate_project_name "$project" || return 1
    _ckipper_worktree_validate_branch_name "$worktree" || return 1

    if [[ ! -d "$CKIPPER_PROJECTS_DIR/$project" ]]; then
        echo "Project not found: $CKIPPER_PROJECTS_DIR/$project" >&2
        return 1
    fi

    if [[ -d "$CKIPPER_WORKTREES_DIR/$project/$worktree" ]]; then
        _ckipper_worktree_validate_existing_worktree "$project" "$worktree" || return 1
        CKIPPER_WT_PATH="$CKIPPER_WORKTREES_DIR/$project/$worktree"
        return 0
    fi

    echo "Creating worktree: $worktree"
    mkdir -p "$CKIPPER_WORKTREES_DIR/$project"
    CKIPPER_WT_PATH="$CKIPPER_WORKTREES_DIR/$project/$worktree"

    _ckipper_worktree_fetch_and_create "$project" "$worktree" || return 1
    _ckipper_worktree_post_create_setup "$project" "$worktree" || return 1
}

# Validate that an existing directory at the worktree path is a real worktree.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 if valid; 1 if the directory exists but has no .git file.
# Errors (stderr):
#   "Error: <path> exists but is not a valid worktree." — when .git file is missing
_ckipper_worktree_validate_existing_worktree() {
    local project="$1"
    local worktree="$2"
    local wt_path="$CKIPPER_WORKTREES_DIR/$project/$worktree"

    if [[ ! -f "$wt_path/.git" ]]; then
        echo "Error: $wt_path exists but is not a valid worktree." >&2
        echo "Remove it manually or use a different branch name." >&2
        return 1
    fi
}

# Fetch from origin and create the git worktree.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 on success; 1 if fetch or worktree creation fails.
# Errors (stderr):
#   "Failed to fetch from origin. ..." — when git fetch fails
#   "Failed: branch '<name>' is currently checked out..." — when branch is already in use
#   "Failed to create worktree" — on other git worktree add failures
_ckipper_worktree_fetch_and_create() {
    local project="$1"
    local worktree="$2"

    _ckipper_worktree_fetch_origin "$project" "$worktree" || return 1
    _ckipper_worktree_add_worktree "$project" "$worktree"
}

# Resolve the base branch for new worktree creation.
#
# Resolution order:
#   1. `git symbolic-ref refs/remotes/origin/HEAD` — what `git remote set-head`
#      records; this is the cheap, definitive answer when origin/HEAD is set.
#   2. `git remote show origin` parse — slower, network-dependent fallback when
#      the symbolic ref isn't present locally.
#   3. $CKIPPER_DEFAULT_BRANCH — global config override (lib/core/schema.zsh
#      key `default_branch`), exported by ckipper-config.zsh on shell init.
#   4. Hardcoded "develop" — preserves pre-overhaul behaviour.
#
# Args: none — must be invoked from inside a git repo.
# Returns: 0; prints the branch name (no "origin/" prefix) to stdout.
_ckipper_worktree_resolve_base_branch() {
    local head
    head=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    if [[ -n "$head" ]]; then
        echo "${head#origin/}"
        return 0
    fi
    head=$(git remote show origin 2>/dev/null | awk '/HEAD branch:/ { print $3; exit }')
    if [[ -n "$head" && "$head" != "(unknown)" ]]; then
        echo "$head"
        return 0
    fi
    if [[ -n "${CKIPPER_DEFAULT_BRANCH:-}" ]]; then
        echo "$CKIPPER_DEFAULT_BRANCH"
        return 0
    fi
    echo "develop"
}

# Fetch origin/<base-branch> and optionally origin/<branch> for the project.
#
# The base branch is resolved via `_ckipper_worktree_resolve_base_branch` from
# inside the project directory, so each invocation reflects the project's
# current origin/HEAD without shared state between helpers.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch name to attempt fetching
#
# Returns: 0 on success; 1 if base-branch fetch fails.
# Errors (stderr):
#   "Failed to fetch from origin. Check your network connection..." — on fetch failure
_ckipper_worktree_fetch_origin() {
    local project="$1"
    local worktree="$2"
    local base
    base=$(cd "$CKIPPER_PROJECTS_DIR/$project" && _ckipper_worktree_resolve_base_branch)

    (cd "$CKIPPER_PROJECTS_DIR/$project" && git fetch origin -- "$base") || {
        echo "Failed to fetch from origin. Check your network connection and that '$base' exists on the remote." >&2
        return 1
    }
    (cd "$CKIPPER_PROJECTS_DIR/$project" && git fetch origin -- "$worktree" 2>/dev/null) || true
}

# Add the git worktree, choosing local, remote, or new branch as appropriate.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 on success; 1 if git worktree add fails.
# Errors (stderr):
#   "Failed: branch '<name>' is currently checked out..." — when branch is in use
#   "Failed to create worktree" — on other failures
_ckipper_worktree_add_worktree() {
    local project="$1"
    local worktree="$2"
    local base
    base=$(cd "$CKIPPER_PROJECTS_DIR/$project" && _ckipper_worktree_resolve_base_branch)

    (cd "$CKIPPER_PROJECTS_DIR/$project" && \
        if git show-ref --verify --quiet "refs/heads/$worktree"; then
            echo "Using existing local branch: $worktree"
            git worktree add "$CKIPPER_WT_PATH" -- "$worktree"
        elif git show-ref --verify --quiet "refs/remotes/origin/$worktree"; then
            echo "Tracking remote branch: origin/$worktree"
            git worktree add "$CKIPPER_WT_PATH" -b "$worktree" -- "origin/$worktree"
        else
            echo "Creating new branch from origin/$base"
            git worktree add "$CKIPPER_WT_PATH" -b "$worktree" -- "origin/$base"
        fi
    ) || _ckipper_worktree_handle_worktree_add_failure "$project" "$worktree"
}

# Handle failure from git worktree add, printing a contextual error.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 1 always.
# Errors (stderr):
#   "Failed: branch '<name>' is currently checked out..." — when branch is in use
#   "Failed to create worktree" — on other failures
_ckipper_worktree_handle_worktree_add_failure() {
    local project="$1"
    local worktree="$2"
    local current_branch base
    current_branch=$(cd "$CKIPPER_PROJECTS_DIR/$project" && git branch --show-current 2>/dev/null)
    base=$(cd "$CKIPPER_PROJECTS_DIR/$project" && _ckipper_worktree_resolve_base_branch)
    if [[ "$current_branch" == "$worktree" ]]; then
        echo "Failed: branch '$worktree' is currently checked out in the main repo." >&2
        echo "Switch the main repo to a different branch first:" >&2
        echo "  cd $CKIPPER_PROJECTS_DIR/$project && git checkout $base" >&2
    else
        echo "Failed to create worktree" >&2
    fi
    return 1
}

# Post-worktree-creation: install deps, copy .env files, sync Claude settings.
#
# The dependency-install step honours $CKIPPER_DEP_INSTALL_CMD (lib/config
# schema key `dep_install_cmd`): unset → `npm install`, non-empty → run that
# command via `eval`, empty string → skip dependency installation entirely.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name (unused but kept for symmetry with other helpers)
#
# Reads CKIPPER_WT_PATH, CKIPPER_WT_ACTIVE_ACCOUNT, CKIPPER_DEP_INSTALL_CMD
# globals.
# Returns: 0 always (individual steps may warn on failure but don't abort).
_ckipper_worktree_post_create_setup() {
    local project="$1"

    # Use `-` (not `:-`) so an explicitly empty CKIPPER_DEP_INSTALL_CMD opts
    # OUT of dependency installation, while an unset variable falls through to
    # the npm-install default (preserves pre-overhaul behaviour).
    local install_cmd="${CKIPPER_DEP_INSTALL_CMD-npm install}"
    if [[ -n "$install_cmd" ]]; then
        echo "Installing dependencies: $install_cmd"
        (cd "$CKIPPER_WT_PATH" && eval "$install_cmd") \
            || echo "Warning: '$install_cmd' failed. You may need to run it manually."
    fi

    local env_file rel_path dest_dir
    while IFS= read -r -d '' env_file; do
        rel_path="${env_file#$CKIPPER_PROJECTS_DIR/$project/}"
        dest_dir="$CKIPPER_WT_PATH/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$env_file" "$dest_dir/"
        echo "Copied $rel_path"
    done < <(find "$CKIPPER_PROJECTS_DIR/$project" -maxdepth "$_CKIPPER_WT_FIND_MAX_DEPTH" -name ".env*" -not -name "*.example" -not -path "*/node_modules/*" -not -path "*/.git/*" -print0)

    _ckipper_worktree_sync_project_registry "$project"
}

# Sync the new worktree into the project registry.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#
# Reads CKIPPER_WT_PATH, CKIPPER_WT_ACTIVE_ACCOUNT globals.
# Returns: 0 always (failure is non-fatal).
_ckipper_worktree_sync_project_registry() {
    local project="$1"
    local main_project_path="$CKIPPER_PROJECTS_DIR/$project"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" sync \
            "$CKIPPER_WT_ACTIVE_ACCOUNT" "$main_project_path" "$CKIPPER_WT_PATH" 2>/dev/null || true
    fi
}
