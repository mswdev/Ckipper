#!/usr/bin/env zsh
# Worktree list, remove, and create operations for w().

# Print all worktrees under $W_WORKTREES_DIR, grouped by project.
#
# Reads W_PROJECTS_DIR and W_WORKTREES_DIR globals.
_w_list_worktrees() {
    echo "=== All Worktrees ==="
    if [[ ! -d "$W_WORKTREES_DIR" ]]; then
        return 0
    fi

    local current_project=""
    find "$W_WORKTREES_DIR" -name ".git" -type f -not -path "*/node_modules/*" 2>/dev/null | sort | while IFS= read -r gitfile; do
        local wt_dir="${gitfile:h}"
        local rel="${wt_dir#$W_WORKTREES_DIR/}"
        local project="${rel%%/*}"
        local after_first="${rel#*/}"
        if [[ "$after_first" == "$rel" ]]; then
            continue
        fi
        local second="${after_first%%/*}"
        local rest="${after_first#*/}"
        if [[ -d "$W_PROJECTS_DIR/$project/$second/.git" ]]; then
            project="$project/$second"
            local branch="$rest"
        else
            local branch="$after_first"
        fi
        if [[ "$project" != "$current_project" ]]; then
            current_project="$project"
            echo "\n[$project]"
        fi
        echo "  • $branch"
    done
}

# Remove a worktree and delete its branch.
#
# Reads W_FLAG_FORCE, W_WORKTREES_DIR, W_PROJECTS_DIR globals.
# Args: $1 = project path, $2 = worktree/branch name.
# Returns: 0 on success; 1 on validation failure or git error.
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

    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" remove "$wt_path" 2>/dev/null || true
    fi
}

# Create a worktree for the given project and branch (idempotent if it already exists).
# Sets W_WT_PATH to the resolved worktree path.
#
# Reads W_PROJECTS_DIR, W_WORKTREES_DIR, W_ACTIVE_ACCOUNT, W_ACTIVE_CONFIG_DIR globals.
# Args: $1 = project path, $2 = branch name.
# Returns: 0 on success; 1 on validation failure or git error.
_w_create_worktree() {
    local project="$1"
    local worktree="$2"

    if [[ ! -d "$W_PROJECTS_DIR/$project" ]]; then
        echo "Project not found: $W_PROJECTS_DIR/$project"
        return 1
    fi

    if [[ -d "$W_WORKTREES_DIR/$project/$worktree" ]]; then
        if [[ ! -f "$W_WORKTREES_DIR/$project/$worktree/.git" ]]; then
            echo "Error: $W_WORKTREES_DIR/$project/$worktree exists but is not a valid worktree."
            echo "Remove it manually or use a different branch name."
            return 1
        fi
        W_WT_PATH="$W_WORKTREES_DIR/$project/$worktree"
        return 0
    fi

    echo "Creating worktree: $worktree"
    mkdir -p "$W_WORKTREES_DIR/$project"
    W_WT_PATH="$W_WORKTREES_DIR/$project/$worktree"

    _w_fetch_and_create "$project" "$worktree" || return 1
    _w_post_create_setup "$project" "$worktree" || return 1
}

# Fetch from origin and create the git worktree.
# Args: $1 = project, $2 = branch/worktree name.
_w_fetch_and_create() {
    local project="$1"
    local worktree="$2"

    (cd "$W_PROJECTS_DIR/$project" && git fetch origin develop) || {
        echo "Failed to fetch from origin. Check your network connection and that 'develop' exists on the remote."
        return 1
    }
    (cd "$W_PROJECTS_DIR/$project" && git fetch origin "$worktree" 2>/dev/null) || true

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
    ) || {
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
}

# Post-worktree-creation: install deps, copy .env files, sync Claude settings.
# Args: $1 = project, $2 = branch/worktree name.
_w_post_create_setup() {
    local project="$1"

    echo "Installing dependencies..."
    (cd "$W_WT_PATH" && npm install) || echo "Warning: npm install failed. You may need to run it manually."

    for env_file in $(find "$W_PROJECTS_DIR/$project" -maxdepth 3 -name ".env*" -not -name "*.example" -not -path "*/node_modules/*" -not -path "*/.git/*"); do
        local rel_path="${env_file#$W_PROJECTS_DIR/$project/}"
        local dest_dir="$W_WT_PATH/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$env_file" "$dest_dir/"
        echo "Copied $rel_path"
    done

    local main_project_path="$W_PROJECTS_DIR/$project"
    local ckipper_base_dir="${CKIPPER_DIR:-$HOME/.ckipper}"
    if [[ -f "$ckipper_base_dir/docker/cleanup-projects.py" ]]; then
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            python3 "$ckipper_base_dir/docker/cleanup-projects.py" sync \
            "$W_ACTIVE_ACCOUNT" "$main_project_path" "$W_WT_PATH" 2>/dev/null || true
    fi
}
