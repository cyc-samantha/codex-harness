#!/usr/bin/env bash
# Function Body Length Check — Codex PostToolUse hook (CX-51). Port of the Claude
# harness hooks/function-body-check.sh, stripped of Claude-only scaffolding.
# BLOCKS (exit 2) on a new/changed function over the per-language limit
# (Ruby 5, TS/JS 12, Python/Go 8); ADVISORY (exit 0) on pre-existing legacy
# violations. New vs legacy is decided by diffing the file against HEAD; any git
# failure fails open to advisory. Supports: .ts/.tsx/.js/.jsx/.rb/.py/.go.
#
# enforces: AGENTS.md § Code Shape Rules

set -uo pipefail

INPUT=$(cat)
# Fail-closed (Iron Law 8): without a parseable payload we cannot tell which file
# was written, so we cannot measure its functions — refuse rather than pass.
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "BLOCKED: function-body-check received an unevaluable payload; failing closed." >&2
  exit 2
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.rb|*.py|*.go) ;;
    *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH")
if [[ "$FILE_PATH" =~ \.(test|spec)\.(ts|tsx|js|jsx)$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ _spec\.rb$ ]]; then exit 0; fi
if [[ "$BASENAME" =~ ^test_.*\.py$ ]] || [[ "$BASENAME" =~ _test\.py$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ _test\.go$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ /__tests__/ ]] || [[ "$FILE_PATH" =~ /test/ ]] || [[ "$FILE_PATH" =~ /tests/ ]] || [[ "$FILE_PATH" =~ /e2e/ ]] || [[ "$FILE_PATH" =~ /spec/ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ \.config\.(ts|js)$ ]] || [[ "$FILE_PATH" =~ (tailwind|babel|metro|jest|eslint|prettier) ]] || [[ "$FILE_PATH" =~ /node_modules/ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ config/.*\.rb$ ]]; then exit 0; fi
if [[ "$BASENAME" == "conftest.py" ]] || [[ "$BASENAME" == "setup.py" ]] || [[ "$BASENAME" == "__init__.py" ]]; then exit 0; fi
[[ -f "$FILE_PATH" ]] || exit 0

# Per-language smell limit: Ruby tightest (5), TS/JS permissive (12), Python/Go 8.
case "$FILE_PATH" in
    *.rb) FUNC_LIMIT="${CLAUDE_FUNCTION_LINE_LIMIT_RB:-5}" ;;
    *.ts|*.tsx|*.js|*.jsx) FUNC_LIMIT="${CLAUDE_FUNCTION_LINE_LIMIT_TS:-12}" ;;
    *) FUNC_LIMIT="${CLAUDE_FUNCTION_LINE_LIMIT:-8}" ;;
esac

VIOLATIONS=""
case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx)
        VIOLATIONS=$(awk -v limit="$FUNC_LIMIT" '
BEGIN { depth=0; fname=""; fline=0; body=0; violations="" }
/^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[a-zA-Z]/ {
    fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0
    if (/{/) { depth++ }
    next
}
/^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+[a-zA-Z]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(/ {
    fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0; next
}
fname != "" && /{/ { depth++ }
fname != "" && /}/ {
    depth--
    if (depth <= 0) {
        if (body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
        fname=""; body=0; depth=0
    }
}
fname != "" && depth > 0 { body++ }
END { printf "%s", violations }
' "$FILE_PATH")
        ;;
    *.rb)
        VIOLATIONS=$(awk -v limit="$FUNC_LIMIT" '
BEGIN { fname=""; fline=0; body=0; depth=0; violations="" }
/^[[:space:]]*def[[:space:]]+[a-zA-Z_]/ {
    if (fname != "" && body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
    fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0; depth=1; next
}
fname != "" && /^[[:space:]]*(if|unless|case|begin|do|class|module|def|while|until|for)[[:space:]]/ { depth++ }
fname != "" && / do( |\||$)/ && !/^[[:space:]]*do[[:space:]]/ { depth++ }
fname != "" && /^[[:space:]]*end[[:space:]]*$/ {
    depth--
    if (depth <= 0) {
        if (body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
        fname=""; body=0; depth=0; next
    }
}
fname != "" && depth > 0 { body++ }
END { printf "%s", violations }
' "$FILE_PATH")
        ;;
    *.py)
        VIOLATIONS=$(awk -v limit="$FUNC_LIMIT" '
BEGIN { fname=""; fline=0; body=0; findent=-1; violations="" }
/^[[:space:]]*def[[:space:]]+[a-zA-Z_]/ {
    if (fname != "" && body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
    fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0
    findent=0; tmp=$0; gsub(/[^ \t].*/, "", tmp); gsub(/\t/, "    ", tmp); findent=length(tmp)
    next
}
fname != "" {
    if (/^[[:space:]]*$/) { body++; next }
    indent=0; tmp=$0; gsub(/[^ \t].*/, "", tmp); gsub(/\t/, "    ", tmp); indent=length(tmp)
    if (indent <= findent) {
        if (body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
        fname=""; body=0; findent=-1
        if (/^[[:space:]]*def[[:space:]]+[a-zA-Z_]/) {
            fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0
            findent=0; tmp=$0; gsub(/[^ \t].*/, "", tmp); gsub(/\t/, "    ", tmp); findent=length(tmp)
        }
    } else { body++ }
}
END {
    if (fname != "" && body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
    printf "%s", violations
}
' "$FILE_PATH")
        ;;
    *.go)
        VIOLATIONS=$(awk -v limit="$FUNC_LIMIT" '
BEGIN { fname=""; fline=0; body=0; depth=0; violations="" }
/^[[:space:]]*func[[:space:]]/ {
    fname=$0; sub(/^[[:space:]]+/, "", fname); fline=NR; body=0; depth=0
    if (/{/) { depth++ }
    next
}
fname != "" && /{/ { depth++ }
fname != "" && /}/ {
    depth--
    if (depth <= 0) {
        if (body > limit) { violations = violations "  Line " fline ": " body " lines (limit: " limit ")\n" }
        fname=""; body=0; depth=0; next
    }
}
fname != "" && depth > 0 { body++ }
END { printf "%s", violations }
' "$FILE_PATH")
        ;;
esac

[[ -z "$VIOLATIONS" ]] && exit 0

print_violation_warning() {
    echo "" >&2
    echo "WARNING: Function body exceeds $FUNC_LIMIT lines in $FILE_PATH. Shape constraint: functions <= $FUNC_LIMIT lines." >&2
    echo "$VIOLATIONS" >&2
    echo "Consider extracting helper functions or decomposing." >&2
    echo "" >&2
}

# WHY: PostToolUse fires after the write, so the file is on disk and can be
# diffed against HEAD to separate new/changed violations (block) from
# pre-existing legacy ones (advisory). Any git failure fails open to advisory.
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$REPO_ROOT" ]]; then
    print_violation_warning
    exit 0
fi

added_line_numbers() {
    local diff="$1"
    echo "$diff" | awk '
/^@@ / {
    h=$0; sub(/^@@ -[0-9,]+ \+/, "", h); sub(/ @@.*/, "", h)
    n=h
    if (index(h, ",") > 0) { split(h, a, ","); n=a[1] }
    newline = n; next
}
/^\+\+\+/ { next }
/^\+/ { print newline; newline++ }
/^-/ { next }
/^ / { newline++ }
'
}

fline_is_added() {
    local fline="$1" added="$2"
    while read -r n; do
        [[ -z "$n" ]] && continue
        if (( n == fline )); then return 0; fi
    done <<< "$added"
    return 1
}

BLOCKING=0
if ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$FILE_PATH" >/dev/null 2>&1; then
    BLOCKING=1
else
    DIFF=$(git -C "$REPO_ROOT" diff HEAD -- "$FILE_PATH" 2>/dev/null)
    if [[ -n "$DIFF" ]]; then
        ADDED=$(added_line_numbers "$DIFF")
        while IFS= read -r line; do
            [[ "$line" =~ Line\ ([0-9]+): ]] || continue
            if fline_is_added "${BASH_REMATCH[1]}" "$ADDED"; then BLOCKING=1; break; fi
        done <<< "$VIOLATIONS"
    fi
fi

print_violation_warning
if (( BLOCKING )); then
    echo "BLOCKED: new/changed function exceeds the per-language limit (Ruby 5 / TS 12 / Python-Go 8). Split it, or if the pieces would be entangled, keep them together — see AGENTS.md § Code Shape Rules." >&2
    exit 2
fi

exit 0
