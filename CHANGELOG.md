# Changelog

## Unreleased

- Guard-style memoization is no longer mutated, just as `@x ||=` never was.
  In a method that opens with `return @x if @x` (and assigns `@x` later) or
  `return if @x` then `@x = true`, the guard gets no `condition` mutant and
  the flag no `true => false`. Removing a memo only recomputes an equal value,
  so those mutants always survived. A re-entrancy guard of the same shape is
  skipped too.

## 0.1.3 (2026-09-27)

- `--isolated` no longer scores a child that crashes before reporting results
  as a kill. It is `harness_error`, and its `detail` gives the exit status and
  the ends of the child's stderr. A Minitest child that fails to load a test
  file still reports that as a kill, as the RSpec child already did.
- `--isolated` passes test ids and test files to the child in a request file
  instead of argv, so a mutant covered by thousands of tests no longer fails
  with `Errno::E2BIG: Argument list too long`.
- Warm reload-path mutants (for example, statements in a memoized method) run
  one test at a time and stop at the first failure. Tests covering the
  mutant's method run first. The hard timeout now applies to each test, not
  the whole suite, so a mutant a test kills is no longer reported as
  "reload worker produced no result". A test that overruns the timeout is a
  `timeout`, and a worker that dies names its exit status or signal.
- A scope or association declared in a concern's `included do` block is now
  instrumented in the classes that already included the concern. It used to be
  reported `no_coverage`, or `survived` when it was covered through another
  path.
- An association overlaid on a parent model now also reaches subclasses that
  declared associations of their own (such as STI children). They used to keep
  the unguarded reflection, so mutants in the association's scope lambda
  survived.
- The red-baseline hint prints a plain Minitest command for a Minitest suite
  instead of `rspec …`.
- `kimera report`/`kimera mutant` and incremental sessions read report JSON as
  UTF-8, so they no longer crash under a non-UTF-8 locale when a report
  contains non-ASCII text.

## 0.1.2 (2026-09-26)

- Kimera sets `KIMERA=1` in its own process before loading the suite, and in
  the `kimera doctor` test commands. A coverage floor gated on
  `ENV["KIMERA"]` no longer fails a passing warm run with exit 2 or blocks
  doctor's dry run. (#6)
- A string interpolating a local bound by a pattern (`in [:ok, chosen]`,
  `=> chosen`), a `&block` parameter, or a regexp named capture no longer
  sinks its file's mutants. unparser 0.9 could not round-trip it; Kimera now
  teaches unparser those bindings. (#7)
- The per-method splice fallback now claims mutants in an endless method
  (`def big? = value > 10`), and reopens `Data.define` / `Struct.new`
  constants instead of redefining them, so spliced guards are reached. (#7)
- Mutants Kimera could not instrument are reported as `unmutatable`, with the
  reason, instead of `no_coverage`. They never gate and stay out of the score,
  so `--fail-on-no-coverage` again means "no test executes this". (#7)
- `kimera run --since` no longer crashes with "invalid byte sequence in
  US-ASCII" when the locale isn't UTF-8 (e.g. `LANG` unset) and the diff
  contains non-ASCII text. Git's diff output is read as UTF-8, with invalid
  bytes replaced. (#9)

## 0.1.1 (2026-09-26)

- Fix a boot crash on case-sensitive filesystems (Linux): `require "English"`
  was spelled `require "english"`.
- `--isolated` judges a mutant on failed tests, not the child's exit status.
  A child that exits non-zero with zero failures (e.g. a SimpleCov
  `minimum_coverage` floor tripped by the partial run) is now `harness_error`
  instead of a false kill. Kills carry their failing tests. Children run with
  `KIMERA=1`, and `kimera doctor` warns about an ungated coverage floor.
- Skill: raising `max_ignored` is a judgment any triager may make when the
  entry has earned it (isolated survival, a mechanism `reason:`, the raise in
  the same diff), never a way to make a failing gate pass.

## 0.1.0 (2026-09-26)

Initial public release.

- Schemata-based mutation testing for Ruby and Rails. All mutants for a file
  compile into one guarded-dispatch program and are selected at runtime, so the
  suite loads once and mutants flip in a warm process.
- Warm worker pool (`--jobs N`) pulling from one shared, heaviest-first queue,
  with opt-in per-mutant transaction rollback (`--isolate-db`), cache resets,
  per-worker test databases, and a hard-killable watchdog.
- Covering tests run most-recent-killer first, cutting test executions without
  narrowing the measured covering set.
- Diff-driven incremental mode (`--since`) with resumable sessions and CI
  gating (`--max-survivors`, `--max-errors`, `--fail-on-no-coverage`).
- Isolated mode (`--isolated`): each mutant baked into a fresh tree and judged
  in a clean subprocess.
- RSpec and Minitest adapters, including `before(:suite)` / `after(:suite)`
  hooks. `--exclude-test GLOB` drops unrunnable test files. A red baseline
  prints how to reproduce it without Kimera.
- Low-noise default operators, plus extended and Rails-aware families
  (`--operators all`). These include contract operators (`index_fetch`,
  `kernel_coercion`, `respond_to_guard`, `symbol_literal`, `default_argument`)
  and `chain_link_deletion` (`a.where(x).recent.first` => `a.where(x).first`).
- Harness failures get their own `harness_error` status and never count as
  kills.
- Equivalent-mutant ignore list: a reason is required, `max_ignored` budgets
  it, `column:` pins ambiguous lines, and a warning fires when an entry no
  longer matches any mutant.
- `kimera skill` prints a bundled guide for AI coding agents: how to run,
  triage, and gate with Kimera, and the rules against gaming the score.
  `kimera init` points agents to it from `AGENTS.md`.
- Kimera holds itself to zero surviving mutants: the full warm self-host run
  gates at `max_survivors: 0`, with harness-critical files judged in the
  isolated tier.
