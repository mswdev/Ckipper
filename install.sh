#!/bin/bash
# Ckipper installer. Copies ckipper.zsh and lib/ into $CKIPPER_DIR
# (default ~/.ckipper), removes files left by the old Docker-based layout,
# and makes ~/.zshrc source the installed ckipper.zsh.
#
# Safe to re-run: accounts.json, desktop.json, and aliases.zsh are never
# touched.
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE='source "$HOME/.ckipper/ckipper.zsh"'

# Paths under $CKIPPER_DIR that only the old Docker-based layout used.
LEGACY_PATHS=(docker hooks settings-template.json)

# Exit with a list of missing tools when any prerequisite is absent.
check_prerequisites() {
    local missing=()
    command -v jq &>/dev/null || missing+=("jq (brew install jq)")
    command -v gum &>/dev/null || missing+=("gum (brew install gum)")
    if [[ "$(uname)" == "Darwin" ]]; then
        command -v security &>/dev/null || missing+=("security (macOS Keychain CLI)")
    fi
    [[ ${#missing[@]} -eq 0 ]] && return 0
    echo "Missing prerequisites:"
    printf '  - %s\n' "${missing[@]}"
    echo ""
    echo "Install the missing tools and re-run this script."
    exit 1
}

# Copy ckipper.zsh and lib/ into $CKIPPER_DIR, excluding test files so
# test stubs can never end up on a user's PATH.
deploy_files() {
    mkdir -p "$CKIPPER_DIR/lib"
    cp "$REPO_DIR/ckipper.zsh" "$CKIPPER_DIR/ckipper.zsh"
    rsync -a --delete --exclude='*_test.bats' "$REPO_DIR/lib/" "$CKIPPER_DIR/lib/"
    if find "$CKIPPER_DIR/lib" -name '*_test.*' | grep -q .; then
        echo "ERROR: test files leaked into $CKIPPER_DIR/lib/" >&2
        exit 1
    fi
}

# Delete files that only the old Docker-based layout used.
remove_legacy_paths() {
    local rel
    for rel in "${LEGACY_PATHS[@]}"; do
        [[ -e "$CKIPPER_DIR/$rel" ]] || continue
        echo "  Removing old Docker-era $CKIPPER_DIR/$rel"
        rm -rf "${CKIPPER_DIR:?}/$rel"
    done
}

# Point ~/.zshrc at the installed ckipper.zsh. Rewrites a source line for an
# older install location (.../docker/ckipper.zsh or .../docker/w-function.zsh)
# in place, after a timestamped backup; appends the line when none exists.
update_zshrc() {
    local old_pattern='^[[:space:]]*source[[:space:]]+["'\'']?[$~/][^"'\'']*/docker/(ckipper|w-function)\.zsh["'\'']?[[:space:]]*(#.*)?$'
    if grep -qE "$old_pattern" "$ZSHRC" 2>/dev/null; then
        local backup
        backup="$ZSHRC.ckipper-bak.$(date -u +%Y%m%dT%H%M%SZ)"
        cp "$ZSHRC" "$backup"
        # Comma delimiter: the pattern itself contains `|` and `#`.
        sed -E "s,$old_pattern,$SOURCE_LINE," "$backup" >"$ZSHRC"
        echo "  Updated ~/.zshrc source line to ~/.ckipper/ckipper.zsh (backup: $backup)"
        return 0
    fi
    if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
        echo "  ~/.zshrc already sources ~/.ckipper/ckipper.zsh"
        return 0
    fi
    printf '\n# Ckipper — multi-account Claude Code manager\n%s\n' "$SOURCE_LINE" >>"$ZSHRC"
    echo "  Added ckipper source line to ~/.zshrc"
}

# Print the aliases.zsh source line when ~/.zshrc does not have it yet.
print_aliases_hint() {
    grep -q 'ckipper/aliases.zsh' "$ZSHRC" 2>/dev/null && return 0
    echo ""
    echo "Optional: enable per-account launchers (claude-<name> and bare <name>) by adding to ~/.zshrc:"
    echo "    [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"
}

echo "=== Ckipper Installer ==="
check_prerequisites
echo "Copying ckipper.zsh and lib/ to $CKIPPER_DIR/..."
deploy_files
remove_legacy_paths
update_zshrc
print_aliases_hint
echo ""
echo "=== Install complete ==="
echo "Next: source ~/.zshrc, then run 'ckipper account add <name>' or 'ckipper doctor'."
echo "To update later: git pull && ./install.sh"
