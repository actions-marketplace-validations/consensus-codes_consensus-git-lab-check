#!/usr/bin/env bash
# Build throw-away Git repositories used to exercise the action.
#   usage: tests/make-fixtures.sh DEST_DIR
# Creates: DEST/pass  DEST/fail  DEST/config  DEST/shallow  DEST/broken-config
#          DEST/not-a-repo
# shellcheck disable=SC2016  # literal $1 / backticks are written into fixture files
set -euo pipefail

DEST="${1:?usage: make-fixtures.sh DEST_DIR}"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$DEST"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

export GIT_AUTHOR_NAME="Lab Learner" GIT_AUTHOR_EMAIL="learner@example.com"
export GIT_COMMITTER_NAME="Lab Learner" GIT_COMMITTER_EMAIL="learner@example.com"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

new_repo() { mkdir -p "$1" && (cd "$1" && g init -q); }

# --- pass: a well-formed exercise -------------------------------------------
build_good() {
  local dir="$1"
  new_repo "$dir"
  (
    cd "$dir"
    printf '# My Git lab\n' >README.md
    printf '*.log\nnode_modules/\n' >.gitignore
    g add . && g commit -q -m "chore: initial commit"
    mkdir -p src && printf '#!/bin/sh\necho hello\n' >src/hello.sh
    g add . && g commit -q -m "feat: add hello script"
    g checkout -q -b feature/greeting
    printf '#!/bin/sh\necho "hello, $1"\n' >src/hello.sh
    g commit -q -am "feat(greeting): greet by name"
    g checkout -q main
    printf '\nRun `src/hello.sh`.\n' >>README.md
    g commit -q -am "docs: usage"
    # a real merge commit; its default message is ignored by the pattern check
    g merge -q --no-ff --no-edit feature/greeting
    printf 'debug\n' >ignored.log   # untracked + ignored: must not be flagged
  )
}
build_good "$DEST/pass"

# --- fail: common learner mistakes -------------------------------------------
new_repo "$DEST/fail"
(
  cd "$DEST/fail"
  mkdir -p node_modules/left-pad
  printf 'module.exports = 1\n' >node_modules/left-pad/index.js
  printf 'oops\n' >debug.log
  printf 'echo hi\n' >hello.sh
  g add . && g commit -q -m "wip"
)

# --- config: well-formed exercise configured via .consensus-lab.yml ----------
build_good "$DEST/config"
cp "$HERE/fixtures/lab.consensus-lab.yml" "$DEST/config/.consensus-lab.yml"
(cd "$DEST/config" && g add .consensus-lab.yml && g commit -q -m "chore: add lab config")

# --- shallow: depth-1 clone of the good repo ----------------------------------
g clone -q --depth 1 "file://$DEST/pass" "$DEST/shallow"

# --- broken-config: unparsable .consensus-lab.yml -----------------------------
build_good "$DEST/broken-config"
cp "$HERE/fixtures/broken.consensus-lab.yml" "$DEST/broken-config/.consensus-lab.yml"

# --- not-a-repo -----------------------------------------------------------------
mkdir -p "$DEST/not-a-repo"
printf 'not tracked\n' >"$DEST/not-a-repo/README.md"

echo "Fixtures created in $DEST"
