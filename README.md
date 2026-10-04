# Consensus Git Lab Check

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Consensus%20Git%20Lab%20Check-7c3aed?logo=github)](https://github.com/marketplace/actions/consensus-git-lab-check)
[![Test](https://github.com/consensus-codes/consensus-git-lab-check/actions/workflows/test.yml/badge.svg)](https://github.com/consensus-codes/consensus-git-lab-check/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Automatically check a learner's Git/GitHub exercise and score it.** It checks
required files, commit count, branches, commit-message style, files that should
never be committed, and `.gitignore`. Then it prints a pass/fail line for each
check, writes a score table to the job summary, and exposes the score as outputs.

It's a free, drop-in **replacement for GitHub Classroom auto-grading** for Git
exercises. Classroom was retired on 28 August 2026.

- **Zero setup:** a composite action using only bash and git. No build step, no
  Docker, no external services, no secrets, no telemetry.
- **Runs anywhere:** tested on `ubuntu-latest` and `macos-latest`.
- **Config as code:** pass action inputs, or commit a `.consensus-lab.yml`
  file next to the exercise.

Made by [Consensus](https://consensus.codes/), the hands-on learning platform
where every learner gets a browser microVM to practise Linux and Git.

---

## Quick start

Add `.github/workflows/lab-check.yml` to the exercise repository:

```yaml
name: Lab check
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0          # full history: required for commit/branch checks

      - uses: consensus-codes/consensus-git-lab-check@v1
        with:
          required-files: |
            README.md
            scripts/hello.sh
          min-commits: 3
          required-branches: main, feature/greeting
          commit-message-pattern: '^(feat|fix|docs|chore)(\(.+\))?: .+'
          forbid-files: '*.log, node_modules/, .env'
          require-gitignore: true
```

On every push, the job log shows:

```text
Checks:
  ✅ PASS  Required file `README.md` - found
  ✅ PASS  Required file `scripts/hello.sh` - found
  ✅ PASS  At least 3 commit(s) - found 5
  ✅ PASS  Branch `main` - exists
  ❌ FAIL  Branch `feature/greeting` - not found
  ✅ PASS  Commit messages match `^(feat|fix|docs|chore)(\(.+\))?: .+` - all 4 non-merge commit(s) match
  ❌ FAIL  No tracked files match `*.log` - 1 committed: `debug.log`
  ✅ PASS  No tracked files match `node_modules/` - none committed
  ✅ PASS  No tracked files match `.env` - none committed
  ✅ PASS  `.gitignore` committed - 2 rule(s)

Result: FAIL - 8/10 checks passed (80%)
```

The run's **summary page** shows a **Consensus Lab Check** table with the same
results. Failed checks also show up as annotations.

> [!IMPORTANT]
> Use `actions/checkout` with `fetch-depth: 0`. The default shallow clone has
> only one commit and one branch. The action detects a shallow clone and warns
> you, but commit and branch checks can't be accurate without the full history.

## Inputs

All inputs are optional. Lists can be separated by newlines, commas, or both.
Blank items and items starting with `#` are ignored.

| Input | Default | Description |
| --- | --- | --- |
| `required-files` | *(none)* | Paths (files or directories) that must exist, relative to `working-directory`. |
| `min-commits` | `1` | Minimum number of commits reachable from `HEAD`. `0` disables the check. |
| `required-branches` | *(none)* | Branches that must exist, either locally (`refs/heads/…`) or on any remote (`refs/remotes/*/…`). |
| `commit-message-pattern` | *(none)* | [POSIX extended regex](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap09.html#tag_09_04) that the **subject line** of every non-merge commit must match. Empty means skip. Use `[0-9]`, not `\d`. |
| `forbid-files` | *(none)* | Patterns that no **tracked** file may match (see [pattern rules](#forbid-files-pattern-rules)). |
| `require-gitignore` | `false` | Require a non-empty, committed `.gitignore` at the repository root. |
| `config` | `.consensus-lab.yml` if present | Path to a config file (see below). If you set a path explicitly and the file is missing, the check fails. |
| `fail-on-error` | `true` | Fail the step when any check fails. Set to `false` to only report the score. |
| `working-directory` | `.` | Repository directory to check (relative to the workspace, or absolute). |

**Precedence:** action input, then `.consensus-lab.yml`, then the built-in default.

### `forbid-files` pattern rules

| Pattern | Matches |
| --- | --- |
| `*.log` | Any file whose **name** matches, at any depth (`debug.log`, `app/logs/x.log`). |
| `node_modules/` | Anything inside a directory with that name, at any depth. |
| `build/out/` | Anything inside exactly that path from the repository root. |
| `docs/*.tmp` | A glob on the full path from the repository root. |

Only committed (tracked) files count. Ignored, untracked files in the
workspace are fine.

## Outputs

| Output | Example | Description |
| --- | --- | --- |
| `passed` | `8` | Number of checks that passed. |
| `total` | `10` | Number of checks that ran. |
| `score` | `80` | Percentage of checks passed, as an integer from 0 to 100 (rounded down). |
| `result` | `fail` | `pass` if every check passed, otherwise `fail`. |

```yaml
      - id: lab
        uses: consensus-codes/consensus-git-lab-check@v1
        with:
          fail-on-error: false
      - run: echo "Score ${{ steps.lab.outputs.score }}% (${{ steps.lab.outputs.passed }}/${{ steps.lab.outputs.total }})"
```

## `.consensus-lab.yml`

Keep the exercise rules in the repository instead of the workflow. The action
reads `.consensus-lab.yml` from the repository root automatically. You can
also point the `config` input at another path.

```yaml
# .consensus-lab.yml
required-files:
  - README.md
  - scripts/backup.sh
  - docs/
min-commits: 5
required-branches: [main, feature/backup-script]
commit-message-pattern: '^(feat|fix|docs|refactor|test|chore)(\([a-z0-9-]+\))?: .{3,}'
forbid-files:
  - "*.log"
  - node_modules/
  - .env
require-gitignore: true
fail-on-error: true
```

The keys match the input names (`_` works in place of `-`). The parser
supports a small, safe subset of YAML with no dependencies:

- `key: value`, where values can be plain, `'single'`-quoted or `"double"`-quoted
- flow lists like `[a, b]`
- block lists (`- item`)
- `#` comments

It reads the file with the `python3` that ships on GitHub-hosted runners. A
file it can't parse fails the run with the line number. A fully commented
example is in [`examples/.consensus-lab.yml`](examples/.consensus-lab.yml).

## For teachers: replacing GitHub Classroom auto-grading

GitHub Classroom was retired on **28 August 2026**, and its auto-grading went
with it. Consensus Git Lab Check covers Git-skills assignments without any
extra service:

1. **Create a template repository** with the starter files, a
   `.consensus-lab.yml` describing the assignment, and the workflow
   [`examples/workflows/lab-check.yml`](examples/workflows/lab-check.yml).
2. **Share the template.** Each student clicks *Use this template* (or you
   create the repositories in your organisation with the GitHub CLI) and
   clones their copy.
3. **Students work as normal:** they commit, branch, push and open pull
   requests. Every push runs the check, and students get instant feedback on
   the *Actions* tab and the run summary.
4. **Collect grades.** The example workflow saves
   `{"passed":…, "total":…, "score":…, "result":…}` as a `lab-score`
   artifact on every run. Download the artifacts, or list the latest run per
   repository with `gh run list`.
5. **Show progress.** Students can add a status badge to their README:

   ```markdown
   ![Lab check](https://github.com/<owner>/<repo>/actions/workflows/lab-check.yml/badge.svg)
   ```

Typical Git assignments you can grade:

| Assignment | Configuration |
| --- | --- |
| "Make your first commits" | `min-commits: 3`, `required-files: README.md` |
| "Feature branch workflow" | `required-branches: [main, feature/login]` |
| "Conventional commits" | `commit-message-pattern: '^(feat\|fix\|docs\|chore): .+'` |
| "Clean repository" | `forbid-files: ["*.log", node_modules/, .env]`, `require-gitignore: true` |

> [!TIP]
> Students can edit any file in their repository, including the workflow and
> the config. For graded work, check that `.github/workflows/` and
> `.consensus-lab.yml` still match the template when you collect grades. You
> can also run the check from a workflow you control that checks out each
> student repository with `working-directory`.

## How it works

- `action.yml` is a composite action that runs `scripts/check.sh` with your
  inputs as environment variables.
- `scripts/check.sh` is portable bash (3.2+, so it also runs on the macOS
  system bash). It uses only `git` and standard POSIX tools.
- `scripts/parse_config.py` is a tiny YAML-subset parser that uses only the
  Python standard library.
- Nothing leaves the runner. There are no network calls, no telemetry, and no
  token is needed.

### Run it locally

```bash
cd path/to/exercise-repo
INPUT_REQUIRED_FILES="README.md" INPUT_MIN_COMMITS=3 \
  bash path/to/consensus-git-lab-check/scripts/check.sh
```

Run the test suite with `bash tests/run-tests.sh`. It builds throw-away
fixture repositories and checks both pass and fail scenarios.

## About Consensus

[**Consensus**](https://consensus.codes/) is a learning platform built around
hands-on labs. Every learner gets their own **browser-based microVM** to
practise Linux and Git/GitHub for real. There's nothing to install and no risk
of breaking a laptop. Pair it with this action: learners practise in a
Consensus lab, push their work, and get it checked automatically.

**Practise Git & Linux hands-on in a free microVM at https://consensus.codes/**

## License

[MIT](LICENSE) © 2026 Consensus
