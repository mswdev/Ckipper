#!/usr/bin/env zsh
# Fuzzy-suggest helper. Pure functions: no globals read or written.
#
# Used by ckipper dispatchers to suggest the closest known subcommand
# when the user types something unrecognised.

readonly _CORE_FUZZY_DISTANCE_THRESHOLD=2

# Compute Levenshtein edit distance between two strings.
#
# Args:
#   $1 — string A
#   $2 — string B
#
# Returns: 0 always. Prints the distance (non-negative integer) to stdout.
_core_fuzzy_levenshtein() {
    local a="$1" b="$2"
    local la=${#a} lb=${#b}
    (( la == 0 )) && { echo "$lb"; return 0; }
    (( lb == 0 )) && { echo "$la"; return 0; }

    local -a prev curr
    local i j cost del ins sub
    for (( i = 0; i <= lb; i++ )); do
        prev[$((i + 1))]=$i
    done
    for (( i = 1; i <= la; i++ )); do
        curr[1]=$i
        for (( j = 1; j <= lb; j++ )); do
            cost=1
            [[ "${a[i]}" == "${b[j]}" ]] && cost=0
            del=$(( prev[j + 1] + 1 ))
            ins=$(( curr[j] + 1 ))
            sub=$(( prev[j] + cost ))
            curr[$((j + 1))]=$(( del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub) ))
        done
        prev=("${curr[@]}")
    done
    echo "${prev[lb + 1]}"
}

# Find the closest candidate to the input within the distance threshold.
#
# Walks every candidate, keeps the one with the smallest distance ≤ threshold,
# and prints it. Exact matches return distance 0 and win automatically. Ties go
# to the first-seen candidate (stable on insertion order).
#
# Args:
#   $1     — input token (the unknown subcommand the user typed)
#   $2..$N — candidate list
#
# Returns: 0 always. Prints the closest candidate, or empty string if no
# candidate is within the threshold (or the candidate list is empty).
_core_fuzzy_suggest() {
    local input="$1"
    shift
    local best="" best_dist=$(( _CORE_FUZZY_DISTANCE_THRESHOLD + 1 ))
    local candidate dist
    for candidate in "$@"; do
        dist=$(_core_fuzzy_levenshtein "$input" "$candidate")
        if (( dist <= _CORE_FUZZY_DISTANCE_THRESHOLD && dist < best_dist )); then
            best="$candidate"
            best_dist="$dist"
        fi
    done
    echo "$best"
}
