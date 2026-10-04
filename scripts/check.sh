#!/usr/bin/env bash
# Consensus Git Lab Check - auto-check a learner's Git/GitHub exercise.
# https://consensus.codes/
#
# Reads its configuration from INPUT_* environment variables (set by
# action.yml) and, optionally, from a .consensus-lab.yml file. Action inputs
# take precedence over the config file; the config file takes precedence
# over built-in defaults. Pure bash + git (python3 only to read the config).
# Compatible with bash 3.2 (macOS) and later.

set -uo pipefail

FOOTER='Practise Git & Linux hands-on in a free microVM at https://consensus.codes/'
DEFAULT_CONFIG='.consensus-lab.yml'

# ----------------------------------------------------------------- helpers --

in_actions() { [ "${GITHUB_ACTIONS:-}" = "true" ]; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Split a newline- and/or comma-separated list; print one trimmed item per
# line, skipping blanks and lines starting with '#'.
split_list() {
  local item
  printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r item || [ -n "$item" ]; do
    item="$(trim "$item")"
    [ -z "$item" ] && continue
    case "$item" in \#*) continue ;; esac
    printf '%s\n' "$item"
  done
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|yes|y|on|1) return 0 ;;
    *) return 1 ;;
  esac
}

is_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|yes|y|on|1|false|no|n|off|0) return 0 ;;
    *) return 1 ;;
  esac
}

warn() {
  if in_actions; then
    printf '::warning title=Consensus Lab Check::%s\n' "$1"
  else
    printf 'WARNING: %s\n' "$1" >&2
  fi
  WARNINGS+=("$1")
}

# Join up to N lines of $2 into a comma-separated sample with "(+K more)".
sample() {
  local max="$1" list="$2" out="" n=0 total line
  total=$(printf '%s\n' "$list" | grep -c . || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    n=$((n + 1))
    [ "$n" -gt "$max" ] && break
    out="${out:+$out, }\`$line\`"
  done <<<"$list"
  [ "$total" -gt "$max" ] && out="$out (+$((total - max)) more)"
  printf '%s' "$out"
}

NAMES=(); STATUSES=(); DETAILS=(); WARNINGS=()

record() { # record pass|fail "check name" "details"
  STATUSES+=("$1"); NAMES+=("$2"); DETAILS+=("$3")
  if [ "$1" = "pass" ]; then
    printf '  \xe2\x9c\x85 PASS  %s - %s\n' "$2" "$3"
  else
    printf '  \xe2\x9d\x8c FAIL  %s - %s\n' "$2" "$3"
    if in_actions; then
      printf '::error title=Consensus Lab Check: %s::%s\n' "$2" "$3"
    fi
  fi
}

md_escape() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# ------------------------------------------------------------ read inputs --

IN_REQUIRED_FILES="${INPUT_REQUIRED_FILES:-}"
IN_MIN_COMMITS="$(trim "${INPUT_MIN_COMMITS:-}")"
IN_REQUIRED_BRANCHES="${INPUT_REQUIRED_BRANCHES:-}"
IN_COMMIT_PATTERN="${INPUT_COMMIT_MESSAGE_PATTERN:-}"
IN_FORBID_FILES="${INPUT_FORBID_FILES:-}"
IN_REQUIRE_GITIGNORE="$(trim "${INPUT_REQUIRE_GITIGNORE:-}")"
IN_FAIL_ON_ERROR="$(trim "${INPUT_FAIL_ON_ERROR:-}")"
IN_CONFIG="$(trim "${INPUT_CONFIG:-}")"

CFG_REQUIRED_FILES=""; CFG_MIN_COMMITS=""; CFG_REQUIRED_BRANCHES=""
CFG_COMMIT_PATTERN=""; CFG_FORBID_FILES=""; CFG_REQUIRE_GITIGNORE=""
CFG_FAIL_ON_ERROR=""

echo "Consensus Lab Check"
echo "==================="

# ------------------------------------------------------------ config file --

CONFIG_USED=""
CONFIG_ERROR=""
if [ -n "$IN_CONFIG" ]; then
  config_path="$IN_CONFIG"; config_explicit=1
else
  config_path="$DEFAULT_CONFIG"; config_explicit=0
fi

if [ -f "$config_path" ]; then
  PY=""
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
  done
  if [ -z "$PY" ]; then
    CONFIG_ERROR="python3 is required to read $config_path but was not found"
  else
    tmp="$(mktemp "${TMPDIR:-/tmp}/consensus-lab.XXXXXX")"
    if "$PY" "$(dirname "$0")/parse_config.py" "$config_path" >"$tmp" 2>"$tmp.err"; then
      while IFS= read -r -d '' key && IFS= read -r -d '' val; do
        case "$key" in
          required-files)         CFG_REQUIRED_FILES="$val" ;;
          min-commits)            CFG_MIN_COMMITS="$(trim "$val")" ;;
          required-branches)      CFG_REQUIRED_BRANCHES="$val" ;;
          commit-message-pattern) CFG_COMMIT_PATTERN="$val" ;;
          forbid-files)           CFG_FORBID_FILES="$val" ;;
          require-gitignore)      CFG_REQUIRE_GITIGNORE="$(trim "$val")" ;;
          fail-on-error)          CFG_FAIL_ON_ERROR="$(trim "$val")" ;;
        esac
      done <"$tmp"
      CONFIG_USED="$config_path"
      while IFS= read -r line; do [ -n "$line" ] && warn "$config_path: ${line#warning: }"; done <"$tmp.err"
    else
      CONFIG_ERROR="$(cat "$tmp.err")"
      [ -z "$CONFIG_ERROR" ] && CONFIG_ERROR="could not parse $config_path"
    fi
    rm -f "$tmp" "$tmp.err"
  fi
elif [ "$config_explicit" = 1 ]; then
  CONFIG_ERROR="config file '$config_path' not found"
fi

pick() { if [ -n "$1" ]; then printf '%s' "$1"; elif [ -n "$2" ]; then printf '%s' "$2"; else printf '%s' "$3"; fi; }

REQUIRED_FILES="$(pick "$IN_REQUIRED_FILES" "$CFG_REQUIRED_FILES" "")"
MIN_COMMITS="$(pick "$IN_MIN_COMMITS" "$CFG_MIN_COMMITS" "1")"
REQUIRED_BRANCHES="$(pick "$IN_REQUIRED_BRANCHES" "$CFG_REQUIRED_BRANCHES" "")"
COMMIT_PATTERN="$(pick "$IN_COMMIT_PATTERN" "$CFG_COMMIT_PATTERN" "")"
FORBID_FILES="$(pick "$IN_FORBID_FILES" "$CFG_FORBID_FILES" "")"
REQUIRE_GITIGNORE="$(pick "$IN_REQUIRE_GITIGNORE" "$CFG_REQUIRE_GITIGNORE" "false")"
FAIL_ON_ERROR="$(pick "$IN_FAIL_ON_ERROR" "$CFG_FAIL_ON_ERROR" "true")"

if [ -n "$CONFIG_USED" ]; then
  echo "Config:    $CONFIG_USED"
fi
echo "Directory: $(pwd)"
echo

# ------------------------------------------------------------------ checks --

IS_REPO=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_REPO=1
fi

HAS_HEAD=0
if [ "$IS_REPO" = 1 ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  HAS_HEAD=1
fi

SHALLOW=0
if [ "$IS_REPO" = 1 ]; then
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] ||
     [ -f "$(git rev-parse --git-dir 2>/dev/null)/shallow" ]; then
    SHALLOW=1
    warn "Shallow clone detected: commit history is incomplete, so commit counts and commit-message checks may be wrong. Use actions/checkout with 'fetch-depth: 0'."
  fi
fi

echo "Checks:"

if [ -n "$CONFIG_ERROR" ]; then
  record fail "Config file" "$CONFIG_ERROR"
fi

if [ "$IS_REPO" = 0 ]; then
  record fail "Git repository" "$(pwd) is not a Git repository (did you run actions/checkout?)"
elif [ "$HAS_HEAD" = 0 ]; then
  record fail "Git repository" "repository has no commits yet"
fi

# 1. Required files ----------------------------------------------------------
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -e "$f" ]; then
    record pass "Required file \`$f\`" "found"
  else
    record fail "Required file \`$f\`" "missing"
  fi
done <<<"$(split_list "$REQUIRED_FILES")"

# 2. Minimum commits ---------------------------------------------------------
case "$MIN_COMMITS" in
  ''|*[!0-9]*)
    record fail "At least $MIN_COMMITS commit(s)" "invalid min-commits value '$MIN_COMMITS' (expected a whole number)" ;;
  *)
    if [ "$MIN_COMMITS" -gt 0 ]; then
      count=0
      [ "$HAS_HEAD" = 1 ] && count="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
      note=""
      [ "$SHALLOW" = 1 ] && note=" (shallow clone - history may be truncated)"
      if [ "$count" -ge "$MIN_COMMITS" ]; then
        record pass "At least $MIN_COMMITS commit(s)" "found $count$note"
      else
        record fail "At least $MIN_COMMITS commit(s)" "found $count$note"
      fi
    fi ;;
esac

# 3. Required branches -------------------------------------------------------
branch_exists() {
  [ "$IS_REPO" = 1 ] || return 1
  git show-ref --verify --quiet "refs/heads/$1" && return 0
  [ -n "$(git for-each-ref --format='%(refname)' "refs/remotes/*/$1" 2>/dev/null)" ] && return 0
  return 1
}
while IFS= read -r b; do
  [ -z "$b" ] && continue
  if branch_exists "$b"; then
    record pass "Branch \`$b\`" "exists"
  else
    hint=""
    [ "$SHALLOW" = 1 ] && hint=" (shallow clones fetch only one branch - use fetch-depth: 0)"
    record fail "Branch \`$b\`" "not found$hint"
  fi
done <<<"$(split_list "$REQUIRED_BRANCHES")"

# 4. Commit message pattern ---------------------------------------------------
if [ -n "$COMMIT_PATTERN" ]; then
  name="Commit messages match \`$COMMIT_PATTERN\`"
  re_rc=0
  # shellcheck disable=SC2319  # we want the [[ ]] status: 2 = invalid regex
  [[ "" =~ $COMMIT_PATTERN ]] || re_rc=$?
  if [ "$re_rc" -eq 2 ]; then
    record fail "$name" "invalid regular expression (POSIX ERE expected)"
  elif [ "$HAS_HEAD" = 0 ]; then
    record fail "$name" "no commits to check"
  else
    bad=""; checked=0
    while IFS=$'\t' read -r sha subject; do
      [ -z "$sha" ] && continue
      checked=$((checked + 1))
      if ! [[ "$subject" =~ $COMMIT_PATTERN ]]; then
        bad="${bad}${sha} ${subject}"$'\n'
      fi
    done <<<"$(git log --no-merges --format='%h%x09%s' HEAD)"
    if [ -z "$bad" ]; then
      record pass "$name" "all $checked non-merge commit(s) match"
    else
      nbad=$(printf '%s' "$bad" | grep -c .)
      record fail "$name" "$nbad of $checked commit(s) do not match: $(sample 3 "$bad")"
    fi
  fi
fi

# 5. Forbidden files -----------------------------------------------------------
TRACKED=""
if [ "$IS_REPO" = 1 ]; then
  TRACKED="$(git ls-files 2>/dev/null)"
fi

# Pattern rules:  'dir/' -> a directory with that name anywhere (or that path
# if it contains a '/'), 'a/b*.txt' -> glob on the full path,
# '*.log' -> glob on the file name at any depth.
# shellcheck disable=SC2254  # patterns are intentionally unquoted globs
matches_pattern() { # path pattern
  local p="$1" pat="${2#/}" d base
  case "$pat" in
    */)
      d="${pat%/}"
      case "$d" in
        */*) case "$p" in $d/*) return 0 ;; esac ;;
        *)   case "$p" in $d/*|*/$d/*) return 0 ;; esac ;;
      esac ;;
    */*)
      case "$p" in $pat) return 0 ;; esac ;;
    *)
      base="${p##*/}"
      case "$base" in $pat) return 0 ;; esac ;;
  esac
  return 1
}

while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  hits=""
  if [ -n "$TRACKED" ]; then
    while IFS= read -r path; do
      if matches_pattern "$path" "$pat"; then hits="${hits}${path}"$'\n'; fi
    done <<<"$TRACKED"
  fi
  if [ -z "$hits" ]; then
    record pass "No tracked files match \`$pat\`" "none committed"
  else
    nhits=$(printf '%s' "$hits" | grep -c .)
    record fail "No tracked files match \`$pat\`" "$nhits committed: $(sample 3 "$hits")"
  fi
done <<<"$(split_list "$FORBID_FILES")"

# 6. .gitignore -----------------------------------------------------------------
if ! is_bool "$REQUIRE_GITIGNORE"; then
  record fail "\`.gitignore\` committed" "invalid require-gitignore value '$REQUIRE_GITIGNORE' (expected true/false)"
elif is_true "$REQUIRE_GITIGNORE"; then
  top="."
  [ "$IS_REPO" = 1 ] && top="$(git rev-parse --show-toplevel)"
  gi="$top/.gitignore"
  if [ ! -f "$gi" ]; then
    record fail "\`.gitignore\` committed" "no .gitignore at the repository root"
  elif ! grep -qv -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$gi"; then
    record fail "\`.gitignore\` committed" ".gitignore has no ignore rules"
  elif ! (cd "$top" && git ls-files --error-unmatch .gitignore >/dev/null 2>&1); then
    record fail "\`.gitignore\` committed" ".gitignore exists but is not committed"
  else
    rules=$(grep -cv -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$gi")
    record pass "\`.gitignore\` committed" "$rules rule(s)"
  fi
fi

# ----------------------------------------------------------------- results --

TOTAL=${#STATUSES[@]}
PASSED=0
for s in ${STATUSES[@]+"${STATUSES[@]}"}; do
  [ "$s" = "pass" ] && PASSED=$((PASSED + 1))
done
if [ "$TOTAL" -gt 0 ]; then SCORE=$((PASSED * 100 / TOTAL)); else SCORE=100; fi
if [ "$PASSED" -eq "$TOTAL" ]; then RESULT=pass; else RESULT=fail; fi

echo
if [ "$RESULT" = pass ]; then
  echo "Result: PASS - $PASSED/$TOTAL checks passed ($SCORE%)"
else
  echo "Result: FAIL - $PASSED/$TOTAL checks passed ($SCORE%)"
fi
echo
echo "$FOOTER"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "passed=$PASSED"
    echo "total=$TOTAL"
    echo "score=$SCORE"
    echo "result=$RESULT"
  } >>"$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Consensus Lab Check"
    echo
    if [ "$RESULT" = pass ]; then
      echo "**Result: :white_check_mark: PASS** - $PASSED/$TOTAL checks passed (**$SCORE%**)"
    else
      echo "**Result: :x: FAIL** - $PASSED/$TOTAL checks passed (**$SCORE%**)"
    fi
    echo
    echo "| Status | Check | Details |"
    echo "| :---: | --- | --- |"
    i=0
    while [ "$i" -lt "$TOTAL" ]; do
      if [ "${STATUSES[$i]}" = pass ]; then icon=":white_check_mark: Pass"; else icon=":x: Fail"; fi
      echo "| $icon | $(md_escape "${NAMES[$i]}") | $(md_escape "${DETAILS[$i]}") |"
      i=$((i + 1))
    done
    echo
    for w in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
      echo "> :warning: $(md_escape "$w")"
      echo
    done
    [ -n "$CONFIG_USED" ] && { echo "<sub>Config: \`$CONFIG_USED\`</sub>"; echo; }
    echo "---"
    echo "$FOOTER"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$RESULT" = fail ]; then
  if is_true "$FAIL_ON_ERROR"; then
    exit 1
  fi
  echo "fail-on-error is false: not failing the job."
fi
exit 0
