---
name: kimera
description: >-
  Running, triaging, and gating mutation tests with kimera in a Ruby or Rails
  project. Use when running kimera, triaging surviving mutants, deciding
  whether to add a test, adding or reviewing ignore or baseline entries,
  raising max_ignored, wiring kimera into CI, or reading a kimera report.
---

# Strengthening a suite with kimera

Mutation testing audits *tests*, not code. The unit of work is one surviving
mutant, and each gets exactly one of four verdicts (see Triage). Never act to
move the score.

## Set up

```sh
bundle exec kimera init                     # detects the project, writes .kimera.yml
bundle exec kimera doctor --check-baseline  # discovery, git, and a green suite
```

- Gates: keep `max_survivors: 0`; every survivor is a decision, not a
  statistic. `max_ignored` rises only in the same diff as the entry it admits.
- Adopting on a suite with existing survivors: `kimera baseline create
  REPORT.json --reason TEXT` records them as reviewed debt, so the gate blocks
  only new holes. Burn the baseline down; never grow it to pass a gate.
- Fix line coverage first. `no_coverage` mutants are plain coverage gaps, and
  mutation results only mean something for code the tests execute.
- CI shape: **PR gate is incremental** (`kimera ci --since origin/main
  --session tmp/kimera.json`; `ci` defaults to `--max-survivors 0
  --fail-on-no-coverage`): no new surviving mutants on changed lines.
  **Full run nightly**, not per-PR.
- Exit codes: 0 pass; 1 invalid invocation or unmutated suite not green (fix
  the suite, not kimera); 2 gate failure (survivors, uncovered, ignore budget,
  or unjudged).
- The green check covers only tests that *cover* an in-scope mutant. A red
  test touching none of them is reported and excluded, so an unrelated flaky
  spec doesn't abort a per-module run.

## Operate

```sh
bundle exec kimera changed                      # changed lines only (vs origin/main)
bundle exec kimera run                          # full, per .kimera.yml
bundle exec kimera report REPORT.json --status survived
bundle exec kimera mutant ID_OR_KEY --report REPORT.json [--rerun]
bundle exec kimera run --isolated --jobs 4      # oracle mode (see Strengthen)
```

- The progress bar renders on a tty. Redirected/CI runs stay silent until the
  report, except isolated mode, which traces one verdict per line to stderr.
- `--session FILE` persists per-mutant verdicts and resumes interrupted runs.
- `--report FILE` writes the machine-readable report. Each result carries
  `mutant_id`, `key`, `status`, `file`, `line`, `operator`, and the
  `original` -> `mutated` source; don't re-parse the human log.
- Refer to a mutant by its `key` (`path:line:digest`), not its `mutant_id`.
  The ID numbers every mutant in that run, so it changes with the set of
  files scanned; the key doesn't. `kimera mutant` and `--focus` take either,
  and a key still resolves after unrelated edits move its line.
- Minitest/Rails: kimera puts `test/` (or `spec/`) on `$LOAD_PATH`, so test
  files can `require "test_helper"` without `RUBYOPT="-Itest"`.
- `--tests` on the CLI *replaces* the config `tests:` glob (it does not
  append).
- `--jobs` sizes the warm pool and isolated mirrors. Coverage-based test
  selection and kill-on-first-failure are automatic.
- A `timeout` verdict is a *detected* mutant (the suite hung on it), not an
  error. A hard-timeout verdict's `detail` holds the killed worker's thread
  backtraces: read them before deciding the mutant caused the hang.
- A red baseline blaming the hard timeout on a Rails suite with slow
  integration tests (a test that passes alone, killed under `--jobs N`): read
  the thread backtraces it prints. If the test only runs slow under load,
  raise `--hard-timeout`. If it waits on something the workers share (a Redis
  db, a lock, a port), give each worker its own through a
  `parallelize_setup`/`after_fork_hook`.
- A kill's `detail` holds the killing test's failure message and first
  frames. A state-leak warning names a test that failed in a warm worker for
  reasons unrelated to the mutant. Kimera already judged that mutant again on
  a fresh worker, but the test depends on state other tests leave behind:
  fix the test, or its teardown.
- On a Rails app that uses `parallelize`, `--jobs > 1` gives each worker its
  own database, so there's no shared-DB fixture/RLS deadlock.
- Operators: the default is the conservative core. `--operators all` enables
  the extended families; `--operators rails` (or `comparison,rails`) the
  Rails-aware ones.
- `isolated_only` marks class-body DSL mutants that only `--isolated` can
  judge. Run it for their verdicts; they never gate or count in the score.
- Rails `enum` models overlay warm (the re-declaration is idempotent), so
  their method-body mutants are judged like any other. A file labeled
  `unmutatable` could not be overlaid (a distinct, reported reason); it is not
  an `--isolated` case. Its mutants report as `unmutatable` (never gating,
  never scored, with the reason in the detail), not `no_coverage`.

## Triage a surviving mutant: the only four verdicts

1. **Real gap**: write the test. Assert the exact distinction the mutant
   erased (the `<` vs `<=` boundary, the deleted call's observable effect).
2. **Equivalent**: ignore entry, only with *both* (a) survival in an
   `--isolated` oracle run and (b) a `reason:` naming the **mechanism**
   ("IO.pipe write ends are sync; the flush is redundant"), not restating the
   verdict ("this is equivalent"). Entries without `reason:` are rejected.
3. **Dead code**: delete the code. A survivor on a branch nothing observes
   is YAGNI evidence.
4. **Wrong level**: the behavior is real but invisible to unit assertions
   (logging, fd hygiene, progress output). Cover it with an integration test
   or accept it visibly. Never stub internals just to kill a mutant; a test
   that pins the implementation makes the suite worse.

## Ignore discipline: hard rules (especially for agents)

- **Raise `max_ignored` only for an entry that has earned it**: survival
  under `--isolated`, a `reason:` naming the mechanism, and the raise in the
  same diff as the entry. Any triager, human or agent, may make that call when
  all three hold. Never raise it to make a failing gate pass; that is skipping
  triage, not finishing it.
- If any criterion is missing (no oracle run, a reason that restates the
  verdict, a mutant you haven't read), write the test or leave the survivor
  visible.
- An ignore entry without an isolated-oracle survival check is inadmissible.
  Warm-path survivors can be measurement artifacts (kimera's own suite once
  had a "clearly equivalent" mutant that 11 specs actually kill).
- Reviewers judge the `reason:`, not the number, so the entry and the raise
  land together.

## Strengthen

- Prioritize by blast radius: boundaries, money, authz, parsers, state
  machines first; CLI wiring and glue last.
- **Verify a kill by hand when in doubt**: apply the mutation to the source
  manually, run the covering tests, confirm red, restore. This catches both
  false survivors and false kills.
- Suspicious verdicts on self-referential or harness-critical code (the test
  runner, global state the suite also touches, kimera's own plumbing):
  adjudicate with `--isolated`. Suites that manipulate shared globals can
  suppress the warm path.
- `--isolated` judges on failed tests, not the exit status. A child that
  exits non-zero with zero failures (typically a SimpleCov `minimum_coverage`
  floor tripped by the partial run) is `harness_error`, not a kill, and so is
  a child that crashes before reporting (read its `detail` for the stderr).
  Kimera
  sets `KIMERA=1` wherever it loads the suite (warm, `--isolated`, doctor), so
  gate the floor on it (`minimum_coverage ... unless ENV["KIMERA"]`); `kimera
  doctor` warns when it isn't.
- A cluster of `error`/`timeout` verdicts in one region usually means harness
  fragility or a missing guard, not test strength. Read the cluster before
  counting the detections.
- Anti-patterns: chasing the score; adding tests without reading the mutant;
  white-box tests that mirror the implementation; reclassifying killable
  mutants as equivalent to end a triage session.
