#!/usr/bin/env bash
# Local test-suite: builds fixture repos and runs scripts/check.sh against
# them with INPUT_* variables, exactly as action.yml does.
#   usage: tests/run-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/consensus-lab-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
bash "$ROOT/tests/make-fixtures.sh" "$WORK/fx" >/dev/null || { echo "fixture build failed"; exit 1; }

PASSES=0; FAILS=0
ok()  { PASSES=$((PASSES + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAILS=$((FAILS + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }

# run FIXTURE [VAR=value ...] -> sets RC, OUT (log), OUTPUTS, SUMMARY
run() {
  local fixture="$1"; shift
  : >"$WORK/outputs"; : >"$WORK/summary"
  OUT="$(cd "$WORK/fx/$fixture" && env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
        GITHUB_OUTPUT="$WORK/outputs" GITHUB_STEP_SUMMARY="$WORK/summary" \
        "$@" bash "$CHECK" 2>&1)"
  RC=$?
  OUTPUTS="$(cat "$WORK/outputs")"; SUMMARY="$(cat "$WORK/summary")"
}
out() { printf '%s\n' "$OUTPUTS" | sed -n "s/^$1=//p"; }

expect() { # description condition...
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc" "rc=$RC outputs: $(echo "$OUTPUTS" | tr '\n' ' ')
$OUT"; fi
}
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

FULL=(
  "INPUT_REQUIRED_FILES=README.md, src/hello.sh"
  "INPUT_MIN_COMMITS=3"
  "INPUT_REQUIRED_BRANCHES=main
feature/greeting"
  "INPUT_COMMIT_MESSAGE_PATTERN=^(feat|fix|docs|chore)(\(.+\))?: .+"
  "INPUT_FORBID_FILES=*.log,node_modules/"
  "INPUT_REQUIRE_GITIGNORE=true"
)

echo "== passing exercise (inputs)"
run pass "${FULL[@]}"
expect "exit code 0"                  [ "$RC" = 0 ]
expect "result=pass"                  [ "$(out result)" = pass ]
expect "9/9 checks, score 100"        [ "$(out passed)/$(out total)/$(out score)" = "9/9/100" ]
expect "merge commit skipped (4 non-merge commits checked)" has "$OUT" "all 4 non-merge commit(s) match"
expect "untracked ignored .log is not flagged" has "$OUT" "No tracked files match \`*.log\` - none committed"
expect "summary has title"            has "$SUMMARY" "## Consensus Lab Check"
expect "summary has table header"     has "$SUMMARY" "| Status | Check | Details |"
expect "summary has footer"           has "$SUMMARY" "Practise Git & Linux hands-on in a free microVM at https://consensus.codes/"
expect "log has footer"               has "$OUT" "Practise Git & Linux hands-on in a free microVM at https://consensus.codes/"

echo "== failing exercise (inputs, fail-on-error default)"
run fail "${FULL[@]}"
expect "exit code 1"                  [ "$RC" = 1 ]
expect "result=fail"                  [ "$(out result)" = fail ]
expect "1/9 checks (only branch main), score 11" [ "$(out passed)/$(out total)/$(out score)" = "1/9/11" ]
expect "missing README reported"      has "$OUT" "FAIL  Required file \`README.md\` - missing"
expect "too few commits reported"     has "$OUT" "FAIL  At least 3 commit(s) - found 1"
expect "missing branch reported"      has "$OUT" "FAIL  Branch \`feature/greeting\` - not found"
expect "bad commit message reported"  has "$OUT" "1 of 1 commit(s) do not match"
expect "committed log reported"       has "$OUT" "\`debug.log\`"
expect "committed node_modules reported" has "$OUT" "\`node_modules/left-pad/index.js\`"
expect "missing .gitignore reported"  has "$OUT" "no .gitignore at the repository root"
expect "summary shows FAIL"           has "$SUMMARY" "FAIL"

echo "== failing exercise with fail-on-error=false"
run fail "${FULL[@]}" "INPUT_FAIL_ON_ERROR=false"
expect "exit code 0"                  [ "$RC" = 0 ]
expect "result=fail still reported"   [ "$(out result)" = fail ]

echo "== partial score"
run fail "INPUT_REQUIRED_FILES=hello.sh,README.md" "INPUT_FAIL_ON_ERROR=false"
expect "2/3 checks, score 66"         [ "$(out passed)/$(out total)/$(out score)" = "2/3/66" ]

echo "== defaults only"
run fail
expect "only min-commits=1 runs and passes" [ "$(out passed)/$(out total)/$(out result)" = "1/1/pass" ]

echo "== config file (.consensus-lab.yml auto-detected)"
run config
expect "exit code 0"                  [ "$RC" = 0 ]
expect "all 9 config checks pass"     [ "$(out passed)/$(out total)" = "9/9" ]
expect "config path logged"           has "$OUT" "Config:    .consensus-lab.yml"
expect "flow list parsed (feature/greeting)" has "$OUT" "Branch \`feature/greeting\`"
expect "quoted regex parsed"          has "$OUT" "match \`^(feat|fix|docs|chore)(\\(.+\\))?: .+\`"
expect "'yes' accepted for require-gitignore" has "$OUT" "PASS  \`.gitignore\` committed"

echo "== inputs override config"
run config "INPUT_MIN_COMMITS=99" "INPUT_FAIL_ON_ERROR=false"
expect "min-commits from input wins"  has "$OUT" "FAIL  At least 99 commit(s)"
expect "other keys still from config" [ "$(out total)" = 9 ]

echo "== explicit config path"
cp "$ROOT/tests/fixtures/lab.consensus-lab.yml" "$WORK/fx/pass/custom.yml"
run pass "INPUT_CONFIG=custom.yml"
expect "custom config used, 9/9"      [ "$(out passed)/$(out total)" = "9/9" ]
run pass "INPUT_CONFIG=does-not-exist.yml"
expect "missing explicit config fails" [ "$RC" = 1 ]
expect "missing explicit config message" has "$OUT" "config file 'does-not-exist.yml' not found"

echo "== broken config"
run broken-config
expect "parse error fails the run"    [ "$RC" = 1 ]
expect "error names the line"         has "$OUT" "line 2"

echo "== shallow clone"
run shallow "INPUT_REQUIRED_BRANCHES=feature/greeting" "INPUT_FAIL_ON_ERROR=false"
expect "shallow warning printed"      has "$OUT" "Shallow clone detected"
expect "warning in summary"           has "$SUMMARY" "Shallow clone detected"
expect "branch hint mentions fetch-depth" has "$OUT" "use fetch-depth: 0"
run shallow "GITHUB_ACTIONS=true"
expect "::warning annotation in Actions" has "$OUT" "::warning title=Consensus Lab Check::Shallow clone"

echo "== not a git repository"
run not-a-repo "INPUT_REQUIRED_FILES=README.md"
expect "exit code 1"                  [ "$RC" = 1 ]
expect "clear message"                has "$OUT" "is not a Git repository"

echo "== invalid values"
run pass "INPUT_COMMIT_MESSAGE_PATTERN=([unclosed" "INPUT_FAIL_ON_ERROR=false"
expect "invalid regex is a failed check" has "$OUT" "invalid regular expression"
run pass "INPUT_MIN_COMMITS=three" "INPUT_FAIL_ON_ERROR=false"
expect "invalid min-commits is a failed check" has "$OUT" "invalid min-commits value 'three'"
run pass "INPUT_REQUIRE_GITIGNORE=maybe" "INPUT_FAIL_ON_ERROR=false"
expect "invalid require-gitignore is a failed check" has "$OUT" "invalid require-gitignore value 'maybe'"
run fail "GITHUB_ACTIONS=true" "INPUT_REQUIRED_FILES=README.md" "INPUT_FAIL_ON_ERROR=false"
expect "::error annotation in Actions" has "$OUT" "::error title=Consensus Lab Check: Required file"

echo "== forbid-files pattern rules"
(
  cd "$WORK/fx/pass" &&
  mkdir -p build/out docs/build && : >build/out/a.o && : >docs/build/x && : >docs/notes.tmp &&
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t add -f . >/dev/null &&
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@t commit -qm "chore: artefacts"
)
run pass "INPUT_FORBID_FILES=docs/build/" "INPUT_FAIL_ON_ERROR=false"
expect "anchored dir pattern matches only that path" has "$OUT" "1 committed: \`docs/build/x\`"
run pass "INPUT_FORBID_FILES=build/" "INPUT_FAIL_ON_ERROR=false"
expect "bare dir pattern matches at any depth" has "$OUT" "2 committed"
run pass "INPUT_FORBID_FILES=*.tmp" "INPUT_FAIL_ON_ERROR=false"
expect "basename glob matches nested file" has "$OUT" "\`docs/notes.tmp\`"
run pass "INPUT_FORBID_FILES=docs/*.tmp" "INPUT_FAIL_ON_ERROR=false"
expect "path glob matches" has "$OUT" "\`docs/notes.tmp\`"
run pass "INPUT_FORBID_FILES=*.exe" 
expect "non-matching pattern passes" [ "$RC" = 0 ]

echo "== config parser"
cat >"$WORK/p.yml" <<'YML'
---
# comment
required-files: [ "a b.txt", 'it''s', c ]   # trailing comment
commit-message-pattern: "^x #not-a-comment"
forbid-files:
  - "*.log"
  - dist/
unknown-key: 1
YML
parsed="$(python3 "$ROOT/scripts/parse_config.py" "$WORK/p.yml" 2>"$WORK/p.err" | tr '\0' '|')"
expect "flow list with quotes" has "$parsed" "required-files|a b.txt
it's
c|"
expect "hash inside quotes kept" has "$parsed" "commit-message-pattern|^x #not-a-comment|"
expect "block list" has "$parsed" "forbid-files|*.log
dist/|"
expect "unknown key warned" has "$(cat "$WORK/p.err")" "unknown key 'unknown-key'"

echo
echo "Passed: $PASSES  Failed: $FAILS"
[ "$FAILS" -eq 0 ]
