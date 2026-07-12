#!/usr/bin/env bash
# Code Shape Check — Codex PostToolUse hook (CX-51). Port of the Claude harness
# hooks/code-shape-check.sh, stripped of Claude-only logging/profile scaffolding.
# HARD BLOCKS (exit 2) if a written source file exceeds the whole-file line cap —
# forces immediate decomposition. Supports: .ts/.tsx/.js/.jsx/.rb/.py/.go.
#
# enforces: AGENTS.md § Code Shape Rules

set -uo pipefail

INPUT=$(cat)
# Fail-closed (Iron Law 8): without a parseable payload we cannot tell which file
# was written, so we cannot verify its shape — refuse rather than pass silently.
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "BLOCKED: code-shape-check received an unevaluable payload; failing closed." >&2
  exit 2
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
LINE_LIMIT="${CLAUDE_FILE_LINE_LIMIT:-300}"

[[ -z "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.rb|*.py|*.go) ;;
    *) exit 0 ;;
esac

# Skip test files, config files, vendored trees — measured by path shape.
if [[ "$FILE_PATH" =~ \.(test|spec)\.(ts|tsx|js|jsx)$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ _spec\.rb$ ]]; then exit 0; fi
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" =~ ^test_.*\.py$ ]] || [[ "$BASENAME" =~ _test\.py$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ _test\.go$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ /__tests__/ ]] || [[ "$FILE_PATH" =~ /test/ ]] || [[ "$FILE_PATH" =~ /tests/ ]] || [[ "$FILE_PATH" =~ /e2e/ ]] || [[ "$FILE_PATH" =~ /spec/ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ \.config\.(ts|js)$ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ (tailwind|babel|metro|jest|eslint|prettier) ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ /node_modules/ ]]; then exit 0; fi
if [[ "$FILE_PATH" =~ config/.*\.rb$ ]]; then exit 0; fi
if [[ "$BASENAME" == "conftest.py" ]] || [[ "$BASENAME" == "setup.py" ]] || [[ "$BASENAME" == "__init__.py" ]]; then exit 0; fi

# Deleted file → nothing to measure.
[[ -f "$FILE_PATH" ]] || exit 0

LINE_COUNT=$(wc -l < "$FILE_PATH" | tr -d ' ')

if [[ "$LINE_COUNT" -gt "$LINE_LIMIT" ]]; then
    echo "" >&2
    echo "CODE SHAPE VIOLATION: $FILE_PATH has $LINE_COUNT lines (limit: $LINE_LIMIT)" >&2
    echo "BLOCKED: Decompose this file before continuing (extract modules/functions)." >&2
    echo "" >&2
    exit 2
fi

exit 0
