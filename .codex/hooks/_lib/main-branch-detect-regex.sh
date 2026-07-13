#!/usr/bin/env bash
# Regex bank for main-branch-detect — separated to keep detect.sh ≤50 lines.
# Bash 3.2 SAFE: ERE only, no PCRE features. Each function emits ONE regex.
#
# DIVERGENCE NOTE (CX-50, security-review rounds 1-2): this file was vendored
# verbatim from /home/samanthachen/git/.claude/hooks/_lib/ at port time. The
# `_mbd_strip_leading_wrappers` token-scan below (command/env/nice/nohup/
# time/stdbuf/timeout/setsid/ionice/chrt/taskset/flock/sudo/doas) does NOT
# exist upstream — it closes a wrapper-bypass gap found only in this port,
# including separate-arg wrapper flags
# (`nice -n 10`, `stdbuf -o 0`) and mandatory positional args (`timeout 5`).
# Do NOT re-sync this file from the source harness without re-applying that
# stripping step, or the bypass reopens. See TRUST.md Reversibility escapes /
# upstream-drift risk for the tracking note.

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
# becomes visible to _mbd_forbidden_re.
#
# Token-scan (not a flag-shape regex): once the first token is a known
# wrapper verb, every token up to but not including the first bare
# `git`/`gh` token is dropped (the git/gh token itself is kept). This is
# deliberately flag-shape-agnostic — it handles
# attached flags (`nice -n10`), space-separated flag VALUES (`nice -n 10`,
# `stdbuf -o 0`), mandatory positional args (`timeout 5`), and `env`'s
# `KEY=VALUE`/`-i` forms uniformly, without enumerating each wrapper's CLI
# grammar (round-2 finding: the prior attached-flag-only regex left a stray
# value token in front of `git`, defeating the anchored forbidden-pattern
# match).
_mbd_strip_leading_wrappers() {
  local cmd="$1" lead="" body="$1"
  if [[ "$cmd" =~ ^([[:space:]]*\(?[[:space:]]*) ]]; then
    lead="${BASH_REMATCH[1]}"
    body="${cmd:${#lead}}"
  fi
  local -a tokens
  read -r -a tokens <<< "$body"
  [[ "${#tokens[@]}" -eq 0 ]] && { printf '%s' "$cmd"; return; }
  [[ "${tokens[0]}" =~ ^(command|env|nice|nohup|time|stdbuf|timeout|setsid|ionice|chrt|taskset|flock|sudo|doas)$ ]] || { printf '%s' "$cmd"; return; }
  local i=0
  while (( i < ${#tokens[@]} )); do
    [[ "${tokens[$i]}" == "git" || "${tokens[$i]}" == "gh" ]] && break
    (( i++ ))
  done
  local rest="" j
  for (( j = i; j < ${#tokens[@]}; j++ )); do
    rest+="${tokens[$j]} "
  done
  printf '%s%s' "$lead" "${rest% }"
}

_mbd_normalize() {
  printf '%s' "$1" | sed -E 's#^[[:space:]]*(\(?[[:space:]]*)?([A-Z_]+=[^[:space:]]+[[:space:]]+)+#\1#' \
                   | sed -E 's#(^|[[:space:]])(/[^[:space:]]+)?/git([[:space:]])#\1git\3#' \
                   | sed -E 's#(^|[[:space:]])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)+([[:space:]])#\1git\3#'
}

_mbd_git_c_prefix_re() {
  printf '%s' '^[[:space:]]*(\(?[[:space:]]*)?git[[:space:]]+-C[[:space:]]+[^[:space:]]+'
}
