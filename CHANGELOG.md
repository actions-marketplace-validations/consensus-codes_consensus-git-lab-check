# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-04

### Added
- First release of **Consensus Git Lab Check**, a composite GitHub Action
  (bash + git only; no build step, no external services, no telemetry, no secrets).
- Checks: required files, minimum commit count, required branches,
  commit-message regex for every non-merge commit, forbidden tracked files,
  committed `.gitignore`.
- Optional `.consensus-lab.yml` config file (action inputs take precedence).
- Shallow-clone detection with a clear warning and `fetch-depth: 0` hint.
- Per-check PASS/FAIL log lines, `::error`/`::warning` annotations and a
  Markdown table in the job summary titled "Consensus Lab Check".
- Outputs: `passed`, `total`, `score` (percent) and `result` (`pass`/`fail`).
- `fail-on-error` switch and `working-directory` input.
- Self-test workflow on `ubuntu-latest` and `macos-latest` covering pass and fail fixtures.

[Unreleased]: https://github.com/consensus-codes/consensus-git-lab-check/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/consensus-codes/consensus-git-lab-check/releases/tag/v1.0.0
