#!/usr/bin/env zsh
# ANSI color/style helpers for ckipper CLI output.
#
# All public helpers degrade gracefully when color is disabled (NO_COLOR set,
# or stdout is not a TTY). Tests pin behavior with CKIPPER_FORCE_COLOR=1, which
# overrides every other check so output is deterministic in non-TTY runs.
#
# Decision precedence in _core_style_enabled:
#   1. CKIPPER_FORCE_COLOR=1  → enabled (test override; wins over NO_COLOR).
#   2. NO_COLOR set non-empty → disabled (https://no-color.org).
#   3. stdout is a TTY        → enabled.
#   4. otherwise              → disabled.

# Width of the horizontal rule drawn by _core_style_divider / _core_style_header.
readonly _CORE_STYLE_DIVIDER_WIDTH=72

# Column width used by _core_style_table for printf %-N s formatting.
readonly _CORE_STYLE_TABLE_COL_WIDTH=22

# ANSI reset sequence — emitted at the end of every colored span.
readonly _CORE_STYLE_RESET=$'\x1b[0m'

# Map of friendly color/style names → ANSI SGR parameter codes.
# `gray` is mapped to bright-black (90) — true 8-color "gray" is rendered as
# bright-black on every terminal we care about.
typeset -gA _CORE_STYLE_COLOR_CODE=(
    [red]=31
    [green]=32
    [yellow]=33
    [blue]=34
    [magenta]=35
    [cyan]=36
    [gray]=90
    [bold]=1
    [dim]=2
    [reset]=0
)

# Decide whether to emit ANSI color codes.
#
# Returns: 0 if color should be emitted; 1 otherwise.
_core_style_enabled() {
    [[ "$CKIPPER_FORCE_COLOR" == "1" ]] && return 0
    [[ -n "$NO_COLOR" ]] && return 1
    [[ -t 1 ]]
}

# Print text wrapped in an ANSI color escape, or plain text when color is disabled.
#
# Args: $1 — color name (must be a key of _CORE_STYLE_COLOR_CODE),
#       $2 — text to wrap.
# Returns: 0 always; prints the (possibly colored) text followed by a newline.
_core_style_color() {
    local name="$1" text="$2"
    if ! _core_style_enabled; then
        printf '%s\n' "$text"
        return 0
    fi
    local code="${_CORE_STYLE_COLOR_CODE[$name]}"
    printf '\x1b[%sm%s%s\n' "$code" "$text" "$_CORE_STYLE_RESET"
}

# Print a bracketed status badge in the given color (e.g. "[PASS]" in green).
# When color is disabled, prints "[<label>]" plain.
#
# Args: $1 — label text (e.g. "PASS", "FAIL"),
#       $2 — color name from _CORE_STYLE_COLOR_CODE.
# Returns: 0 always.
_core_style_badge() {
    local label="$1" color="$2"
    _core_style_color "$color" "[$label]"
}

# Print a horizontal rule of box-draw characters at _CORE_STYLE_DIVIDER_WIDTH.
#
# Returns: 0 always.
_core_style_divider() {
    local rule
    rule=$(printf '─%.0s' {1..$_CORE_STYLE_DIVIDER_WIDTH})
    printf '%s\n' "$rule"
}

# Print a styled section header: divider, bold title, divider.
#
# Args: $1 — title text.
# Returns: 0 always.
_core_style_header() {
    local title="$1"
    _core_style_divider
    _core_style_color bold "$title"
    _core_style_divider
}

# Format a single pipe-separated row into fixed-width columns.
# Helper for _core_style_table; kept private to satisfy the 25-line cap.
#
# Args: $1 — pipe-separated row (e.g. "col1|col2|col3").
# Returns: 0 always; prints the row followed by a newline.
_core_style_table_print_row() {
    local row="$1"
    local -a cells
    cells=("${(@s:|:)row}")
    local cell
    for cell in "${cells[@]}"; do
        printf "%-${_CORE_STYLE_TABLE_COL_WIDTH}s" "$cell"
    done
    printf '\n'
}

# Render a table with header columns from args and pipe-separated rows from stdin.
# Each cell is padded to _CORE_STYLE_TABLE_COL_WIDTH for visual alignment.
#
# Args: $@ — header column names (one per column).
# Returns: 0 always.
#
# Example:
#   printf 'a|b\nc|d\n' | _core_style_table NAME VALUE
_core_style_table() {
    local header
    header="${(j:|:)@}"
    _core_style_table_print_row "$header"
    local row
    while IFS= read -r row; do
        _core_style_table_print_row "$row"
    done
}
