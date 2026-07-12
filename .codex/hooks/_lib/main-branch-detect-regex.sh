#!/usr/bin/env bash
# Regex bank for main-branch-detect — separated to keep detect.sh ≤50 lines.
# Bash 3.2 SAFE: ERE only, no PCRE features. Each function emits ONE regex.
#
# DIVERGENCE NOTE (CX-50, security-review round 1): this file was vendored
# verbatim from /home/samanthachen/git/.claude/hooks/_lib/ at port time. The
# `_mbd_normalize` wrapper-token stripping below (command/env/nice/nohup/
# time/stdbuf) does NOT exist upstream — it closes a wrapper-bypass gap found
# only in this port. Do NOT re-sync this file from the source harness without
# re-applying that stripping step, or the bypass reopens. See TRUST.md
# Reversibility escapes / upstream-drift risk for the tracking note.

_mbd_forbidden_re() {
  printf '%s' '^[[:space:]]*(\(?[[:space:]]*)?(git[[:space:]]+(checkout|switch|branch[[:space:]]+-[dD]|reset[[:space:]]+--hard|merge|rebase|pull)([[:space:]]|$)|git[[:space:]]+fetch[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+:[^[:space:]]+|git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+\+?[^[:space:]]*:(main|refs/heads/main)([[:space:]]|$)|git[[:space:]]+push[[:space:]].*(--delete|[[:space:]]-d)[[:space:]]+(.*[[:space:]])?(main|refs/heads/main)([[:space:]]|$)|git[[:space:]]+update-ref[[:space:]]+refs/heads/main([[:space:]]|$)|git[[:space:]]+symbolic-ref[[:space:]]+HEAD([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$))'
}

_mbd_delegation_re() {
  printf '%s' '^[[:space:]]*\(?[[:space:]]*(cd[[:space:]]+[^[:space:]]+[[:space:]]*&&|git[[:space:]]+-C[[:space:]]+[^[:space:]]+|git[[:space:]]+--git-dir=[^[:space:]]+)'
}

_mbd_wrapper_re() {
  printf '%s' '(^|[[:space:]])(bash|sh)[[:space:]]+-c([[:space:]]|$)|(^|[[:space:]])eval([[:space:]]|$)|(^|[[:space:]])xargs[[:space:]]+([^[:space:]]+[[:space:]]+)*git([[:space:]]|$)|(^|[[:space:]])find[[:space:]].*-exec[[:space:]]+git([[:space:]]|$)'
}

_mbd_cd_prefix_re() {
  printf '%s' '^[[:space:]]*\(?[[:space:]]*cd[[:space:]]+[^[:space:]]+[[:space:]]*&&'
}

# Leading invocation-wrapper tokens that run their argument directly without
# shell reinterpretation (unlike bash -c / eval / xargs, which ARE still
# blocked outright by _mbd_wrapper_re). Stripped so the git verb underneath
# becomes visible to _mbd_forbidden_re. Iterative: handles chained wrappers
# (e.g. `nice nohup command git checkout main`).
_mbd_strip_leading_wrappers() {
  local cmd="$1" prev
  local wrapper_re='^[[:space:]]*(\(?[[:space:]]*)?(command|env|nice|nohup|time|stdbuf)([[:space:]]+-[^[:space:]]+)*[[:space:]]+'
  while :; do
    prev="$cmd"
    cmd=$(printf '%s' "$cmd" | sed -E "s#${wrapper_re}#\1#")
    [[ "$cmd" == "$prev" ]] && break
  done
  printf '%s' "$cmd"
}

_mbd_normalize() {
  printf '%s' "$1" | sed -E 's#^[[:space:]]*(\(?[[:space:]]*)?([A-Z_]+=[^[:space:]]+[[:space:]]+)+#\1#' \
                   | sed -E 's#(^|[[:space:]])(/[^[:space:]]+)?/git([[:space:]])#\1git\3#' \
                   | sed -E 's#(^|[[:space:]])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)+([[:space:]])#\1git\3#'
}

_mbd_git_c_prefix_re() {
  printf '%s' '^[[:space:]]*(\(?[[:space:]]*)?git[[:space:]]+-C[[:space:]]+[^[:space:]]+'
}
