#!/usr/bin/env zsh
# Worktree list, remove, and create operations for w().

readonly W_FIND_MAX_DEPTH=3

# Print all worktrees under $W_WORKTREES_DIR, grouped by project.
#
# Reads W_PROJECTS_DIR and W_WORKTREES_DIR globals.
_w_list_worktrees() {
    echo "=== All Worktrees ==="
    [[ ! -d "$W_WORKTREES_DIR" ]] && return 0

    local previous_project_for_grouping=""
    find "$W_WORKTREES_DIR" -name ".git" -type f -not -path "*/node_modules/*" 2>/dev/null \
        | sort \
        | while IFS= read -r git_metadata_file; do
            local wt_dir="${git_metadata_file:h}"
            local rel="${wt_dir#$W_WORKTREES_DIR/}"
            local project="${rel%%/*}"
            local after_first="${rel#*/}"
            [[ "$after_first" == "$rel" ]] && continue

            local branch
            _w_get_project_and_branch "$project" "$after_first" project branch

            if [[ "$project" != "$previous_project_for_grouping" ]]; then
                previous_project_for_grouping="$project"
                echo "\n[$project]"
            fi
            echo "  • $branch"
        done
}

# Set the caller's project and branch variables from path components.
#
# Args:
#   $1 — initial project name (first path component)
#   $2 — path after the first component
#   $3 — variable name to receive the resolved project
#   $4 — variable name to receive the resolved branch
#
# Returns: 0 always.
_w_get_project_and_branch() {
    local initial_project="$1"
    local after_first="$2"
    local out_project_var="$3"
    local out_branch_var="$4"

    local second="${after_first%%/*}"
    local rest="${after_first#*/}"

    if [[ -d "$W_PROJECTS_DIR/$initial_project/$second/.git" ]]; then
        eval "$out_project_var=\"$initial_project/$second\""
        eval "$out_branch_var=\"$rest\""
    else
        eval "$out_project_var=\"$initial_project\""
        eval "$out_branch_var=\"$after_first\""
    fi
}

# Remove a worktree and delete its branch.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — worktree/branch name
#
# Reads W_FLAG_FORCE, W_WORKTREES_DIR, W_PROJECTS_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Usage: w --rm [--force] <project> <worktree>" — when project or worktree is empty
#   "Worktree not found: <path>" — when the worktree directory does not exist
#   "Failed to remove worktree. Use --force if it has uncommitted changes." — on git error
_w_remove_worktree() {
    local project="$1"
    local worktree="$2"

    if [[ -z "$project" || -z "$worktree" ]]; then
        echo "Usage: w --rm [--force] <project> <worktree>"
        return 1
    fi

    local wt_path="$W_WORKTREES_DIR/$project/$worktree"
    if [[ ! -d "$wt_path" ]]; then
        echo "Worktree not found: $wt_path"
        return 1
    fi

    local force_flag=""
    [[ "$W_FLAG_FORCE" = true ]] && force_flag="--force"

    (cd "$W_PROJECTS_DIR/$project" && git worktree remove $force_flag "$wt_path" && git branch -D "$worktree" 2>/dev/null) || {
        echo "Failed to remove worktree. Use --force if it has uncommitted changes."
        return 1
    }

    _w_cleanup_project_registry "$wt_path"
}

# Remove a worktree path from the project registry if the cleanup script exists.
#
# Args:
#   $1 — absolute path to the worktree that was removed
#
# Returns: 0 always (failure is non-fatal).
_w_cleanup_project_registry() {
    local wt_path="$1"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" remove "$wt_path" 2>/dev/null || true
    fi
}

# Create a worktree for the given project and branch (idempotent if it already exists).
# Sets W_WT_PATH to the resolved worktree path.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch name
#
# Reads W_PROJECTS_DIR, W_WORKTREES_DIR, W_ACTIVE_ACCOUNT, W_ACTIVE_CONFIG_DIR globals.
# Returns: 0 on success; 1 on validation failure or git error.
# Errors (stderr):
#   "Project not found: <path>" — when the project directory does not exist
#   "Error: <path> exists but is not a valid worktree." — when dir exists but lacks .git file
_w_create_worktree() {
    local project="$1"
    local worktree="$2"

    if [[ ! -d "$W_PROJECTS_DIR/$project" ]]; then
        echo "Project not found: $W_PROJECTS_DIR/$project"
        return 1
    fi

    if [[ -d "$W_WORKTREES_DIR/$project/$worktree" ]]; then
        _w_validate_existing_worktree "$project" "$worktree" || return 1
        W_WT_PATH="$W_WORKTREES_DIR/$project/$worktree"
        return 0
    fi

    echo "Creating worktree: $worktree"
    mkdir -p "$W_WORKTREES_DIR/$project"
    W_WT_PATH="$W_WORKTREES_DIR/$project/$worktree"

    _w_fetch_and_create "$project" "$worktree" || return 1
    _w_post_create_setup "$project" "$worktree" || return 1
}

# Validate that an existing directory at the worktree path is a real worktree.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 if valid; 1 if the directory exists but has no .git file.
# Errors (stderr):
#   "Error: <path> exists but is not a valid worktree." — when .git file is missing
_w_validate_existing_worktree() {
    local project="$1"
    local worktree="$2"
    local wt_path="$W_WORKTREES_DIR/$project/$worktree"

    if [[ ! -f "$wt_path/.git" ]]; then
        echo "Error: $wt_path exists but is not a valid worktree."
        echo "Remove it manually or use a different branch name."
        return 1
    fi
}

# Fetch from origin and create the git worktree.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 on success; 1 if fetch or worktree creation fails.
# Errors (stderr):
#   "Failed to fetch from origin. ..." — when git fetch fails
#   "Failed: branch '<name>' is currently checked out..." — when branch is already in use
#   "Failed to create worktree" — on other git worktree add failures
_w_fetch_and_create() {
    local project="$1"
    local worktree="$2"

    _w_fetch_origin "$project" "$worktree" || return 1
    _w_add_worktree "$project" "$worktree"
}

# Fetch origin/develop and optionally origin/<branch> for the project.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch name to attempt fetching
#
# Returns: 0 on success; 1 if origin/develop fetch fails.
# Errors (stderr):
#   "Failed to fetch from origin. Check your network connection..." — on fetch failure
_w_fetch_origin() {
    local project="$1"
    local worktree="$2"

    (cd "$W_PROJECTS_DIR/$project" && git fetch origin develop) || {
        echo "Failed to fetch from origin. Check your network connection and that 'develop' exists on the remote."
        return 1
    }
    (cd "$W_PROJECTS_DIR/$project" && git fetch origin "$worktree" 2>/dev/null) || true
}

# Add the git worktree, choosing local, remote, or new branch as appropriate.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 0 on success; 1 if git worktree add fails.
# Errors (stderr):
#   "Failed: branch '<name>' is currently checked out..." — when branch is in use
#   "Failed to create worktree" — on other failures
_w_add_worktree() {
    local project="$1"
    local worktree="$2"

    (cd "$W_PROJECTS_DIR/$project" && \
        if git show-ref --verify --quiet "refs/heads/$worktree"; then
            echo "Using existing local branch: $worktree"
            git worktree add "$W_WT_PATH" "$worktree"
        elif git show-ref --verify --quiet "refs/remotes/origin/$worktree"; then
            echo "Tracking remote branch: origin/$worktree"
            git worktree add "$W_WT_PATH" -b "$worktree" "origin/$worktree"
        else
            echo "Creating new branch from origin/develop"
            git worktree add "$W_WT_PATH" -b "$worktree" origin/develop
        fi
    ) || _w_handle_worktree_add_failure "$project" "$worktree"
}

# Handle failure from git worktree add, printing a contextual error.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch/worktree name
#
# Returns: 1 always.
# Errors (stderr):
#   "Failed: branch '<name>' is currently checked out..." — when branch is in use
#   "Failed to create worktree" — on other failures
_w_handle_worktree_add_failure() {
    local project="$1"
    local worktree="$2"
    local current_branch
    current_branch=$(cd "$W_PROJECTS_DIR/$project" && git branch --show-current 2>/dev/null)
    if [[ "$current_branch" == "$worktree" ]]; then
        echo "Failed: branch '$worktree' is currently checked out in the main repo."
        echo "Switch the main repo to a different branch first:"
        echo "  cd $W_PROJECTS_DIR/$project && git checkout develop"
    else
        echo "Failed to create worktree"
    fi
    return 1
}

# Post-worktree-creation: install deps, copy .env files, sync Claude settings.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#   $2 — branch/worktree name (unused but kept for symmetry with other helpers)
#
# Reads W_WT_PATH, W_ACTIVE_ACCOUNT globals.
# Returns: 0 always (individual steps may warn on failure but don't abort).
_w_post_create_setup() {
    local project="$1"

    echo "Installing dependencies..."
    (cd "$W_WT_PATH" && npm install) || echo "Warning: npm install failed. You may need to run it manually."

    for env_file in $(find "$W_PROJECTS_DIR/$project" -maxdepth "$W_FIND_MAX_DEPTH" -name ".env*" -not -name "*.example" -not -path "*/node_modules/*" -not -path "*/.git/*"); do
        local rel_path="${env_file#$W_PROJECTS_DIR/$project/}"
        local dest_dir="$W_WT_PATH/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$env_file" "$dest_dir/"
        echo "Copied $rel_path"
    done

    _w_sync_project_registry "$project"
}

# Sync the new worktree into the project registry.
#
# Args:
#   $1 — project path (relative to W_PROJECTS_DIR)
#
# Reads W_WT_PATH, W_ACTIVE_ACCOUNT globals.
# Returns: 0 always (failure is non-fatal).
_w_sync_project_registry() {
    local project="$1"
    local main_project_path="$W_PROJECTS_DIR/$project"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" sync \
            "$W_ACTIVE_ACCOUNT" "$main_project_path" "$W_WT_PATH" 2>/dev/null || true
    fi
}
