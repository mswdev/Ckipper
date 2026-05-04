#!/usr/bin/env zsh
# Docker image build helper for `ckipper worktree rebuild-image`.

# Build the ckipper-dev Docker image from $CKIPPER_DIR/docker/Dockerfile.
#
# Returns: 0 on success; 1 if Dockerfile not found or docker build fails.
_ckipper_worktree_build_image() {
    local docker_dir="${CKIPPER_DIR:-$HOME/.ckipper}/docker"
    if [[ ! -f "$docker_dir/Dockerfile" ]]; then
        echo "Dockerfile not found: $docker_dir/Dockerfile" >&2
        return 1
    fi
    echo "Building ckipper-dev Docker image..."
    docker build --build-arg "CACHEBUST=$(date +%s)" -t ckipper-dev "$docker_dir"
}
