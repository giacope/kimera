# Changelog

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
