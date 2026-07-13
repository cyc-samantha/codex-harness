#!/usr/bin/env bash
# Comment Smell Check — Codex PostToolUse hook (CX-51). Port of the Claude harness
# hooks/comment-smell-check.sh, stripped of Claude-only scaffolding.
# BLOCKS (exit 2) on a new/changed WHAT comment that restates code; advisory
# (exit 0) on legacy comments. Doc-comments, license headers, WHY:/SAFETY: notes,
# and directive/pragma comments pass. Supports: .ts/.tsx/.js/.jsx/.rb/.py/.go.
#
# enforces: AGENTS.md § Code Shape Rules (Comments carry WHY only)

set -uo pipefail

INPUT=$(cat)
# Fail-closed (Iron Law 8): without a parseable payload we cannot tell which file
# was written, so we cannot inspect its comments — refuse rather than pass.
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "BLOCKED: comment-smell-check received an unevaluable payload; failing closed." >&2
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

# New/legacy discrimination: any git error => fail-open advisory (exit 0).
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -z "$REPO_ROOT" ]] && exit 0

if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$FILE_PATH" >/dev/null 2>&1; then
    DIFF=$(git -C "$REPO_ROOT" diff HEAD -- "$FILE_PATH" 2>/dev/null) || exit 0
    [[ -z "$DIFF" ]] && exit 0
    ADDED_LINES=$(printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' | sed 's/^+//')
else
    ADDED_LINES=$(cat "$FILE_PATH")
fi

[[ -z "$ADDED_LINES" ]] && exit 0

# is_what_comment <line> => prints "1" if the line is a blocking WHAT comment.
is_what_comment() {
    local line="$1"
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
        '#'*|'//'*|'/*'*) ;;
        *) return 1 ;;
    esac
    case "$trimmed" in '#!'*) return 1 ;; esac
    case "$trimmed" in '/**'*|'///'*) return 1 ;; esac
    case "$trimmed" in '"""'*|"'''"*) return 1 ;; esac
    if printf '%s' "$trimmed" | grep -qE 'SPDX|Copyright|License|@license'; then return 1; fi
    if printf '%s' "$trimmed" | grep -qiE '^(#|//)[[:space:]]*(WHY|SAFETY|NOTE|HACK|TODO|FIXME|WARNING|IMPORTANT|XXX|REVIEW|CONTRACT|RETURNS|RAISES|THROWS|PRECONDITION|POSTCONDITION|DEBT):'; then return 1; fi
    if printf '%s' "$trimmed" | grep -qE '@(param|return|returns|type|license)'; then return 1; fi
    if printf '%s' "$trimmed" | grep -qE 'frozen_string_literal:|rubocop:|^#[[:space:]]*type:|noqa|pylint:|eslint-disable|@ts-|prettier-ignore|biome-ignore|^#[[:space:]]*-\*-|^#[[:space:]]*coding:|^#[[:space:]]*vim:|^#[[:space:]]*-!-'; then return 1; fi
    local text
    text="${trimmed#'#'}"; text="${text#'//'}"; text="${text#'/*'}"
    text="${text#"${text%%[![:space:]]*}"}"
    if printf '%s' "$text" | grep -qiE '^(increment|loop|iterate|set|get|check|call|return|create|initialize|fetch|update|delete|remove|add|build|send|open|close|read|write|load|save|parse|format|convert|handle|process|compute|calculate|run|start|stop|reset|clear|sort|filter|map|find|count|print|log|show|hide|enable|disable|append|insert|push|pop|shift|unshift)[[:space:]]'; then
        printf '1'
    fi
}

VIOLATION=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ -n "$(is_what_comment "$line")" ]]; then VIOLATION=1; break; fi
done <<< "$ADDED_LINES"

if [[ "$VIOLATION" -eq 1 ]]; then
    echo "" >&2
    echo "BLOCKED: comment restates code (WHAT). Delete it or rewrite as WHY (intent/constraint/contract). Doc-comments, license headers, and WHY:/SAFETY: notes are allowed. See AGENTS.md § Code Shape Rules." >&2
    echo "  File: $FILE_PATH" >&2
    echo "" >&2
    exit 2
fi

exit 0
