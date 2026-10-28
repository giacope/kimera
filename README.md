<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Kimera" width="464">
  </picture>
</h1>

Mutation testing for Ruby and Rails, fast enough to gate a pull request.

Kimera plants small bugs ("mutants") in your code and checks that a test fails
for each one. A mutant no test catches is a **survivor**: a hole in your suite
that line coverage can't see. Kimera compiles all mutants into your code *once*
and flips them at runtime, so your app boots once, not once per mutant.

- **Fast.** [Stryker](https://stryker-mutator.io)-style mutant schemata
  ([Untch, Offutt & Harrold, 1993](https://doi.org/10.1145/154183.154265)): no
  reparse or reload per mutant. Each mutant's covering tests run fastest
  first, so most mutants die on their cheapest test. On a 4-vCPU cloud VM,
  dry-inflector's `lib` (738 mutants, `--operators all`) runs in 62s with
  `--jobs 4`, and kimera's own `lib/kimera/operators` and `lib/kimera/rewrite`
  (426 mutants) in 29s; a small Rails suite pays more for a fresh process per
  test ([`eval/results`](eval/results/README.md)).
- **Parallel.** Warm workers, forked once, pull mutants from one shared
  heaviest-first queue. A single large file spreads across every core.
- **Rails-ready.** Opt-in transaction rollback (`--isolate-db`), per-worker
  test databases via Rails' parallel-testing hooks, and 4 Rails operator
  families (strong params, validations, callbacks, associations). CI runs it
  end to end on a Rails 8.1 app ([`examples/rails_app`](examples/rails_app)),
  with Minitest and RSpec, in every mode.
- **Built for CI.** `kimera changed` mutates only the lines a PR touched.
  `kimera ci` fails the build on any survivor or untested change.
- **Low noise.** A small default operator set. 30 extended families are one
  flag away, and you can write your own.
- **Honest verdicts.** Your suite boots once, but every test and every
  mutant runs in a process forked from one no test has run in, so no cache,
  registry or flag a test left behind decides a verdict. Code the warm path
  can't judge is reported separately, never scored, and code it doesn't
  mutate is listed with the reason. `--isolated` re-checks any mutant in a
  fresh process.
- **Small.** Ruby >= 3.4 (CI covers 3.4 and 4.0), RSpec or Minitest, and one
  dependency: [Prism](https://github.com/ruby/prism). Kimera mutates Prism's
  tree and writes it back as Ruby itself (`Kimera::Scribe`).

```sh
$ bundle exec kimera run app --since origin/main
mutants=28 killed=17 survived=5 timeout=0 error=0 no_coverage=6 score=77.3%

  survived #3  app/models/discount.rb:18:21  in eligible?  [<= => <]
    - order_total <= 0
    + order_total < 0
    covered by 7 test(s):
      spec/discount_spec.rb:7  Discount#eligible? is false for non-positive totals
      spec/discount_spec.rb:12  Discount#eligible? is eligible for large orders
      spec/discount_spec.rb:17  Discount#eligible? is eligible for premium customers with a coupon
      (+4 more; all of them: kimera mutant 3 --report tmp/kimera/report.json)
```

This survivor says no test checks an order total of exactly `0`. Add that test
and the mutant dies.

**Contents:** [Getting started](#getting-started) ·
[Commands](#commands) · [Configuration](#configuration) ·
[Operators](#operators) ([Rails](#rails), [Custom](#custom-operators)) ·
[How it works](#how-it-works) · [Design notes](#design-notes--known-limits) ·
[Development](#development)

---

## Getting started

**1. Add Kimera to your Gemfile.** It runs inside your app's bundle so
dependency versions resolve consistently.

```ruby
gem "kimera", group: :test
```

```sh
bundle install
```

**2. Generate a config.** `init` detects RSpec or Minitest (from `.rspec`, a
test helper, or which one `Gemfile.lock` installs), your source roots
(`app/`, `lib/`), and your test glob (the one whose files define the most
tests: `test/**/test_*.rb` over a `test/**/*_test.rb` that matches only a
support class, or the pattern `.rspec` names; the files `.rspec` leaves out go to
`exclude_tests`), and its operators: the conservative core plus `when_clause`
and `append_deletion` (a `case`'s branches and `<<` statements, which the
core never mutates), and on a Rails app the `rails` operators. A
configuration without `operators:` keeps the core alone. It writes a commented `.kimera.yml`
whose first line names its [JSON schema](schema/kimera.schema.json), so
editors with a YAML language server complete and check the keys.

AI coding agents get their guide from `kimera skill`: how to run Kimera and
triage survivors without gaming the score. It matches your installed version
and works with any agent that can run a shell command.

```sh
bundle exec kimera init
```

**3. Check the setup.** `doctor` confirms source and test discovery (it fails
a `tests:` glob whose files define no test), Git, and Rails parallel-safety.
`--check-baseline` also runs your suite once to confirm it is green (leaving out
the tests `exclude_test_names` names, as `kimera run` does), and when
the suite aborts it quotes the reason (Rails' pending migrations). With `jobs:`
over 1 it then runs it again, split across that many processes as `kimera run`
splits it across its workers, and warns, naming the tests, when it is red
there: the suite shares a directory, file or port between tests. A split whose
parts fail with no failing test is a coverage floor (SimpleCov's
`minimum_coverage`), and doctor says that instead. A suite killed by a
signal is named first ("the suite was killed by SIGKILL before it printed a
summary — out of memory?"). `--jobs N` checks another
width; `--jobs 1` skips it. Ctrl-C or SIGTERM stops the suite's whole process
group, and kimera says it was interrupted.

```sh
bundle exec kimera doctor --check-baseline
```

**4. Run it.** Start with the code your branch changed, then widen.

```sh
bundle exec kimera changed          # lines changed since the branch left origin/main (or main)
bundle exec kimera run app/models   # one directory
bundle exec kimera run              # every path in .kimera.yml
```

**5. Triage survivors.** Every run saves its report to
`tmp/kimera/report.json` (`--report FILE` moves it, `--no-report` skips it),
so you can dig in without rerunning the suite. `report` and `mutant` read it
when you name no other.

```sh
bundle exec kimera report --status survived
bundle exec kimera mutant 42
bundle exec kimera mutant app/models/discount.rb:44:8557dadd
bundle exec kimera mutant 42 --rerun
bundle exec kimera run app/models/discount.rb:40-48   # only these lines
bundle exec kimera run app --method apply             # only inside apply
```

`kimera mutant` shows the diff, the source lines around the mutant, and the
tests that cover it and kill it, by file, line and description. The diff's
`+` line is the mutant's code: written alone when it parses alone (a call
forwarding an anonymous `&`, `*`, `**` or `...` does), else in its file
where it stands (an element of a `%i[]` list, a bare list, a call holding a
heredoc); one Kimera cannot write says so on the `+` line.

A mutant has two names. Its ID (`42`) numbers every mutant the run scanned,
so the same mutant gets a different ID when a run covers a different set of
files. Its key (`app/models/discount.rb:44:8557dadd`, the `key` field of each
report result) is `path:line:digest`. The digest is computed from the mutant's
own code (its file, method, operator, source, and label), so the key names
the same mutant in a one-file run and in a full one. `kimera mutant` and
`--focus` take either. A key whose line moved still resolves when the path
and digest match exactly one mutant. `--rerun` re-evaluates only that mutant,
focused by its key.

For each survivor, write the test that kills it. If a mutant is truly
equivalent, add it to `ignore:` in `.kimera.yml` with a reason, or mark the
line in the source (see [Configuration](#configuration)).

**6. Gate pull requests.** `kimera ci` fails on any survivor or uncovered
mutant. It writes `tmp/kimera/report.json`, prints GitHub annotations beside
the text report, and adds a Markdown summary to the job. On a pull request it
mutates only the PR's lines (`--since origin/$GITHUB_BASE_REF`), which needs
the base branch's history. The base comes from `--since`, `KIMERA_BASE` (any
ref), GitHub's `GITHUB_BASE_REF`, GitLab's `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`
or Buildkite's `BUILDKITE_PULL_REQUEST_BASE_BRANCH`; with none, `ci` says so
and runs a full run, which leaves class-body DSL (validations, associations,
callbacks) `isolated_only`: unjudged and ungated unless you pass
`--judge-isolated-only` (hours on a whole Rails app):

```yaml
# .github/workflows/mutation.yml
name: Mutation
on: pull_request
jobs:
  kimera:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec kimera ci
```

> **Adopting on an existing suite?** Snapshot today's survivors as reviewed
> debt, so the gate blocks only *new* holes:
> `bundle exec kimera baseline create --reason "adopting Kimera" --write`.
> It reads the last report and sets `baseline:` in `.kimera.yml`.

---

## Commands

```sh
# Summarize what would be mutated
bundle exec kimera registry app

# Write the synthesized schemata mirror (for inspection)
bundle exec kimera synthesize app --out tmp/schemata

# Run the full mutation suite
bundle exec kimera run app --tests 'spec/**/*_spec.rb'

# Minitest
bundle exec kimera run app --framework minitest --tests 'test/**/*_test.rb'

# Incremental: mutate only lines changed since the merge-base with main, gate
# CI, resume on retry (a session is resumed only while the sources, every file
# under the test roots, .rspec, Gemfile.lock and the judging settings match)
bundle exec kimera run app --since origin/main \
  --session tmp/kimera.json --max-survivors 0 --report tmp/report.json

# Also fail when a changed line has no covering test
# (a no_coverage mutant is untested new logic, not a pass)
bundle exec kimera run app --since origin/main --fail-on-no-coverage

# Evaluate only the given mutants, by report key or by ID (repeatable)
bundle exec kimera run app/models/discount.rb --focus app/models/discount.rb:44:8557dadd

# Mutate only some lines of a file, or only inside some methods (repeatable).
# A target that matches nothing fails, naming the lines and methods that have
# mutants
bundle exec kimera run app/models/discount.rb:40-48
bundle exec kimera run app --method apply --method eligible?

# N warm workers pull from one shared queue, so this scales with cores
# even on a single big file
bundle exec kimera run app --jobs 4

# Rails suites with slow integration tests: the watchdog kills a worker whose
# test runs past --hard-timeout (default 16s, from --soft-timeout 5 × 3 + 1).
# A baseline test killed that way reruns once alone; raise the limit if it's
# only slow under parallel load
bundle exec kimera run app --jobs 8 --hard-timeout 60

# Run only some test files, for speed. --tests replaces the configured tests:
# glob, so verdicts hold only for those files: a survivor may be killed by a
# test left out. The report says so ("narrowed run: --tests matched 1 of 1,120
# test files ...", and "narrowed": true in the JSON report's run section).
# Mutants the narrowed tests leave uncovered read "not covered by the narrowed
# tests" and are neither scored nor gated on (--fail-on-no-coverage still gates)
bundle exec kimera run app/models/order.rb --tests 'spec/models/order_spec.rb'

# Drop spec files that can't run this way (order-dependent, need a browser)
# without rewriting the whole --tests glob
bundle exec kimera run app --exclude-test 'spec/system/**/*_spec.rb'

# Leave out single tests by name or id (a regular expression; exclude_test_names
# in .kimera.yml), keeping the rest of their file: a test that fails only as root
bundle exec kimera run lib --exclude-test-name 'unreadable directories'

# Judge every mutant in a fresh subprocess: bake it into a mirror of the tree
# and run its covering tests under plain rspec. Slower, but trustworthy even
# for code that can't be instrumented in-process.
bundle exec kimera run app --isolated
```

### Daily and CI workflows

```sh
# Mutate only the PR's changed lines (origin/main, falling back to main)
bundle exec kimera changed

# Strict gate: zero survivors, no uncovered mutants, a JSON artifact, GitHub
# annotations and a job summary. Override with --format sarif/json.
bundle exec kimera ci

# Continue triage without rerunning the suite (reads tmp/kimera/report.json)
bundle exec kimera report --status no_coverage
bundle exec kimera mutant 42

# Snapshot pre-existing survivors while adopting Kimera, and set baseline:
# in .kimera.yml; then review the file in code review
bundle exec kimera baseline create --reason "adopting Kimera" --write
bundle exec kimera baseline review .kimera-baseline.yml

# Burn the baseline down: evaluate the ignored mutants too, see which entries
# are now killed or stale, and drop them
bundle exec kimera run --evaluate-ignored --report tmp/kimera/report.json
bundle exec kimera baseline review .kimera-baseline.yml --report tmp/kimera/report.json
bundle exec kimera baseline prune .kimera-baseline.yml --report tmp/kimera/report.json
```

Ignored mutants, from `ignore:` or the baseline, are skipped by default.
`--evaluate-ignored` runs them anyway: each keeps status `ignored` (it never
gates as a survivor and still counts toward `max_ignored`) and its report row
gains a `verdict` (`killed`, `survived`, ...). `--no-baseline` leaves the
baseline out entirely, so its mutants are judged and gated like any other.

`baseline review --report` sorts the entries into killed (safe to prune),
still surviving, unjudged, stale (the report covers the file but no mutant
matches), and out of the report's scope. `baseline prune` drops the killed and
stale ones (`--dry-run` only prints them) and says how far `max_ignored` can
drop. After an incremental `--since` run it never prunes an entry as stale.

### Output formats and exit codes

- `--format json`, `ndjson`, `github`, `sarif`, and `markdown` write *only*
  that format to stdout. Progress and diagnostics go to stderr, and so does
  the text report under `github`, so a CI log reads on its own.
- The canonical JSON report goes to `tmp/kimera/report.json`, or to
  `--report FILE`; `--no-report` skips it. Each result names its test ids, and
  the report's `tests` section maps each id to its description and
  `file:line`. [`schema/report.schema.json`](schema/report.schema.json)
  describes every field.
- `--summary FILE` appends a Markdown summary of the findings to FILE.
  `kimera ci` sets it to `$GITHUB_STEP_SUMMARY` when GitHub Actions does.
- GitHub annotations fold the mutants on one line into one, with each diff.
  GitHub shows 10 annotations of each level per step; past that, a notice
  points at the job summary and the report.
- Text output honors `NO_COLOR`. `--no-color` forces it off.
- `--quiet` suits scripts that only need an artifact. `--verbose` prints the
  resolved scope. `--log FILE` keeps the final text report.
- `--pidfile FILE` writes kimera's process id to FILE when the run starts and
  removes the file when the run ends, whether it passes, fails or errors
  (short of `kill -9`). A script that waits on a background run can watch
  that pid; `pgrep -f "kimera run"` also matches the shell that started it.

Exit codes:

- **`0`**: pass.
- **`2`**: the gate failed. Survivors (with `uncovered_by_unit` mutants)
  exceed the threshold (default: any survivor), or a mutant in scope has no covering test under
  `--fail-on-no-coverage` or `--count-no-coverage`, ignored mutants exceed `max_ignored`, or more
  mutants than `--max-errors` (default 0) could not be judged.
- **`1`**: the baseline is not green, a test fails under Kimera but passes
  when rerun plainly (a harness error that names the tests and the likely
  cause), the pool cannot keep a worker alive, or the invocation is invalid. Paths that match no source files, `--tests` that
  matches no test files, and an unknown `--since` ref all count. An empty or
  broken scope fails loudly instead of scoring perfectly over nothing.

`--isolated` trades speed for trust. It never overlays schemata or shares a
process with the code under test. On ordinary code it reaches the same verdicts
as the warm path. It can also test what the warm path can't: the runtime
selector and Kimera's own harness-critical files (see below).

An isolated child is judged on its failed tests, not its exit status. A child
that exits non-zero with no failing test is `harness_error` (unjudged, gated
by `--max-errors`), not a kill. So is a child that dies before reporting any
results (a boot error, an exit hook, a crash); its `detail` carries the
child's exit status and the ends of its stderr. The usual cause of a non-zero
exit with no failures is a coverage floor such as
SimpleCov's `minimum_coverage`, which a partial run always trips. Kimera sets
`KIMERA=1` wherever it loads your suite (the warm process, `--isolated`
children, and `kimera doctor`'s test commands), so skip the floor there:

```ruby
SimpleCov.start { minimum_coverage(line: 100, branch: 100) unless ENV["KIMERA"] }
```

`kimera doctor` warns when it finds a `minimum_coverage` or
`minimum_coverage_by_file` that no condition on `ENV` guards. A floor that
applies only when the environment asks for it (`if ENV["COVERAGE"]`, a
`case` on `ENV`, or after `return unless ENV["COVERAGE"]`) passes whatever
the variable; one under any other condition still warns.

Each isolated mirror is a copy of the project root with some exceptions:
`.git/` and `coverage/` are left out, `tmp/` and `log/` start empty, and
`vendor/`, `node_modules/` and `.bundle/` are symlinked to the originals. The
exception is a directory that holds a mutated file, which is always copied.
Before judging any mutant, `--isolated` runs the unmutated suite once in a
mirror: the tests its mutants will run, in suite order (every test, when one
of them needs the whole suite). If it isn't green there, the run stops with
exit 1 and the error. A mutant's mirror then runs its covering tests fastest
first and stops at the first that fails.

A mirror is as safe as a warm worker:

- Past the first, each concurrent mirror takes a test database of its own
  through Rails' parallel-testing hooks (`<db>_1`, `<db>_2`, ...), or a copy
  of the parent's when there is no schema file to load, as warm workers do,
  so a `before(:suite)` that truncates or seeds cannot race
  another mirror. Each also gets `TEST_ENV_NUMBER` (parallel_tests'
  convention), and kimera closes its own database connections before it
  starts one, so a suite that drops and re-creates its database at load runs.
- Its `.git` is a private snapshot (HEAD, index and refs) that reads the
  project's objects, so a suite's `git ls-files` works and nothing the suite
  does writes the project's `.git`.
- A run that fails with an error outside every test (a load error, a suite
  hook, a `spec_helper` that `.rspec` requires and that raises) names no test,
  and is quoted with its class and message; it is not a kill on sight. The mutant runs once
  more; if the error recurs, a fresh mirror runs the same tests without the
  mutant. Clean there, the mutant broke loading and is killed, the detail
  saying so; failing there too, it is the environment and the mutant stays
  `harness_error`.
- A mutant with no coverage of its own (class-body DSL, a memoized value,
  code the suite runs while it loads) runs every test in the test files that
  cover its source file, plus the file's conventional spec or test file
  (`user_spec.rb`, `user_test.rb`); the whole suite only where coverage names
  no such test.
- The watchdog renews on each test; a test whose baseline needs longer than
  `--hard-timeout` gets its own limit (baseline × 3 + 1s), and a timed-out
  mirror says so with its limit ("timed out after 16s without a test
  finishing"), never "its tests fail".

### Re-judging what the warm pass could not

The warm pass can't judge a mutant whose process died before it replied (the
mutant makes the code call `exit!`, or crash), or whose only failing test
also fails without the mutant after the covering tests run before it: that
mutant would be `harness_error`. Nor can it change what a method computed
while the suite loaded (a constant table built from it): the guards are
installed after boot. So a warm survivor whose method the suite also ran
while it loaded is judged again too. Nor can it see what Ruby settles as it
compiles a method, such as whether the method uses the block passed to it:
the overlay compiles every mutant of a method into one, so a mutant that
leaves the method no `yield` still reads as taking its block. Under a suite
that reports an ignored block (`Warning[:strict_unused_block]`, or
`$VERBOSE`), and may raise it, such a mutant's warm survivor is judged again.

After the warm pass, Kimera judges each such mutant again in the isolated
tier, in a fresh mirror of its own, against its covering tests only (every
test under `--no-coverage`; for a method that ran at load, and for a mutant
that leaves its method no `yield`, the tests near its file, as above). A kill (or
timeout) stands only if those tests then pass in another fresh mirror
without the mutant. The report carries the fresh
verdict, and the row's `note` keeps what the warm pass said. The text report
tallies these mutants, and `github`/`sarif` findings append the note.

- If the tests fail without the mutant too, or the mirror can't run them,
  the mutant stays `harness_error`, with the reason as its `detail`.
- Only these mutants are re-judged, `--jobs` at a time, each under
  `--hard-timeout` for its whole run (300s when unset). No full-suite
  baseline runs first; the confirming run replaces it.
- `--no-rejudge` (or `rejudge: false` in `.kimera.yml`) turns this off: the
  mutants stay `harness_error` with the warm detail.

### Confirming survivors

A mutant's covering tests run together in one forked process, so an earlier
test can load what the mutant broke and hide the kill: a run-once guard, a
lazy registry, an autoloader. Under `--confirm-survivors`
(`confirm_survivors: true`), each warm survivor's covering tests then run
alone in a fresh fork with the mutant on, fastest first and at most 50. A test
that fails alone kills the mutant only if it passes alone with the mutant
off; the detail starts "failed alone in a fresh process (an earlier covering
test masked it ...)". It is on by default for incremental runs (`--since`,
`kimera ci`, `kimera changed`), where survivors are few, and off for full
runs unless asked; the report's run section records the choice.

### Reusing coverage on incremental runs

An incremental run still measures the coverage baseline first: every test,
once, under coverage, before any mutant runs. On a big suite that is most of
the wait. Under `--reuse-coverage` (`reuse_coverage: true`) a full run keeps
its baseline's coverage map in `tmp/kimera/coverage.json`: which tests reached
each source file, every test the suite held, and what it was measured
against: the commit, Ruby, the settings that pick the tests and sources, and a
digest of each source and of each test, support and config file (everything
under the test roots, `.rspec`, `Gemfile.lock`, `config/`, `db/schema.rb`;
files git ignores are left out, since a suite rewrites some on every run). A
later `--since`, `kimera ci` or `kimera changed` run with the flag reruns only
the tests the map says reached a source file that changed since it was built,
or one in scope, and the tests it does not know. Every test that can cover a
changed line gets a fresh baseline, so no mutant is judged against old
coverage.

```sh
bundle exec kimera run --reuse-coverage       # a full run (on main) stores the map
bundle exec kimera changed --reuse-coverage   # a branch reruns only what its change reaches
```

The incremental run says what it reused, for example `kimera: reusing the
coverage map from 1a2b3c4 (2 source file(s) changed since): the baseline runs
38 of 1,204 tests`. When the map cannot hold (none is stored, another Ruby,
other settings, or a test, support or config file changed, was added or was
removed) it runs every test and says why in one line: `kimera: not reusing
the stored coverage map: spec/support/auth.rb changed; the baseline runs every
test`. Only a full run stores a map; in CI, cache `tmp/kimera/coverage.json`
from the main branch's full run and restore it in pull requests.

A map cannot see a test that reached none of the changed or in-scope files
when it was built but reaches them now through code that ran only at load (a
new method that overrides an inherited one, a changed constant), or through a
changed file outside the source, test and config sets (a view, a data file).
Leaving such a test out can only turn a kill into a survivor or an uncovered
mutant, never the reverse: confirm a surprising one without the flag.

### Per-test soft limit

Each covering test may run for `--soft-timeout`, or for its own baseline ×
3 + 1s when that is longer, so a DB-heavy example that takes 4.7s on a busy
machine is not timed out at 5s. The raise stays a second under the hard
watchdog (`--hard-timeout`), which still catches what the soft timeout cannot
interrupt. A test with no baseline (under `--no-coverage`) keeps
`--soft-timeout`. Timeout details name the limit the test ran under.

### Relative time budget

A mutant can slow every test it touches without failing any: deleting a
`pool.shutdown` makes a `wait_for_termination(1)` in each test's setup wait
out its full second. Under the absolute soft timeout alone, such a mutant runs
all its covering tests to completion and survives, and one of them can cost
most of a run's wall time.

The coverage pass already runs each test once, so Kimera records how long it
took. In the warm pass, a covering test that passes but runs past
`baseline × --timeout-factor + --timeout-slack` (10 × its baseline + 1s by
default) makes the mutant a `timeout`, which counts as detected. A single slow
run is not enough. The same test must then keep to its budget with the mutant
switched off, and run past it again with the mutant on. A fresh worker's first
test, a GC pause or a burst of load from other workers doesn't repeat on the
rerun, or slows the control run too, so the budget is let go and the mutant
runs on. The verdict's `detail` names the test, both runs, the budget and how
it was set.

- It is on by default. `--no-relative-timeout` (or `relative_timeout: false`
  in `.kimera.yml`) turns it off; `--timeout-factor` and `--timeout-slack`
  (`timeout_factor:`, `timeout_slack:`) tune it.
- A test with no baseline has no budget: under `--no-coverage` nothing is
  timed, and the soft and hard timeouts alone apply, as they always do.
- The isolated and reload tiers keep only their absolute limits (raised per
  test as above in the isolated tier). They bake the mutant into a fresh
  process, so there is no run without it to compare with, and a fresh
  process's first tests run slower than the warm baseline.

### Strict attribution

By default any covering test may kill a mutant, so a request spec that runs
a whole controller stack kills mutants in every model it touches, and those
models look tested when no test of theirs would notice. `attribution: unit`
(`--attribution unit`) lets only a unit's own tests kill its mutants:

- `lib/foo/bar.rb` is tested by `spec/foo/bar_spec.rb`,
  `spec/lib/foo/bar_spec.rb`, `test/foo/bar_test.rb` or `test/foo/test_bar.rb`,
  the same under `spec/unit/` and `test/unit/`, and any spec or test in a
  directory named after it (`spec/unit/foo/bar/camelize_spec.rb`);
- `app/models/order.rb` by `spec/models/order_spec.rb`,
  `test/models/order_test.rb` or `spec/order_spec.rb`, so `spec/requests/`
  and `test/integration/` count for no unit;
- `unit_tests:` adds rules, source glob => test pattern(s). A pattern may name
  `{path}`, the source's path under the glob's literal prefix, and `{name}`,
  both without `.rb`; it matches as a glob. `--unit-tests GLOB=PATTERN`
  (repeatable) replaces the config's rules.

```yaml
attribution: unit
unit_tests:
  "app/services/**/*.rb": "spec/services/{path}_spec.rb"
  "lib/**/*.rb": ["test/**/{name}_test.rb"]
```

A test belongs to the file that declares it (an RSpec example to its spec
file, a Minitest test to its class's file). A mutant only other units' tests
reach is `uncovered_by_unit`, not killed: its row lists those tests (they are
not run) and names the test files that would count. It is scored as not
killed and counts toward `max_survivors` like a survivor, and `kimera
baseline create` accepts it like one. A mutant no test reaches stays
`no_coverage`. It needs the coverage baseline, so not with `--no-coverage`.

### Test quality

A run stops judging a mutant at its first failing test, so it says which
mutants survive, not which tests earn their keep. `test_quality: true`
(`--test-quality`), meant for a nightly full run, records every covering
test that kills each killed mutant: after the usual verdict, each other
covering test runs alone in a fresh fork with the mutant on, and fails,
times out or crashes to count. The verdicts and the score don't change.

Each killed result gains `killing_tests`, and the report a `test_quality`
section:

- `kills_nothing`: tests that cover a judged mutant and kill none of them;
- `redundant`: tests that kill mutants, each of which another test kills
  too. Each is redundant alone: dropping two of them may lose a kill;
- `covers_nothing`: tests that run no mutant in scope (a run over part of
  the code lists most of the suite here);
- `standings`: for each test that covers a mutant, how many it covers, how
  many it kills, and how many only it kills.

The text report sums these up and names the first few of each. It costs one
fork per covering test of each killed mutant, after the first: two
dry-inflector files whose 15 mutants about 620 specs each cover took 89s
against 14s, and its whole `lib` (738 mutants, about 820 covering specs
each) would take over an hour against about a minute. Run it nightly, or
over the part of the code you are reviewing. In the isolated
tier a mutant's killers are the tests that fail in one run of all its
covering tests; the reload tier (memoized code) records its first killer
only. Under `attribution: unit`, a test counts only toward its own unit's
mutants.

### Seeds and flaky tests

Every test runs in a process forked from the booted suite, and Ruby reseeds
its random numbers in each fork, so a test that draws `rand` (or a factory
that does) draws differently in the baseline and in each mutant's run. On
Minitest the suite's order is fixed at `--seed 1`.

- `seed: N` (`--seed N`) seeds each test's random numbers with `N` and the
  test's id (`Kernel.srand`) before it runs, on the warm path, the reload
  tier and in `--isolated` children alike, and gives Minitest `N` as its
  seed. A test then draws the same numbers in the baseline, in every mutant's
  run and in the next run with the same seed. `--seed random` draws `N`; the
  report's `run` section records it, so `--seed N` repeats the run. Kimera
  exports it to the suite as `KIMERA_SEED`. Unset
  (the default) keeps today's behavior. A `--session` resumes only under the
  same seed.
- `flaky_runs: N` (`--flaky-runs N`, default 0) reruns the tests that cover
  a mutant in scope `N` more times after the baseline, each in a fresh fork
  under another seed (the run's seed plus 1, 2, ..., or drawn ones). A test
  that passed the baseline and fails, times out or crashes in a rerun is
  **flaky**: the report lists it under "Flaky tests", with the seeds it
  failed under and why (`flaky_tests` in the JSON report), and it never kills
  a mutant. A mutant only flaky tests cover is `no_coverage`, its detail
  naming them. Each rerun costs about one baseline of the covering tests.

Why a flaky test kills nothing: Kimera takes a covering test's failure, in a
fresh process with the mutant on, as the kill. A flaky test fails without
the mutant too, so its failure says nothing about the mutant, and counting
it would score a hole in the suite as caught. Leaving it out errs the other
way, toward a survivor or an uncovered mutant, which the gate shows and a
person triages: fix the test, and its kills count again.

### Progress output

During a run, progress for each phase goes to stderr, never stdout, so
`--format json` and the other machine formats stay parseable. On a tty it is a
bar redrawn in place, and completed phases stay visible:

- `baseline` records coverage.
- `mutants (warm)` uses the shared worker pool.
- `mutants (isolated)` evaluates the subset routed to fresh mirrors.
- `mutants (re-judged)` judges again what the warm pass could not.

The warm and isolated labels appear only when a run uses both strategies. Output the
suite prints during mutant evaluation is swallowed, since mutated code warns,
raises, and logs freely. Verdicts travel back as structured results.

```
baseline [========================]  895/895  100%  0:03
mutants (warm) [========================]  2104/2104  100%  killed=1867 survived=137 no_coverage=100  0:59
mutants (isolated) [===========>            ]  224/445  50%  killed=196 survived=0 no_coverage=19 timeout=9  2:01
```

When stderr is not a tty (CI, `2> log`), each phase prints plain lines
instead: one when it starts, one at most every 30 seconds while its mutants
complete, and one when it ends. A line comes only as mutants complete, so a
gap well past 30 seconds plus `--hard-timeout` points at a stalled run rather
than a slow one.

```
kimera: baseline 0/895 0%  0:00 elapsed
kimera: baseline 895/895 100%  298.3/s  0:03 elapsed
kimera: mutants (warm) 0/4124 0%  0:00 elapsed
kimera: mutants (warm) 1210/4124 29%  killed=801 survived=312 no_coverage=97  1.7/s  ETA 29:03  12:04 elapsed
```

Phases with no count, such as `--isolated`'s unmutated baseline or the
re-judge pass's reason, get one plain line each. `--no-progress` (or
`progress: false` in `.kimera.yml`) silences all of it; `--progress` turns it
back on over a config's `false`.

---

## Configuration

`.kimera.yml` in the project root sets defaults. Command-line flags override
them. [`schema/kimera.schema.json`](schema/kimera.schema.json) describes every
key; the `.kimera.yml` that `kimera init` writes names it on its first line,
so editors with a YAML language server complete and check the file.

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/giacope/kimera/main/schema/kimera.schema.json
framework: rspec
paths: ["app/**/*.rb"]
tests: ["spec/**/*_spec.rb"]
exclude: ["app/legacy/**/*.rb"]
operators: [comparison, boolean_connective, boolean_literal, statement_deletion, negation, conditional]
# Ruby files loaded before the scan, for custom operators.
require: []
jobs: 4
max_survivors: 0
# Fail when any mutant in scope lacks a covering test, even with
# count_no_coverage off or on a narrowed run. Best on incremental runs, where
# "no coverage" means the PR adds logic no test executes.
fail_on_no_coverage: false
# Score uncovered mutants as not killed, and fail on them, in every command
# (default: true; untested code is not passing code). false reports them
# without scoring them.
count_no_coverage: true
# Judge in fresh isolated mirrors what the warm run cannot (validations,
# callbacks, dependent:, lambdas a macro registers). Unset: on for --since,
# ci and changed; off for full runs.
# judge_isolated_only: true
# Run each warm survivor's covering tests alone in a fresh process, so an
# earlier test cannot mask a kill. Unset: on for --since, ci and changed.
# confirm_survivors: true
# Keep a full run's coverage map in tmp/kimera; --since, ci and changed then
# rerun only the baseline tests that reach the changed files, while the tests,
# support and config files, settings and Ruby still match it.
# reuse_coverage: true
# Extra folders for the load path, beside each test file's nearest test/ or
# spec/ and the project's own test/ and spec/. doctor and the printed
# reproduce commands use the same load path.
# load_path: [test/support]

# The gate fails when more than this many mutants are ignore-listed. Marking
# one more mutant equivalent means raising this number in the same diff, so
# the ignore list stays a justified decision, reviewed in the diff that makes
# it, not a shortcut past a test.
max_ignored: 1

# Accepted pre-adoption survivors, merged with the ignore rules below.
# `kimera baseline create --write` creates the file and sets this line.
# baseline: .kimera-baseline.yml

# Known-equivalent mutants. Equivalence is undecidable, so Kimera doesn't
# guess: you mark a mutant and it stops being a survivor. An entry without
# a reason: is rejected at startup. Anchors: file (a glob, required), line
# (spanned), starts (the line the mutated code starts on), column (1-based, as the report prints it),
# label, method, original, operator. If a line anchor drifts (a line was added
# above), the entry still applies when its label (plus original/method, if
# given) singles out one mutant in the file; Kimera warns so you can update it.
ignore:
  - file: app/models/discount.rb
    line: 33
    label: "> => >="
    reason: known equivalent at the 50 boundary (spend > 50 vs >= 50 both hit the tier)
```

A comment in the source does the same for the mutants that start on its line,
or on the next line with `-next-line`, optionally only those of the named
operators:

```ruby
amount > 50 # kimera:disable comparison: spend > 50 and >= 50 both hit the tier

# kimera:disable-next-line: the flush is redundant, IO.pipe write ends are sync
io.flush
```

The reason is required, the operator keys are checked, and the mutants count
toward `max_ignored` like any ignore entry. A comment that disables nothing is
warned about.

---

## Operators

The *default* set is small and low-noise:

- comparison operators (boundary and negation)
- boolean connectives and boolean literals
- deletion of side-effecting statements, not of the value an interpolation
  embeds (`x` in `"#{x}"`, `:"#{x}"`, `/#{x}/`, backticks, heredocs)
- `!x => x`
- forced `if` conditions

Memoization is not a mutation target. Dropping a memo only recomputes an equal
value, so that mutant would always survive. `@x ||= …` has no such mutant, and
neither does a guard that opens a method: `return @x if defined?(@x)`,
`return @x if @x` (with `@x` assigned later in the method), or `return if @x`
followed by `@x = true`, nor a guarded fill that ends on the ivar:
`unless @x; ...; @x = value; end; @x` (also `@x = value unless @x`,
`if @x.nil?`, `if !@x`). A keyed cache is the same memo: `@cache[key] ||= …`
marks its value as computed once, and an early return of a cache lookup
(`return @cache[key] if @cache.key?(key)`, or `cached = @cache[key]; return
cached if cached`) has no conditional mutant when the method stores into the
same cache, nor does that store. Everything the method computes is still mutated. A
re-entrancy guard with the run-once shape is skipped too.

The extended families are one flag away. Use `--operators all`, or pick from:

| family | mutation |
|---|---|
| `arithmetic` | `+ => -`, `* => /`, `% => *`, `** => *`, ... |
| `safe_navigation` | `a&.b => a.b` |
| `numeric_literal` | `n => n-1, n+1, 0`; floats `f => f+1.0` |
| `string_literal` | `"text" => ""` |
| `collection_literal` | `[a, b] => []`, `{k: v} => {}` |
| `range` | `a..b <=> a...b` |
| `method_unwrap` | `x.strip => x` (curated argless transformations) |
| `return_value` | `return x => return nil`; def-body tail `=> nil` (not for a `nil` or `false` tail: a truthiness test can't tell them apart) |
| `selector_swap` | `select <=> reject`, `all? <=> any?`, `min <=> max`, `first <=> last`, `detect => first` |
| `regexp` | `/pat/ => //` (match all) and `=> /(?!)/` (match none) |
| `element_drop` | `[a, b, c]` / `{k: v, ...}` => drop one element/pair |
| `argument_drop` | `pay(amount, currency)` => drop one argument |
| `op_assign` | `total += x => total -= x`, `*= <=> /=` |
| `index_fetch` | `h[k] => h.fetch(k)` (a tolerated miss becomes a `KeyError`) |
| `kernel_coercion` | `Array(x) => x`, likewise `String`/`Integer`/`Float` |
| `respond_to_guard` | `x.respond_to?(:m) => x` |
| `symbol_literal` | `:total => :total__kimera__` |
| `default_argument` | `def f(a = 1)` / `f(b: 1)` => the parameter becomes required |
| `chain_link_deletion` | `a.where(x).recent.first => a.where(x).first`: drop one link, keep both ends |
| `super_call` | `super` / `super(...)` => `nil`: the inherited behavior is skipped |
| `rescue_clause` | drop one `rescue` clause (of a method body or a `begin`), or a `rescue` modifier |
| `ensure_clause` | drop an `ensure` block |
| `assignment_deletion` | `@total = sum(xs) => sum(xs)`; a local only where it rebinds a bound name (`name = name.strip => name.strip`) |
| `nil_literal` | `return nil` (and `next`/`break nil`), a method's tail `nil` => `::Object.new` |
| `regexp_anchor` | drop one of `\A`, `^`, `\z`, `\Z`, `$` |
| `regexp_quantifier` | `+ <=> *`, drop `?`, `{n,m} => {n-1,m}` / `{n,m+1}`, `{n} => {n-1}` / `{n+1}` |
| `keyword_drop` | `pay(amount, currency: "EUR") => pay(amount)`: drop one keyword argument at a call |
| `visibility` | a public instance method => private |
| `when_clause` | drop one `when` of a `case` that has another: the value falls through to the next branch or the `else` |
| `append_deletion` | delete a statement that appends with `<<` (`@log << name`), which `statement_deletion` leaves alone |

Turning them all on typically triples the mutant count. Adopt them through the
baseline burn-down workflow, not by flipping them on in a mature gate.

**Contract operators.** The five from `index_fetch` through `default_argument`
each remove an affordance the code grants its callers. A survivor means no test
exercises the case the affordance exists for. `index_fetch` and
`kernel_coercion` are equivalent wherever the key is always present or the
value already has the target shape. That is the normal case for an options hash
built from a defaults literal. Scope them to data that crosses a boundary
(params, parsed JSON, ENV); on internal bookkeeping they are noise.

**`assignment_deletion`** keeps the assigned value: the right-hand side
still runs and is still the statement's value, only the store is gone, so a
survivor says exactly one thing: nothing reads what was stored. (Dropping the
whole statement would also drop the value's side effects, which
`statement_deletion` already covers, and mix two questions in one mutant.) A
local is mutated only where an earlier binding keeps its name a local (a
parameter, an earlier write, an outer local written from a block); dropping a
name's first write would turn its later reads into method calls, a
`NameError` any covering test trips. A memoizing store is never a target.

**`visibility`** asks whether a public method is public for a reason. A
survivor means no test calls it from outside its object: it is untested API,
or it should be private. The schemata keeps the method public and registers
it with `::Kimera::RUNTIME`; activating the mutant makes it private (every
name holding that definition, so an alias another file took of it too, or
one a class or object that includes or extends its module took, and not a
later redefinition; a method defined while the mutant is active is private
as defined), and deactivating it makes it public again. So the
mutant is a real private method: `respond_to?` says false, an outside call
reaches `method_missing`, `public_send` raises, `send` still works (a method
only ever called through `send` survives, as it should), and a Rails
controller's cached action list is dropped with each flip, so a private
action is not routable. A probe at the top of the method records which tests
call it. Only `def`s in a class, module or `class << self` body that are
public where they stand count; methods Ruby or a protocol calls by name
(`initialize`, `to_s`, `==`, `each`, `call`, `method_missing`, ...) are left
alone. A visibility mutant spans its whole method, so on an incremental run
a change anywhere in a public method selects it.

**`regexp_anchor` and `regexp_quantifier`** read the pattern's own syntax
(character classes, escapes and group openers are skipped). They leave
interpolated patterns and the `x` flag alone.

The nine families from `super_call` down were measured before choosing
where they go; each is opt-in because each leaves more equivalent or
low-value survivors than the default set allows (from 30% of the survivors
an independent reviewer judged, for `keyword_drop`, to 80% for
`super_call`). `super_call` skips the `super` of `respond_to_missing?`, and
`assignment_deletion` an `@x = nil` in `initialize`: both are equivalent by
construction. The numbers, per family and corpus, are in
[`eval/results`](eval/results/README.md#new-operators-o1).

**`chain_link_deletion`** casts the widest net and matters most for Rails. Most
Rails business rules live mid-chain: the scope, the filter, the decorator.
Deleting a link asks whether any test depends on it narrowing anything. It
generates roughly one mutant per chained call, so scope it to the code you are
burning down, not a whole app.

### Rails

Four Rails-aware families ship as the `rails` group. `--operators
comparison,rails` composes, and `all` includes them.

| family | mutation | what a survivor means |
|---|---|---|
| `rails_permit` | `permit(:name, :admin)` => drop one key | over-permissive strong params no test notices |
| `rails_validation` | delete `validates ...`; drop one option of a `validates` that keeps a validator (`length:` beside `presence:`, `if:`) | a validation, or one constraint of it, no test ever violates |
| `rails_callback` | delete `before_action :authenticate_user!` etc.; drop one action from an `only:`/`except:` list | an unguarded path (or a guarded action) no test exercises |
| `rails_association` | `has_many :posts, dependent: :destroy` => drop `dependent:` | orphaned-record cleanup no test observes |

- **Scope lambdas** are mutated on the *warm* path. A `-> { ... }` body at class
  level re-executes per call, so ordinary operators mutate it safely
  (`scope :active, -> { where(active: true) }`). Run-once `do ... end` DSL
  blocks (`included do`, `class_eval`) stay excluded. A macro that registers
  its lambda rather than redefining a method (`belongs_to :creator, default:
  -> { Current.user }`, `after_create_commit -> { ... }`) keeps the original
  lambda in front when the warm overlay re-declares it, so the mutated one
  never runs: such a lambda that no test reached warm reports `isolated_only`,
  not `no_coverage`, and `--isolated` judges it against the tests in the
  files that cover its source file (the whole suite where coverage names none).
  One that adds to a list (`default_scope -> { order(:name) }`, a callback)
  keeps the original beside the mutated one, which a test then reaches while
  the original masks the mutant: a warm survivor of a lambda handed to a
  class-body macro is judged again in a fresh mirror, against those tests.
- **`rails_permit`** runs on the normal warm path.
- **Validations and callbacks** are class-body DSL. They execute once at load,
  so no in-process scheme can judge them. The warm run marks them
  `isolated_only`, and the isolated tier judges them by baking each deletion
  into a fresh tree: on incremental runs (`--since`, `kimera ci`, `kimera
  changed`) by default, where the scope keeps the cost small; on a full run
  with `--judge-isolated-only` (`judge_isolated_only: true`) or `--isolated`.
  Left unjudged, they are excluded from the score, and a scope where nothing
  else could be evaluated fails the gate instead of passing on nothing.
- **Out of the box.** `kimera init` on a Rails app (one with
  `config/application.rb`), or on an engine (a `Rails::Engine` or
  `isolate_namespace` under `lib/`) with a `spec/dummy` or `test/dummy` app,
  writes the `rails` group into `operators:`.
- **Zeitwerk.** Kimera calls `Rails.application.eager_load!` before overlaying,
  so lazily autoloaded constants can't escape mutation.

### Custom operators

The built-in operators cover what every Ruby app shares. The mutants that find
the most in *your* app are often ones only you can write: the call whose
deletion should break a test, the keyword whose absence should be caught.
Register them the way you add a RuboCop cop: a Ruby file named in `require:`,
loaded before the scan.

```ruby
# lib/kimera/operators/authorization.rb
require "kimera/operators"

class Authorization < Kimera::Operators::Base
  NAMES = %i[authorize authorize! policy_scope].freeze

  def key = "authorization"

  def statement? = true

  def variants(node, **)
    return unless matches?(node, NAMES)
    deletion(node)
  end
end

Kimera::Operators.register(Authorization)
```

```yaml
# .kimera.yml
require: [lib/kimera/operators/authorization.rb]
operators: [comparison, custom]   # `custom` is every operator you registered
```

`variants` receives a [Prism](https://github.com/ruby/prism) node and returns
`Variant`s. Each has a label for the report and a *directive* naming a rewrite
Kimera already knows: `selector_swap`, `drop_argument`, `kwarg_pair_drop`,
`statement_deletion`, and the rest of the built-in vocabulary. A directive type
with no handler is an error, not a silent pass. Custom rewrite handlers are not
supported yet.

Operators load once, in the CLI parent. The warm pool forks its workers and the
isolated tier bakes each mutant before spawning. So a registered operator
reaches every process that builds a mutant, with no per-worker setup.

Seven worked examples ship in [`examples/operators`](examples/operators), each
with a note on what a survivor means:

- authorization deletion
- bang-call stripping
- `perform_later => perform_now`
- HTTP status dropping
- cache-expiry dropping
- money rounding
- encrypted attribute deletion

**Audit your operator before it guards anything.** A run can't show two
failures: a directive that won't render, and one that rebuilds the original
source. The second is an equivalent mutant that survives every run and ends up
hand-added to the ignore list. Check it against a representative snippet:

```ruby
require "kimera/operators/audit"

faults = Kimera::Operators::Audit.new([Authorization.new]).faults(File.read("app/controllers/orders_controller.rb"))
expect(faults).to(be_empty)
```

---

## How it works

```
source ──Prism──▶ registry (mutation points, JSON) ──┬─▶ synthesis (Scribe) ─▶ schemata
                                                      └─▶ reporting
                                                                │
   suite ─load once─▶ overlay schemata ─▶ fork workers ─▶ per test: fork, run, record coverage
                                                        └▶ per mutant: fork, run covering tests
```

1. **Registry.** Walk the Prism AST and record every mutation point: operator,
   byte/line span, original node, and variant directives. Each gets a globally
   unique integer id. The JSON registry is the single source of truth.
2. **Synthesis.** Splice a guard into the original source where each
   schema-safe point stands, around the untouched original slice
   (`(!(::Kimera::RUNTIME.active?(102)) ? (a > b) : (a >= b))`), so every
   other line, comment and magic comment stays where it was. Memoized
   expressions (`@x ||= …`) go to a reload fallback that bakes the mutant into
   a fresh process and watches the method that holds it: the tests that call
   that method are its covering tests, and a mutant no test calls is
   `no_coverage`. Code that only runs while the suite loads goes to the
   isolated tier.
3. **Execution.** Load the suite once and overlay the schemata. From then on
   the parent runs no test: it stays in the post-boot, pre-test state, and
   every test runs in a process forked from it. Fork `--jobs` workers (each
   sets up its own test database on Rails). For the baseline, each worker
   forks a child per test, which runs it and reports its coverage; so a
   cache an earlier test filled can't hide a later caller. The whole suite
   then runs once more, in order, in one fresh process: code that run reaches
   but no single test does (a cache hit only an earlier test's state sets up)
   is judged in the isolated tier against the whole suite (skipped when
   every mutant in scope has a covering test: it could change no verdict).
   For each mutant, a worker forks a child that flips
   `Kimera::RUNTIME.active` and runs the mutant's covering tests, the
   worker's recent killers first, then the rest fastest first by their
   baseline time, stopping at the first that fails; nothing it changes
   outlives it. That failure is the kill when it came first in that
   fresh process (the baseline ran the same test, first in a fresh process,
   without the mutant); a later test's failure is confirmed by running it
   alone, or after the same tests with the mutant off and then on. Mutants
   come from one shared, heaviest-first queue, so `--jobs N` scales with
   cores even when mutants sit in one large file. Mutants the warm pass could
   not judge are then judged again, each in a fresh mirror of its own (see
   [re-judging](#re-judging-what-the-warm-pass-could-not)).

---

## Design notes & known limits

- **Test files load in the configured order.** `tests:` patterns keep their
  order (each sorted within itself, a file listed once), so a helper listed
  first (`tests: [test/helper.rb, "test/**/*_test.rb"]`) loads before the
  files that rely on it, as a Rake task's `-r` would load it.
- **RSpec filters as `rspec` applies them.** A `filter_run_including focus:
  true` that matches nothing falls back to every example when the suite sets
  `run_all_when_everything_filtered`; a baseline whose test files load but
  select no test fails with exit 1 instead of scoring every mutant uncovered.
- **Runs under your bundle.** Use `bundle exec`. A source checkout's `exe/kimera` activates the current
  directory's Gemfile before booting Kimera. `--isolated` mirrors and the
  mirrors that judge a mutant again run under the Gemfile Kimera runs under
  (`BUNDLE_GEMFILE=Gemfile.rails-8.1 bundle exec kimera run` runs them under
  the mirror's `Gemfile.rails-8.1`), and under the project's own one when
  its lockfile resolved a gem by a relative `path:` out of the project (a
  monorepo's engines), so that gem resolves there too.
- **Kimera writes its own Ruby.** Every rewrite and guard is made on Prism's
  own tree, the one the registry scanned, and `Kimera::Scribe` writes it back
  as source that reads as the very same tree: it groups operators, signs and powers by precedence
  rather than by the parentheses a mutated tree lacks, writes any string,
  symbol, regexp or backtick shape (heredocs come back as quoted strings,
  bytes that are not UTF-8 and non-ASCII characters as escapes), and keeps
  the parentheses of `|(name)|`. It tracks locals as Ruby binds them
  (patterns, captures, rescue, block and method parameters), so a method a
  local shadows is written `name()`, and a read of a local nothing binds where
  it sits is refused rather than written as a method call.
  `spec/kimera/scribe_spec.rb` holds it to reading Kimera's own sources back
  as the same trees.
- **Kimera writes only what changes.** A warm overlay and a bake splice their
  rewritten text into the original source; everything outside the rewritten
  spans is byte for byte the file you wrote: comments, every magic comment in
  any spelling and on any line of the leading comment block
  (`# frozen-string-literal: true` after a license header included),
  `__END__` and its data, the encoding, and every line's number, so
  `__LINE__`, backtraces and `source_location` read as without Kimera.
  - A mutant is guarded at the smallest expression its rewrite changes: the
    original slice first and untouched, then each mutant's alternative on the
    same line, written on that one line (an untouched part that spans lines
    is written afresh there). A bake writes the rewritten node alone, padded
    with the line breaks it lacks after it or before its closing `)`, `]`,
    `}` or `end`, parenthesised when Ruby would read it with its neighbour,
    and each bake must read back as the mutated tree. Unchanged subtrees keep
    their text, comments and line breaks. A deleted statement is written
    `()`, which reads as `nil` without `ruby -w`'s "useless use of nil".
  - A changed part of a heredoc, or of a string that spans lines (`%{...}`),
    is written in the literal's own text, a line break it drops as a `\`
    line continuation, so the heredoc stays a heredoc and no node after it
    moves (`class_eval <<~RUBY, __FILE__, __LINE__ + 1` hands down the same
    line). An argument or statement dropped beside a heredoc leaves its body
    where it was, or blank lines when the heredoc goes with it. A heredoc's
    text ends with a line break, so the mutant that drops its last one has
    no heredoc to be written as and is unmutatable.
  - A named-capture match (`/(?<n>\d+)/ =~ s`) is guarded whole, so its
    capture still binds; a visibility mutant's probe and registration go on
    the method's own lines.
  - A dropped `rescue` or `ensure` clause is guarded on the clause alone:
    its classes as a splat that rescues nothing while its mutant is on
    (`rescue *(active ? [] : [IndexError])`, a bare `rescue` as one of
    `::StandardError`), an `ensure` body under `if !active` on the body's
    lines. Its bake blanks the clause's lines (an `else` it leaves runs after
    the body). So with the mutant on, in either tier, the method runs its own
    body on its own lines: a test that reads a line (`__LINE__`, a backtrace,
    `caller_locations`) sees the mutation and nothing else. A rescue's
    guard runs when an exception reaches the clause, so its covering tests
    are the tests that raise into it: a rescue no test raises into is
    `no_coverage` ("no test reached the code it mutates"), not a survivor
    "covered" by tests that could never kill it. A point no
    expression can hold (a mutant that must break a line) has its method
    written whole, or, outside every method, the statement of the file that
    holds it, only where that keeps every line: read back with every mutant
    off, the rewrite must be the original, each node on its line, so
    `__LINE__`, a backtrace and a coverage line inside it stay put. One that
    would move a line (written whole, most methods sit on their first line)
    is not written, and its point is unguardable.
  - The file Kimera runs with every mutant off keeps the file's line layout:
    as many lines, every node on its line. Every
    bake changes no line outside its mutation (the point's lines, and the
    bodies of the heredocs it holds or sits in), so no node before or after
    the mutation point moves. A guard or rewrite that would move a line is not
    written: its point is unguardable (`kimera: x.rb: 1 mutation point(s) at
    line 3 are unguardable`) and the bake unmutatable ("what it wrote changes
    or moves a line outside the mutation"); the file itself is never written
    whole.
  - Every bake and every woven file is parse-checked. A mutant whose bake
    does not parse, or reads as the original, is reported unmutatable
    (Kimera could not write it), never killed or survived.
- **What is not mutated is listed.** The scan mutates method bodies, and the
  bodies of blocks that run on each call: `define_method`,
  `define_singleton_method`, `lambda`, `proc`, `Proc.new` and `->`. The code
  it would mutate in any other block outside a method (a class-level `map`,
  a DSL callback block), by its own lines (not those of a method it
  defines, which is mutated), and any scanned file that does
  not parse, cannot be read, or that the scan itself trips on (a Kimera bug,
  reported as one with the error, never a crash of the run), are listed
  under "Not mutated" in the text report and `unmutated` in the JSON report
  and the registry, with the reason.
- **Schema-unsafe mutants.** Code that runs once at load (class/module bodies,
  constants) or is memoized can't be toggled in a warm process. Kimera mutates
  only inside method bodies and routes memoized points to a fork-per-mutant
  reload fallback.
- **Class bodies run once.** To install its guards, a warm worker evaluates
  each mutated file again. For a file the suite already required, Kimera first
  blanks every class-body statement that holds no mutant, so `include`,
  `class_attribute`, `pre_check`, registrations and other DSL calls keep the
  state the real load left. What runs again: the methods and lambdas that
  carry mutants (and the class, module or `included do` blocks around them),
  visibility calls, `require`s (not one under a modifier condition: `require
  "x/railtie" if defined?(Rails)` may hold now when it did not at load),
  local variables, and an `alias` of a mutated
  method. A concern's trimmed `included` block runs on the classes that
  already include it; a class that includes the concern later gets the full
  block, then the mutated statements. A class keeps its superclass even if the
  constant naming it was reassigned, and a `Struct.new`, `Data.define`,
  `Class.new` or `Module.new` constant is reopened, not replaced, as is a
  constant any other factory builds from a block that defines methods
  (faraday's `RequestOptions = Options.new(...) do ... end`), so references
  taken at load keep the instrumented class. A constant holding a lambda or
  proc (`BY_SYMBOL = ->(record) { ... }`) stays bound to the one made at load,
  since a registry built from it (`self.chain = [BY_SYMBOL]`) keeps that
  object: its body and its parameters' defaults are `isolated_only`, judged
  in the isolated tier. Pending autoloads along the constants a file opens
  are resolved first, as the suite would resolve them, and a file they load
  (the one an autoload names, or one it requires) is then trimmed. Of the files nothing required before the overlay, one whose
  classes and modules hold only methods, constants and `require`s is
  evaluated whole; any other (a class body that sets `@limit = 100` or calls
  `after Parser`) is never evaluated, and its mutants are `no_coverage`, as
  are those of a file Kimera could not load either (a gem the suite never
  requires), with the error in the detail. A method a file
  loaded later redefined (a wrapper around an `alias_method` chain) keeps
  that definition; the alias then calls the overlaid original, so its
  mutants are covered. A wrapper that holds the method it replaced (a
  memoizer such as Adamantium's `memoize`) never calls the overlay: its
  method's mutants are judged again in a fresh mirror.
- **An unwritable tree costs one method, not a file.** When a guard leaves a
  tree Kimera can't write faithfully (a local read it unbinds), only those
  points are dropped; when the whole file still won't write, Kimera guards and
  writes each method that carries points and splices those back into the
  original text. The rest of the file stays verbatim and mutatable.
- **Standing risks and mitigations:**
  - State a test leaves behind: no process-local state (a memo cache, a
    registry, a class variable, an `ENV` flag, a constant) carries from one
    test to another in the baseline, or from one mutant to another: each runs
    in its own forked process. What lives outside the process still does:
    rows a non-transactional test commits (`--isolate-db` rolls each mutant's
    back), files, servers. Within one mutant's run its covering tests share a
    process, as in a plain run of the suite. Code reached only through state
    an earlier test leaves is found by the in-order run and judged against
    the whole suite in a fresh mirror (under `--no-rejudge` it stays
    `no_coverage`, with that reason in its detail). A test that only fails
    when an earlier test ran first with the mutant, and that does not run
    the mutated code itself, does not kill it.
  - Order-dependent suites: a test that passes when the suite runs in order
    but fails alone in a fresh process can't be judged this way. The run
    stops at the baseline, calls the suite order-dependent, and names those
    tests; make each set up the state it needs.
  - The cost: one fork per baseline test and per mutant, each forked
    process starting cold (a Rails test reloads its fixtures in each), and,
    when a mutant in scope has no covering test, one more run of the whole
    suite in order. See the numbers in
    `eval/results/README.md`.
  - Selector-induced hangs: a soft timeout on each covering test a mutant runs
    (`--soft-timeout`, 5s), plus a watchdog that SIGKILLs a worker whose test
    runs past `--hard-timeout`, so a replacement pulls from the shared queue.
    Both time one test at a time: a mutant many tests cover is not a `timeout`
    for that alone. Raise `--soft-timeout` if single tests run slow under
    `--jobs` load. Below the soft timeout, a warm test that passes but runs
    far past its baseline time, twice, is a `timeout` too (see
    [relative time budget](#relative-time-budget)).
    Before the kill it asks the worker for every thread's backtrace (SIGQUIT)
    and puts them in the verdict's `detail`, or in the baseline error. A test
    that runs past the soft timeout with the mutant on is then run alone with
    the mutant off: the mutant is a `timeout` (detected) only when that run
    passes in under half the soft timeout. A test that is slow on its own (or
    fails on its own) kills nothing; the other covering tests are tried, and
    if none kills the mutant it is unjudged, its detail saying to raise
    `--soft-timeout`. So a test whose own time sits near the limit cannot turn
    slow-but-passing runs into kills, whatever the machine's load.
    The interrupt reaches only the test's own thread, so threads it started
    may still hold connections and locks; they end with the mutant's process.
  - Code under test that calls `exit` or `abort` (a rake task, a CLI entry
    point): RSpec and Minitest let the `SystemExit` through, so it would end
    the worker. Kimera records it as that test's failure instead, after the
    test's teardown, with the status, where it was called, and `abort`'s
    message (`SystemExit: exit(1) called from lib/tasks/import.rb:12:in
    'Kernel#abort': no such file`). A mutant that makes a test exit is killed;
    a baseline test that exits turns the baseline red. `exit!` still ends the
    process, and interrupts still stop the run.
  - A test that sends its own process a signal (`Process.kill("TERM",
    Process.pid)` to exercise graceful shutdown) behaves as it does outside
    Kimera: if nothing traps the signal, it ends the process. Trap it in the
    test, or leave the test out with `--exclude-test`. A test or mutant whose
    process dies this way is reported with the signal, the exception and
    where it was raised.
  - Slow tests under parallel load: a baseline test whose worker hits the hard
    timeout reruns once, alone. If it passes, the run goes on with a notice and
    the stacks. If it times out again, the baseline is red.
  - Equivalent mutants: a small operator set plus human suppression hooks, not
    a solver.
- **`.rspec` and suite hooks are honored.** The RSpec adapter applies the
  project's `.rspec` (`--require spec_helper`/`rails_helper`, the `spec` load
  path) as the `rspec` executable does; its `--require` files load with the
  test files, so code they run while loading is traced. It fires
  `config.before(:suite)` once, in the process that loads the suite, before the
  baseline, and `after(:suite)` at the end; workers forked from it never run
  them again. The Minitest adapter runs `Minitest.after_run` hooks the same
  way, once, in that process, when the run ends (resque stops the Redis its
  helper started); a hook that raises or exits is reported and the run goes
  on, and SimpleCov's own hook is left out, since it would write the coverage
  of kimera's process over the project's report. Libraries install global
  switches there: `webmock/rspec` calls `WebMock.enable!` only in that hook.
  Without it, every stubbed HTTP request would reach the real network.
- **Parallel runs need parallel state.** With `--jobs N` on a Rails app, Kimera
  runs Rails' parallel-testing fork hooks (on Rails before 8.1 too, which has
  no `parallelize_test_databases` switch). Each worker gets its own database
  (`app_test_0`, `app_test_1`, …), as with `rails test -j`, and
  `TEST_ENV_NUMBER` (`""`, `"2"`, …): a `database.yml` that names the database
  by it gets each worker's database created and loaded. A suite that builds
  its database as it loads (migrates it, as thredded's does) leaves no schema
  file for Rails to load: kimera copies the database the parent prepared for
  each worker and mirror past the first, after the parent disconnects
  (`CREATE DATABASE app_test_1 TEMPLATE app_test` on PostgreSQL, a copy of the
  file on SQLite), and drops the copies when the run ends. An in-memory SQLite
  database is never renamed; each fork keeps its own copy of the schema. A
  library suite that configures no test database and connects in a `before`
  (`establish_connection(adapter: "sqlite3", database: ":memory:")`) has no
  schema to load either: its workers connect as it does.
  When workers would share one database (another adapter), kimera says so.
  Anything *else* your suite shares
  (Redis, Elasticsearch, a temp directory) needs the same treatment. Register
  a hook and Kimera runs it:
  `ActiveSupport::Testing::Parallelization.after_fork_hook { |i| ... }`.
  Without one, concurrent examples fight over one keyspace. That reads as a red
  baseline, or worse, as kills that are really collisions. A suite that is not
  parallel-safe at all (thor's tests share `spec/sandbox`, sinatra's write and
  delete `test/file.txt`) is green with `--jobs 1` and red with more: a red
  baseline that ran on several workers says so, and `kimera doctor
  --check-baseline` warns before a run. Give each test its own path
  (`Dir.mktmpdir`) and port, or set `jobs: 1`.
- **Score definition.** `score = killed / evaluable`.
  - Killed includes timeouts and errors (observable misbehaviour).
  - Evaluable excludes `no_coverage`, `ignored`, `isolated_only`,
    `unmutatable`, and `harness_error` mutants. Each is reported separately.
    `uncovered_by_unit` (under `attribution: unit`) is evaluable and not
    killed.
  - An `unmutatable` mutant is one Kimera could not instrument for the warm
    run (its file or method failed to re-emit or load); the detail says why.
    It never gates, and it is not `no_coverage`: a test may well run it.
  - A `harness_error` is a mutant Kimera could not judge: its worker died, or
    its reply was unreadable, and a fresh mirror could not judge it either.
    It is not a kill. It gates via `--max-errors`
    (default 0). A pool that never produces a result aborts the run. When a
    worker died, the `detail` says how (`died on signal 15 (SIGTERM)`,
    `exited 1`) and, if Ruby raised something, the exception and its frames.
  - Uncovered mutants count: by default (`count_no_coverage: true`) each
    scores as not killed, so the score is killed over every mutant a test
    could have killed, run or not, and the gate fails on them in every
    command, `kimera run` included. `count_no_coverage: false`
    (`--no-count-no-coverage`) reports them without scoring them;
    `--fail-on-no-coverage` still fails the gate on them. The report's `run`
    section records the setting.
  - A gate that killed nothing while `isolated_only` or `unmutatable`
    mutants were in scope fails ("0 of N mutants killed"), naming
    `--isolated`.
- **No constant outside `Kimera`.** Every synthesized guard dispatches through
  `::Kimera::RUNTIME`, the process's one `Kimera::Runtime`, bound once: a
  second copy of `kimera/runtime.rb` keeps the runtime it finds. Kimera's
  dependency does define a top-level constant in the process that loads your
  suite (`Prism`), so a project with its own top-level `Prism` cannot load
  beside it; the load error names the constant and the gem, and the fix is a
  namespace.
- **One load path.** Each test file's nearest `test/` or `spec/` folder, the
  project's own `test/` and `spec/`, and the folders `load_path:` names go on
  the load path when the suite loads, and the same `-I` flags go into
  `kimera doctor`'s commands, the isolated tier's children and every printed
  "reproduce without kimera" command.
- **Warnings as the test task sets them.** `Rake::TestTask` and
  `Minitest::TestTask` run the suite with `ruby -w` unless the task sets
  `warning = false`. For a Minitest suite Kimera reads the Rakefile's test
  task (the one named `test`, or the first) and does the same: the suite loads
  with `$VERBOSE` on, and `-w` goes into `kimera doctor`'s commands, the
  isolated tier's children and every printed reproduce command. When a red
  baseline is green with warnings the other way, doctor says so.
- **Methods a block defines.** A `def` inside a block a DSL runs
  (`RSpec.shared_examples_for`, `shared_context`, `Module.new`) lives on each
  module that ran the block, which the source cannot name. Before the warm
  overlay runs, Kimera notes every module whose method came from such a def,
  then defines the instrumented def on each, in the def's lexical scope and
  with its visibility, so the examples that run it cover it.
- **A Method taken at load stays as loaded.** `REGISTERED = method(:to_int)`
  holds the definition it was taken from. Once the warm overlay redefines
  `to_int`, the two are not `==` (Ruby compares definitions) and the one
  taken still runs the unmutated code. A test comparing them fails under
  Kimera only; the harness error names each such method and the
  `--exclude` that leaves its file out.
- **Minitest class hooks.** Each test runs through its class's suite
  runner (Minitest 6's `run_suite`, Minitest 5's `run`) and its per-test
  runner, as a plain run does, so a fixture the class sets up there (excon
  starts its test servers in `run_suite`) and minitest-hooks'
  `before(:all)`/`around(:all)` run around it, and a failing class hook
  fails the test. A class Minitest runs in parallel runs its test in place.
- **Locale.** Kimera reads its files, reports and pipes as UTF-8 whatever
  `LANG` says, so it runs with `LANG` unset or `LANG=C`.

## Mutation-testing Kimera with Kimera

Kimera gates itself at zero survivors (`bundle exec kimera run`, configured by
the repo's `.kimera.yml`). The warm path can't judge its own harness: the
runtime selector would recurse, and a mutant in the RSpec adapter can disable
the runner judging it. Those files are excluded or reported as
`isolated_only`. `bundle exec kimera run --isolated` judges them in fresh
subprocesses that share nothing with Kimera's runtime.

## Development

```sh
bundle install
bin/spec                 # run the test suite
COVERAGE=1 bin/spec      # run with line+branch coverage (SimpleCov)
bin/model-check          # model-check the worker pool (needs Java)
```

`spec/property/` holds property-based specs ([pbt](https://github.com/ohbarye/pbt)).
They generate random Ruby methods and check, on those samples, the
invariants every run relies on:
- with mutant k active, the compiled schemata reduces to mutant k's source,
  and with none active, to the original. This is checked symbolically and by
  running both on random calls, including calls that omit optional arguments.
  The one-page equivalence contract, with its exclusions, is at the top of
  `spec/property/support/schemata_projection.rb`;
- no mutant is the original program, and no two mutants at a point are the
  same program;
- mutant ids, keys (including keys whose line moved) and registry JSON are
  stable;
- diff parsing never misses a changed line, checked against real `git diff`;
- the gate passes and fails exactly at its documented thresholds.

A failure prints a shrunk counterexample and its seed. `PBT_SEED=<seed>`
replays a run, and `PBT_SCALE=10` searches ten times deeper. Property tests
sample; they don't prove.

[`formal/`](formal/README.md) holds a TLA+ model of the warm worker pool.
TLC checks it exhaustively for three small configurations of mutants and
jobs, which says nothing about other sizes or about the Ruby code directly.
`spec/property/worker_pool_spec.rb` runs the real pool against scripted
children that inject the model's faults (fault injection, not conformance).

`examples/` holds the runnable fixtures the integration tests drive
(`sample_app` for RSpec, `minitest_app` for Minitest) and a Rails app CI runs
end to end (`rails_app`, `bin/e2e`).

`eval/run` measures a kimera checkout (give it the checkout's path)
against the gaps an independent review found, each verdict checked against
an oracle that bakes the mutant into a copy of the project and runs the plain
test command in a fresh process. [`eval/results/README.md`](eval/results/README.md) has the
cases and the numbers before and after the fixes.

## License

MIT
