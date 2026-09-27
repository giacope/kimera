# Changelog

## Unreleased

- A warm worker that hits the soft timeout is replaced before it takes
  another mutant. The timeout interrupts only the test's own thread, so
  threads the test started (a lock holder in a concurrency test, say) kept
  their connections, transactions and locks. Later mutants on that worker
  blocked on them, timed out, and could be scored as kills.
- A retiring worker's shutdown (`parallelize_teardown` hooks, emptying its
  test database) is bounded by the hard timeout. Before, the watchdog stopped
  watching a worker once the queue drained, so a teardown blocked on a leaked
  lock hung `kimera run` forever.
- Emptying a worker's test database at shutdown waits at most 5 seconds for
  table locks on PostgreSQL and MySQL. If it gives up, kimera warns and still
  runs the `parallelize_teardown` hooks.
- `kimera doctor --check-baseline` lists the failing tests (up to ten) of a
  red baseline, for RSpec and Minitest.

## 0.1.5 (2026-09-27)

- Re-running a mutated concern's `included do` block no longer clobbers a
  scope or association that an including class redeclares after its
  `include`. Rails keeps the class's later declaration, but kimera re-declared
  the concern's version on top of it, so the baseline could go red only under
  kimera (for example, an `Invitation.expired` override losing its extra
  filter). Names the class declares after the `include` line are now skipped;
  the rest of the block still runs.
- Warm kills are confirmed. A mutant counts as killed only when its killing
  test also passes with the mutant switched off, then fails again with it on.
  Otherwise state the warm worker kept from earlier tests failed the test,
  whether that state persists or the test's own teardown cleared it. The
  worker is retired, the mutant is judged again on a fresh worker, and the
  report lists the test under state-leak warnings. On that fresh worker, a
  test that still fails without the mutant is left out, and if no other
  covering test confirms a kill the mutant is `harness_error` with the reason.
  Equivalent mutants no longer flip between `killed` and `survived` from run
  to run.
- A warm kill's `detail` holds the killing test's failure: its class, message
  and first frames (RSpec and Minitest). Kimera's own runner frames are left
  out.
- A test interrupted by the soft timeout is no longer named as the mutant's
  killer. RSpec and Minitest rescue the interrupt as an ordinary failure, so
  the test that happened to be running was scored `killed`. It is now a
  `timeout` whose `detail` names the test.
- Before the watchdog kills a wedged warm worker, it asks the worker for every
  thread's backtrace (SIGQUIT, answered within a second). The backtraces go in
  a hard-timeout verdict's `detail` and in a red baseline's message, so a stall
  shows what the worker was waiting on.
- A baseline test whose worker hits the hard timeout under `--jobs N` runs
  once more, alone, before it can turn the baseline red. If it passes, the run
  goes on and prints which tests stalled, with their backtraces. If it times
  out again, the baseline error says so and shows the backtraces of that run.
- Worker messages are read as UTF-8 whatever the locale, so a failure message
  with non-ASCII text no longer crashes a run under `LANG=C`.
- The README documents `--hard-timeout` next to `--jobs` for Rails suites with
  slow integration tests.

## 0.1.4 (2026-09-27)

- Guard-style memoization is no longer mutated, just as `@x ||=` never was.
  In a method that opens with `return @x if @x` (and assigns `@x` later) or
  `return if @x` then `@x = true`, the guard gets no `condition` mutant and
  the flag no `true => false`. Removing a memo only recomputes an equal value,
  so those mutants always survived. A re-entrancy guard of the same shape is
  skipped too.
- `--isolated` first runs the unmutated suite once in a fresh mirror. If it
  isn't green there (for example, a test helper that won't load), the run
  stops with exit 1 and the error, as a red warm baseline does. Before, every
  mutant it covered was scored `killed` with no failing test named.
- An isolated mirror symlinks `vendor/`, `node_modules/` and `.bundle/`
  instead of leaving them out. It creates `tmp/` and `log/` empty, and still
  leaves out `.git/` and `coverage/`. A boot that needs frontend tooling or a
  vendored bundle now loads in the mirror.
- An isolated kill caused by a test file failing to load now puts the load
  error (Minitest: message and first backtrace lines; RSpec: its load-error
  report) in the result's `detail`.
- Parallel warm workers follow Rails' fork contract more closely. Each sets
  `ActiveSupport::TestCase.parallel_worker_id` to its slot, so per-worker
  resources keyed on it (a Redis db, lease or key namespace, a port) no
  longer collide between workers. `parallelize_before_fork` hooks run once per
  fleet, not again before every spawn (including replacement workers forked
  while other workers are mid-test). `parallelize_teardown` hooks get the
  worker number.
- A red parallel baseline lists, for each worker that ran a failing test,
  where each failure fell in that worker's run and which tests ran just
  before it. A test lost when its worker hit the hard timeout or crashed now
  says so, instead of showing up as an unexplained failure.

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
  doctor's dry run.
- A string interpolating a local bound by a pattern (`in [:ok, chosen]`,
  `=> chosen`), a `&block` parameter, or a regexp named capture no longer
  sinks its file's mutants. unparser 0.9 could not round-trip it; Kimera now
  teaches unparser those bindings.
- The per-method splice fallback now claims mutants in an endless method
  (`def big? = value > 10`), and reopens `Data.define` / `Struct.new`
  constants instead of redefining them, so spliced guards are reached.
- Mutants Kimera could not instrument are reported as `unmutatable`, with the
  reason, instead of `no_coverage`. They never gate and stay out of the score,
  so `--fail-on-no-coverage` again means "no test executes this".
- `kimera run --since` no longer crashes with "invalid byte sequence in
  US-ASCII" when the locale isn't UTF-8 (e.g. `LANG` unset) and the diff
  contains non-ASCII text. Git's diff output is read as UTF-8, with invalid
  bytes replaced.

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
