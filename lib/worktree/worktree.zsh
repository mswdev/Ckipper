#!/usr/bin/env zsh
# Worktree list, remove, and create operations for `ckipper worktree`.

readonly CKIPPER_WT_FIND_MAX_DEPTH=3

# Print all worktrees under $CKIPPER_WORKTREES_DIR, grouped by project.
#
# Reads CKIPPER_PROJECTS_DIR and CKIPPER_WORKTREES_DIR globals.
_ckipper_worktree_list_worktrees() {
    echo "=== All Worktrees ==="
    [[ ! -d "$CKIPPER_WORKTREES_DIR" ]] && return 0

    local previous_project_for_grouping=""
    find "$CKIPPER_WORKTREES_DIR" -name ".git" -type f -not -path "*/node_modules/*" 2>/dev/null \
        | sort \
        | while IFS= read -r git_metadata_file; do
            local wt_dir="${git_metadata_file:h}"
            local rel="${wt_dir#$CKIPPER_WORKTREES_DIR/}"
            local project="${rel%%/*}"
            local after_first="${rel#*/}"
            [[ "$after_first" == "$rel" ]] && continue

            local branch
            IFS=$'\t' read -r project branch < <(_ckipper_worktree_get_project_and_branch "$project" "$after_first")

            if [[ "$project" != "$previous_project_for_grouping" ]]; then
                previous_project_for_grouping="$project"
                echo "\n[$project]"
            fi
            echo "  • $branch"
        done
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

# Remove a worktree and delete its branch.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — worktree/branch name
#
# Reads CKIPPER_WT_FLAG_FORCE, CKIPPER_WORKTREES_DIR, CKIPPER_PROJECTS_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Usage: ckipper worktree rm [--force] <project> <worktree>" — when project or worktree is empty
#   "Worktree not found: <path>" — when the worktree directory does not exist
#   "Failed to remove worktree. Use --force if it has uncommitted changes." — on git error
_ckipper_worktree_remove_worktree() {
    local project="$1"
    local worktree="$2"

    if [[ -z "$project" || -z "$worktree" ]]; then
        echo "Usage: ckipper worktree rm [--force] <project> <worktree>"
        return 1
    fi

    local wt_path="$CKIPPER_WORKTREES_DIR/$project/$worktree"
    if [[ ! -d "$wt_path" ]]; then
        echo "Worktree not found: $wt_path"
        return 1
    fi

    local force_flag=""
    [[ "$CKIPPER_WT_FLAG_FORCE" = true ]] && force_flag="--force"

    (cd "$CKIPPER_PROJECTS_DIR/$project" && git worktree remove $force_flag "$wt_path" && git branch -D "$worktree" 2>/dev/null) || {
        echo "Failed to remove worktree. Use --force if it has uncommitted changes."
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
# Sets CKIPPER_WT_WT_PATH to the resolved worktree path.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch name
#
# Reads CKIPPER_PROJECTS_DIR, CKIPPER_WORKTREES_DIR, CKIPPER_WT_ACTIVE_ACCOUNT, CKIPPER_WT_ACTIVE_CONFIG_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Project not found: <path>" — when the project directory does not exist
#   "Error: <path> exists but is not a valid worktree." — when dir exists but lacks .git file
_ckipper_worktree_create_worktree() {
    local project="$1"
    local worktree="$2"

    if [[ ! -d "$CKIPPER_PROJECTS_DIR/$project" ]]; then
        echo "Project not found: $CKIPPER_PROJECTS_DIR/$project"
        return 1
    fi

    if [[ -d "$CKIPPER_WORKTREES_DIR/$project/$worktree" ]]; then
        _ckipper_worktree_validate_existing_worktree "$project" "$worktree" || return 1
        CKIPPER_WT_WT_PATH="$CKIPPER_WORKTREES_DIR/$project/$worktree"
        return 0
    fi

    echo "Creating worktree: $worktree"
    mkdir -p "$CKIPPER_WORKTREES_DIR/$project"
    CKIPPER_WT_WT_PATH="$CKIPPER_WORKTREES_DIR/$project/$worktree"

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
        echo "Error: $wt_path exists but is not a valid worktree."
        echo "Remove it manually or use a different branch name."
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

# Fetch origin/develop and optionally origin/<branch> for the project.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch name to attempt fetching
#
# Returns: 0 on success; 1 if origin/develop fetch fails.
# Errors (stderr):
#   "Failed to fetch from origin. Check your network connection..." — on fetch failure
_ckipper_worktree_fetch_origin() {
    local project="$1"
    local worktree="$2"

    (cd "$CKIPPER_PROJECTS_DIR/$project" && git fetch origin develop) || {
        echo "Failed to fetch from origin. Check your network connection and that 'develop' exists on the remote."
        return 1
    }
    (cd "$CKIPPER_PROJECTS_DIR/$project" && git fetch origin "$worktree" 2>/dev/null) || true
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

    (cd "$CKIPPER_PROJECTS_DIR/$project" && \
        if git show-ref --verify --quiet "refs/heads/$worktree"; then
            echo "Using existing local branch: $worktree"
            git worktree add "$CKIPPER_WT_WT_PATH" "$worktree"
        elif git show-ref --verify --quiet "refs/remotes/origin/$worktree"; then
            echo "Tracking remote branch: origin/$worktree"
            git worktree add "$CKIPPER_WT_WT_PATH" -b "$worktree" "origin/$worktree"
        else
            echo "Creating new branch from origin/develop"
            git worktree add "$CKIPPER_WT_WT_PATH" -b "$worktree" origin/develop
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
    local current_branch
    current_branch=$(cd "$CKIPPER_PROJECTS_DIR/$project" && git branch --show-current 2>/dev/null)
    if [[ "$current_branch" == "$worktree" ]]; then
        echo "Failed: branch '$worktree' is currently checked out in the main repo."
        echo "Switch the main repo to a different branch first:"
        echo "  cd $CKIPPER_PROJECTS_DIR/$project && git checkout develop"
    else
        echo "Failed to create worktree"
    fi
    return 1
}

# Post-worktree-creation: install deps, copy .env files, sync Claude settings.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#   $2 — branch/worktree name (unused but kept for symmetry with other helpers)
#
# Reads CKIPPER_WT_WT_PATH, CKIPPER_WT_ACTIVE_ACCOUNT globals.
# Returns: 0 always (individual steps may warn on failure but don't abort).
_ckipper_worktree_post_create_setup() {
    local project="$1"

    echo "Installing dependencies..."
    (cd "$CKIPPER_WT_WT_PATH" && npm install) || echo "Warning: npm install failed. You may need to run it manually."

    for env_file in $(find "$CKIPPER_PROJECTS_DIR/$project" -maxdepth "$CKIPPER_WT_FIND_MAX_DEPTH" -name ".env*" -not -name "*.example" -not -path "*/node_modules/*" -not -path "*/.git/*"); do
        local rel_path="${env_file#$CKIPPER_PROJECTS_DIR/$project/}"
        local dest_dir="$CKIPPER_WT_WT_PATH/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$env_file" "$dest_dir/"
        echo "Copied $rel_path"
    done

    _ckipper_worktree_sync_project_registry "$project"
}

# Sync the new worktree into the project registry.
#
# Args:
#   $1 — project path (relative to CKIPPER_PROJECTS_DIR)
#
# Reads CKIPPER_WT_WT_PATH, CKIPPER_WT_ACTIVE_ACCOUNT globals.
# Returns: 0 always (failure is non-fatal).
_ckipper_worktree_sync_project_registry() {
    local project="$1"
    local main_project_path="$CKIPPER_PROJECTS_DIR/$project"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" sync \
            "$CKIPPER_WT_ACTIVE_ACCOUNT" "$main_project_path" "$CKIPPER_WT_WT_PATH" 2>/dev/null || true
    fi
}
