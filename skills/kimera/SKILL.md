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
  --reason TEXT --write` records the last report's survivors as reviewed debt
  and sets `baseline:` in .kimera.yml, so the gate blocks only new holes. Burn
  the baseline down; never grow it to pass a gate.
- Fix line coverage first. `no_coverage` mutants are plain coverage gaps, and
  mutation results only mean something for code the tests execute. By default
  (`count_no_coverage: true`) each scores as not killed and fails the gate in
  every command, `kimera run` included; untested code is not passing code.
  Write the test that runs the code; don't set `count_no_coverage: false` to
  pass a gate.
- CI shape: **PR gate is incremental** (`kimera ci --session tmp/kimera.json`;
  `ci` defaults to `--max-survivors 0 --fail-on-no-coverage`, and on a pull
  request to `--since` its base (`KIMERA_BASE`, or GitHub's, GitLab's or
  Buildkite's base-branch variable) and on GitHub to `--summary
  $GITHUB_STEP_SUMMARY`): no new surviving mutants on changed lines. With no
  base, ci says so and runs a full run, which leaves `isolated_only` DSL
  unjudged and ungated. **Full run nightly**, not per-PR. On a big suite,
  `--reuse-coverage` on both keeps the full run's coverage map and lets the
  PR run rerun only the baseline tests that reach its changed files; when a
  test, support or config file changed it says so and measures every test.
- Exit codes: 0 pass; 1 invalid invocation or unmutated suite not green (fix
  the suite, not kimera); 2 gate failure (survivors, uncovered, ignore budget,
  or unjudged).
- The green check covers only tests that *cover* an in-scope mutant. A test
  that fails in the baseline is rerun plainly: if it passes there, the run
  stops with a harness error naming it (kimera, not the test, is at fault:
  report it, or try `--jobs 1`); if it fails plainly too and touched no
  in-scope mutant, it is excluded, its coverage unknown, so an unrelated red
  spec doesn't abort a per-module run.
- A run that deletes or rewrites tracked files (a mutant pointing a cleaner
  at the wrong directory) fails with exit 1, naming them: restore them, and
  judge such code with `--isolated`, which works on a copy.
- A red baseline that says `ran on N workers`: rerun with `--jobs 1`. Green
  there means the tests share a directory, file or port between workers, not
  that they are broken. Give each test its own (`Dir.mktmpdir`, a free port)
  or keep `jobs: 1`; `doctor --check-baseline` flags this before a run when
  `jobs:` is over 1.

## Operate

```sh
bundle exec kimera changed                      # changed lines only (vs origin/main)
bundle exec kimera run                          # full, per .kimera.yml
bundle exec kimera run app/models/order.rb:40-60  # only those lines (or :42)
bundle exec kimera run app --method total       # only inside methods named total
bundle exec kimera report --status survived     # reads tmp/kimera/report.json
bundle exec kimera mutant ID_OR_KEY [--rerun]   # one mutant: diff, source, tests
bundle exec kimera run --isolated --jobs 4      # oracle mode (see Strengthen)
```

- Progress goes to stderr: a bar on a tty; redirected/CI runs get a plain
  `kimera: <phase> done/total …` line per phase start, at most every 30s, and at
  the end. `--no-progress` silences it.
- `--session FILE` persists per-mutant verdicts and resumes interrupted runs.
- Every run writes the machine-readable report to tmp/kimera/report.json
  (`--report FILE` moves it, `--no-report` skips it), and `kimera report` and
  `kimera mutant` read it by default. Each result carries `mutant_id`, `key`,
  `status`, `file`, `line`, `column`, `method`, `operator`, the `original` ->
  `mutated` source, and `covering_tests`/`failing_tests` ids; the report's
  `tests` section names each id (`name`, `location` as file:line). Don't
  re-parse the human log.
- A path target that matches no mutant fails with the lines and methods that
  do have mutants: aim again from that list.
- Refer to a mutant by its `key` (`path:line:digest`), not its `mutant_id`.
  The ID numbers every mutant in that run, so it changes with the set of
  files scanned; the key doesn't. `kimera mutant` and `--focus` take either,
  and a key still resolves after unrelated edits move its line.
- Minitest/Rails: kimera puts each test file's nearest `test/` or `spec/`,
  the project's own `test/` and `spec/`, and any `load_path:` folders on
  `$LOAD_PATH`, so test files can `require "test_helper"` without
  `RUBYOPT="-Itest"`. `kimera doctor` and every printed "reproduce without
  kimera" command use the same `-I` flags.
- `--tests` on the CLI *replaces* the config `tests:` glob (it does not
  append). A narrowed run's verdicts hold only for the narrowed set: a
  survivor may be killed by a test left out, so confirm it with the full glob
  before writing a test or an ignore entry. The report flags such a run
  (`narrowed run: ...`, `"narrowed": true` in the JSON `run` section). Its
  uncovered mutants read "not covered by the narrowed tests" and are neither
  scored nor gated on; confirm them with the full glob too.
- `tests:` patterns load in the order listed: put a helper the runner
  preloads (Rake's `-r`) first, e.g. `tests: [test/helper.rb,
  "test/**/*_test.rb"]`.
- `--jobs` sizes the warm pool and isolated mirrors. Coverage-based test
  selection and kill-on-first-failure are automatic.
- A `timeout` verdict is a *detected* mutant (the suite hung on it), not an
  error. Both timeouts time one covering test at a time, so a timeout means a
  single test ran long under the mutant. A hard-timeout verdict's `detail`
  holds the killed worker's thread backtraces: read them before deciding the
  mutant caused the hang.
- A `timeout` whose `detail` says a test "ran past its relative time budget"
  passed, but took over 10 × its baseline time + 1s, twice with the mutant on,
  and kept to it with the mutant off. The mutant made that test slow (a
  deleted shutdown, a dropped cache). Tune with `--timeout-factor` and
  `--timeout-slack`; `--no-relative-timeout` (`relative_timeout: false`) turns
  it off.
- A red baseline blaming the hard timeout on a Rails suite with slow
  integration tests (a test that passes alone, killed under `--jobs N`): read
  the thread backtraces it prints. If the test only runs slow under load,
  raise `--hard-timeout`. If it waits on something the workers share (a Redis
  db, a lock, a port), give each worker its own through a
  `parallelize_setup`/`after_fork_hook`.
- Each test's soft limit is `--soft-timeout` or its baseline × 3 + 1s,
  whichever is longer (under the hard watchdog). A test that runs past it with
  the mutant on is a `timeout` only when, alone with the mutant off, it passes
  in under half that limit. A mutant left unjudged with a detail saying the test "ran past the
  soft timeout ... with it off" means the test is too slow (or broken) on its
  own: raise `--soft-timeout` well above its time, or fix the test.
- Code under test that calls `exit` or `abort` fails that test (`detail`:
  `SystemExit: exit(1) called from FILE:LINE`), so a mutant that makes a test
  abort is `killed`, not `harness_error`.
- A `harness_error` from a dead worker says how it died (`died on signal 15
  (SIGTERM)`, `exited 1`) and the exception it died of, with frames. A test
  that signals its own process with nothing trapping the signal ends the
  worker, as it would end `rails test`: trap it in the test, or leave the test
  out with `--exclude-test` (its file) or `--exclude-test-name REGEX` (that
  test alone).
- A kill's `detail` holds the killing test's failure message and first
  frames. Every baseline test and every mutant runs in a process forked from
  one no test has run in, so a cache or flag another test left can't decide
  a verdict; don't add resets to the suite to please kimera.
- A mutant the warm pass can't judge (its process died; or its only failing
  test also fails without it after the tests run before it) is judged again
  in a fresh isolated mirror of its own, against its covering tests, and so
  is a warm survivor whose method also ran while the suite loaded (against
  the tests in the files that cover its source file). Its report row carries
  that verdict plus a `note` with the warm detail. It stays `harness_error`
  only if the tests also fail in a fresh mirror without the mutant.
  `--no-rejudge` (`rejudge: false`) turns this off.
- On incremental runs (`--since`, `ci`, `changed`) each warm survivor's
  covering tests also run alone in a fresh process (`confirm_survivors`), so
  an earlier test's state can't mask a kill; a kill found that way says
  "failed alone in a fresh process". Turn it on for a full run with
  `--confirm-survivors` when a library has lazy registries or run-once guards.
- `unjudged` in the text report and gate is the JSON status `harness_error`;
  `kimera report --status unjudged` lists them.
- "Not mutated" (`unmutated` in the JSON report) lists code the scan holds
  no mutant for, with the reason: a block outside any method that isn't
  `define_method`/`lambda`/`proc`, or a file that does not parse. It is not a
  survivor; it's a place no verdict covers.
- On a Rails app that uses `parallelize`, `--jobs > 1` gives each worker its
  own database, so there's no shared-DB fixture/RLS deadlock. With no schema
  file to load (a suite that migrates as it loads), each worker and mirror
  gets a copy of the parent's PostgreSQL or SQLite database; on another
  adapter kimera says the workers share one.
- Operators: the default is the conservative core. `--operators all` enables
  the extended families; `--operators rails` (or `comparison,rails`) the
  Rails-aware ones.
- `attribution: unit` (`--attribution unit`) lets only a unit's own tests
  (`spec/models/order_spec.rb` for `app/models/order.rb`, plus `unit_tests:`
  rules) kill its mutants. `uncovered_by_unit` means only other units' tests
  (request, integration) reach the mutant: it gates like a survivor. Fix it
  with a unit test that exercises the code, never by adding a rule that maps
  an integration spec to the unit.
- `--test-quality` (`test_quality:`, nightly) records every test that kills
  each mutant (`killing_tests`) and reports, under `test_quality` in the JSON
  report, tests that kill nothing they cover and redundant tests (every kill
  also another test's). A redundant test may still pin behavior a mutant
  can't reach; read it before deleting it, and never delete two at once on
  this evidence alone.
- `--seed N` (`seed:`) makes each test draw the same random numbers in the
  baseline and every mutant's run; `--seed random` draws one and records it
  in the report's `run` section, so `--seed N` repeats a run.
- `--flaky-runs N` (`flaky_runs:`, nightly) reruns the covering tests under
  N other seeds. A test whose result changes is listed as flaky
  (`flaky_tests` in the JSON report) and never kills, so a mutant only it
  covers reads `no_coverage`. Fix the flaky test; don't raise a timeout or
  pin a seed to hide it.
- A `visibility` survivor (`public => private (name)`) says no test calls the
  method from outside its object: make it private, or test it through its
  public use. A method only ever called via `send` survives by design.
- `isolated_only` marks mutants that only `--isolated` can judge: class-body
  DSL, code in a method the suite only runs while it loads (a class macro
  or `included` hook another file's class body calls), and a lambda handed to
  a class-body macro (a `belongs_to` default, an `after_create_commit` lambda)
  that no test reached warm, because re-declaring the macro can leave the
  original lambda registered in front of the mutated one. Incremental runs
  (`--since`, `ci`, `changed`) judge them in the isolated tier by default
  (`judge_isolated_only`); on a full run use `--judge-isolated-only` or
  `--isolated`. Left unjudged they don't count in the score, and a scope
  where nothing else could be evaluated fails the gate. A method reached through an
  `alias` or `alias_method` declared in another file is judged warm like any
  other.
- Rails `enum` models overlay warm (the re-declaration is idempotent), so
  their method-body mutants are judged like any other. A file labeled
  `unmutatable` could not be overlaid (a distinct, reported reason); it is not
  an `--isolated` case. Its mutants report as `unmutatable` (never gating,
  never scored, with the reason in the detail), not `no_coverage`.

## Burn down a baseline

```sh
bundle exec kimera run --evaluate-ignored --report r.json   # judge ignored mutants too
bundle exec kimera baseline review .kimera-baseline.yml --report r.json
bundle exec kimera baseline prune .kimera-baseline.yml --report r.json  # --dry-run first
```

- `--evaluate-ignored` keeps ignored mutants `ignored` (never a gating
  survivor, still counted by `max_ignored`) but records each one's `verdict`.
  Don't copy `.kimera.yml` to drop the `baseline:` line; `--no-baseline`
  does that.
- `review` sorts entries into killed (prune), still surviving (triage them
  like any survivor), unjudged, stale, and out of scope. `prune` drops killed
  and stale entries, moves re-anchored ones to their current line, and says
  how far to lower `max_ignored`: lower it in the same diff.
- A drifted line anchor re-anchors on its own when the label (and `original`)
  single out one mutant; the `re-anchored` warning means update the entry.

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

### Survivors that recur on Rails apps

These shapes survive again and again. Recognizing one tells you which verdict
to test first. It never replaces the `--isolated` check.

Usually **dead code**. The guard only saves a query, so delete it:

- A guard before a query that already returns nil/false/0: `return false
  unless user` before `memberships.exists?(user:)` on a NOT NULL column, or
  `return if ids.empty?` before `where(id: ids)` / `update_all`.
- A no-op write under dirty tracking: `update!(status: :past_due) unless
  past_due?`. Rails skips the UPDATE when nothing changed. Delete the guard
  unless callbacks or `updated_at` must not fire, and if they must, test
  that.
- A readiness check that compares constants with constants
  (`REQUIRED - LIVE_STATES`). Nothing at runtime can change it, so assert it
  once at load time or drop it.

Usually **keep and ignore** (after `--isolated`, with the mechanism as the
`reason:`), because the code hardens against something tests don't drive:

- `reload` before `with_lock`/`lock!` on the same record, or double-checked
  locking. `with_lock` reloads the row anyway, and only a real race tells
  the two apart.
- `transaction(requires_new: true)` around a `create!` that rescues
  `RecordNotUnique`. It matters only when a concurrent insert wins.
- Barrier or queue values that nothing reads (`ready << true`), and
  timing-safe compares.

Before you delete one of these guards, check that it doesn't also skip a side
effect (a callback, a job, an audit row). If it does, the survivor is a real
gap: test that side effect.

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
- An inline `# kimera:disable[-next-line] [OPERATOR ...]: REASON` comment is
  an ignore entry too: it counts toward `max_ignored`, needs the same oracle
  run and mechanism, and lands with the raise. A comment without a reason
  fails the run.

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
  An error outside every test (a load error, a suite hook) kills only when it
  recurs with the mutant on and a fresh mirror without the mutant runs clean;
  otherwise it is `harness_error`. Concurrent mirrors get their own test
  database (Rails parallel testing) and a read-only view of `.git`.
  Kimera
  sets `KIMERA=1` wherever it loads the suite (warm, `--isolated`, doctor), so
  gate the floor on it (`minimum_coverage ... unless ENV["KIMERA"]`); `kimera
  doctor` warns when no condition on `ENV` guards it.
- A cluster of `error`/`timeout` verdicts in one region usually means harness
  fragility or a missing guard, not test strength. Read the cluster before
  counting the detections.
- Anti-patterns: chasing the score; adding tests without reading the mutant;
  white-box tests that mirror the implementation; reclassifying killable
  mutants as equivalent to end a triage session.
