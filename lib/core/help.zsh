#!/usr/bin/env zsh
# Uniform help-page renderer for ckipper subcommand --help output.
#
# Wraps _core_style_header (from lib/core/style.zsh) so every help page renders
# with the same divider+title+divider chrome, then prints body lines verbatim.
# Body content (Synopsis / Description / Args / Examples / etc.) is the
# caller's responsibility; this module only owns the chrome and the line-wise
# emission contract.

# Render a help page: styled header followed by body lines.
#
# Args: $1 — page title (passed straight to _core_style_header).
#       $2..$N — body lines; each is printed verbatim on its own line.
# Returns: 0 always.
#
# Example:
#   _core_help_render "ckipper account add" \
#       "Synopsis: ckipper account add <name>" \
#       "Description: register a new isolated account."
_core_help_render() {
    local title="$1"
    shift 2>/dev/null
    _core_style_header "$title"
    (($# == 0)) && return 0
    printf '%s\n' "$@"
    echo ""
}
