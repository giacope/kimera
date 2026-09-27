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
  reparse or reload per mutant. On an 8-core Apple M3, dry-inflector's `lib`
  (742 mutants, `--operators all`) runs in 17s with `--jobs 4`. Kimera's own
  codebase (2,552 mutants) takes about 6 minutes with `--jobs 8`, mostly in the
  fresh-process tier for harness-critical files.
- **Parallel.** Warm workers, forked once, pull mutants from one shared
  heaviest-first queue. A single large file spreads across every core.
- **Rails-ready.** Opt-in transaction rollback (`--isolate-db`), per-worker
  test databases via Rails' parallel-testing hooks, and 4 Rails operator
  families (strong params, validations, callbacks, associations).
- **Built for CI.** `kimera changed` mutates only the lines a PR touched.
  `kimera ci` fails the build on any survivor or untested change.
- **Low noise.** A small default operator set. 19 extended families are one
  flag away, and you can write your own.
- **Honest verdicts.** Code the warm path can't judge safely is reported
  separately, never scored. `--isolated` re-checks any mutant in a fresh
  process.
- **Small.** Ruby >= 3.4 (CI covers 3.4 and 4.0), RSpec or Minitest, and two
  dependencies: [Prism](https://github.com/ruby/prism) and
  [unparser](https://github.com/mbj/unparser).

```sh
$ bundle exec kimera run app --since origin/main --tests 'spec/**/*_spec.rb'
mutants=28 killed=17 survived=5 timeout=0 error=0 no_coverage=6 score=77.3%

  survived #1  app/models/discount.rb:18  [<= => <]
    - order_total <= 0
    + order_total < 0
    covered by 7 test(s): ./spec/discount_spec.rb[1:1:1], …
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

**2. Generate a config.** `init` detects RSpec or Minitest, your source roots
(`app/`, `lib/`), and your test glob. It writes `.kimera.yml`, and adds a line
to `AGENTS.md` pointing AI coding agents to `kimera skill`: a guide to running
Kimera and triaging survivors without gaming the score. It matches your
installed version and works with any agent that can run a shell command.

```sh
bundle exec kimera init
```

**3. Check the setup.** `doctor` confirms source and test discovery, Git, and
Rails parallel-safety. `--check-baseline` also runs your suite once to confirm
it is green.

```sh
bundle exec kimera doctor --check-baseline
```

**4. Run it.** Start with the code your branch changed, then widen.

```sh
bundle exec kimera changed          # lines changed since origin/main (or main)
bundle exec kimera run app/models   # one directory
bundle exec kimera run              # every path in .kimera.yml
```

**5. Triage survivors.** Save a report so you can dig in without rerunning the
suite.

```sh
bundle exec kimera run --report tmp/kimera/report.json
bundle exec kimera report tmp/kimera/report.json --status survived
bundle exec kimera mutant 42 --report tmp/kimera/report.json
```

For each survivor, write the test that kills it. If a mutant is truly
equivalent, add it to `ignore:` in `.kimera.yml` with a reason (see
[Configuration](#configuration)).

**6. Gate pull requests.** `kimera ci` fails on any survivor or uncovered
mutant. It writes `tmp/kimera/report.json` and prints GitHub annotations. Pass
`--since` to mutate only the PR's lines (this needs full Git history):

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
      - run: bundle exec kimera ci --since origin/${{ github.base_ref }}
```

> **Adopting on an existing suite?** Snapshot today's survivors as reviewed
> debt, so the gate blocks only *new* holes:
> `bundle exec kimera baseline create tmp/kimera/report.json --reason "adopting Kimera"`.
> Then add the printed `baseline:` line to `.kimera.yml`.

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

# Incremental: mutate only lines changed since main, gate CI, resume on retry
bundle exec kimera run app --since origin/main \
  --session tmp/kimera.json --max-survivors 0 --report tmp/report.json

# Also fail when a changed line has no covering test
# (a no_coverage mutant is untested new logic, not a pass)
bundle exec kimera run app --since origin/main --fail-on-no-coverage

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
# test files ...", and "narrowed": true in the JSON report's run section)
bundle exec kimera run app/models/order.rb --tests 'spec/models/order_spec.rb'

# Drop spec files that can't run this way (order-dependent, need a browser)
# without rewriting the whole --tests glob
bundle exec kimera run app --exclude-test 'spec/system/**/*_spec.rb'

# Judge every mutant in a fresh subprocess: bake it into a mirror of the tree
# and run its covering tests under plain rspec. Slower, but trustworthy even
# for code that can't be instrumented in-process.
bundle exec kimera run app --isolated
```

### Daily and CI workflows

```sh
# Mutate only the PR's changed lines (origin/main, falling back to main)
bundle exec kimera changed --report tmp/kimera/report.json

# Strict gate: zero survivors, no uncovered mutants, a JSON artifact, and
# GitHub annotations. Override with --format sarif/json.
bundle exec kimera ci

# Continue triage without rerunning the suite
bundle exec kimera report tmp/kimera/report.json --status no_coverage
bundle exec kimera mutant 42 --report tmp/kimera/report.json

# Snapshot pre-existing survivors while adopting Kimera
bundle exec kimera baseline create tmp/kimera/report.json --reason "adopting Kimera"
# Add the printed `baseline:` entry to .kimera.yml, then review it in code review
bundle exec kimera baseline review .kimera-baseline.yml
```

### Output formats and exit codes

- `--format json`, `ndjson`, `github`, and `sarif` write *only* that format to
  stdout. Progress and diagnostics go to stderr.
- `--report FILE` always writes the canonical JSON report for later triage.
- Text output honors `NO_COLOR`. `--no-color` forces it off.
- `--quiet` suits scripts that only need an artifact. `--verbose` prints the
  resolved scope. `--log FILE` keeps the final text report.
- `--pidfile FILE` writes kimera's process id to FILE when the run starts and
  removes the file when the run ends, whether it passes, fails or errors
  (short of `kill -9`). A script that waits on a background run can watch
  that pid; `pgrep -f "kimera run"` also matches the shell that started it.

Exit codes:

- **`0`**: pass.
- **`2`**: the gate failed. Survivors exceed the threshold (default: any
  survivor), or a mutant in scope has no covering test under
  `--fail-on-no-coverage`, ignored mutants exceed `max_ignored`, or more
  mutants than `--max-errors` (default 0) could not be judged.
- **`1`**: the baseline is not green, the pool cannot keep a worker alive, or
  the invocation is invalid. Paths that match no source files, `--tests` that
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

`kimera doctor` warns when it finds an ungated `minimum_coverage`.

Each isolated mirror is a copy of the project root with some exceptions:
`.git/` and `coverage/` are left out, `tmp/` and `log/` start empty, and
`vendor/`, `node_modules/` and `.bundle/` are symlinked to the originals. The
exception is a directory that holds a mutated file, which is always copied.
Before judging any mutant, `--isolated` runs the unmutated suite once in a
mirror. If it isn't green there, the run stops with exit 1 and the error.

### Progress output

During a run, a progress bar tracks each phase on stderr. It shows only when
stderr is a tty; `--[no-]progress` overrides. Completed phases stay visible:

- `baseline` records coverage.
- `mutants (warm)` uses the shared worker pool.
- `mutants (isolated)` evaluates the subset routed to fresh mirrors.

The last two labels appear only when a run uses both strategies. Output the
suite prints during mutant evaluation is swallowed, since mutated code warns,
raises, and logs freely. Verdicts travel back as structured results.

```
baseline [========================]  895/895  100%  0:03
mutants (warm) [========================]  2104/2104  100%  killed=1867 survived=137 no_coverage=100  0:59
mutants (isolated) [===========>            ]  224/445  50%  killed=196 survived=0 no_coverage=19 timeout=9  2:01
```

---

## Configuration

`.kimera.yml` in the project root sets defaults. Command-line flags override
them.

```yaml
framework: rspec
paths: ["app/**/*.rb"]
tests: ["spec/**/*_spec.rb"]
exclude: ["app/legacy/**/*.rb"]
operators: [comparison, boolean_connective, boolean_literal, statement_deletion, negation, conditional]
# Ruby files loaded before the scan, for custom operators.
require: []
jobs: 4
max_survivors: 0
# Fail when any mutant in scope lacks a covering test. Best on incremental
# runs, where "no coverage" means the PR adds logic no test executes.
fail_on_no_coverage: false

# The gate fails when more than this many mutants are ignore-listed. Marking
# one more mutant equivalent means raising this number in the same diff, so
# the ignore list stays a justified decision, reviewed in the diff that makes
# it, not a shortcut past a test.
max_ignored: 1

# Accepted pre-adoption survivors, merged with the ignore rules below.
# Uncomment only after creating the file with `kimera baseline create`.
# baseline: .kimera-baseline.yml

# Known-equivalent mutants. Equivalence is undecidable, so Kimera doesn't
# guess: you mark a mutant and it stops being a survivor. An entry without
# a reason: is rejected at startup.
ignore:
  - file: app/models/discount.rb
    line: 33
    label: "> => >="
    reason: known equivalent at the 50 boundary (spend > 50 vs >= 50 both hit the tier)
```

---

## Operators

The *default* set is small and low-noise:

- comparison operators (boundary and negation)
- boolean connectives and boolean literals
- deletion of side-effecting statements
- `!x => x`
- forced `if` conditions

Memoization is not a mutation target. Dropping a memo only recomputes an equal
value, so that mutant would always survive. `@x ||= …` has no such mutant, and
neither does a guard that opens a method: `return @x if defined?(@x)`,
`return @x if @x` (with `@x` assigned later in the method), or `return if @x`
followed by `@x = true`. Everything the method computes is still mutated. A
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
| `return_value` | `return x => return nil`; def-body tail `=> nil` |
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

Turning them all on typically triples the mutant count. Adopt them through the
baseline burn-down workflow, not by flipping them on in a mature gate.

**Contract operators.** The five from `index_fetch` through `default_argument`
each remove an affordance the code grants its callers. A survivor means no test
exercises the case the affordance exists for. `index_fetch` and
`kernel_coercion` are equivalent wherever the key is always present or the
value already has the target shape. That is the normal case for an options hash
built from a defaults literal. Scope them to data that crosses a boundary
(params, parsed JSON, ENV); on internal bookkeeping they are noise.

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
| `rails_validation` | delete `validates ...` | a validation no test ever violates |
| `rails_callback` | delete `before_action :authenticate_user!` etc.; drop one action from an `only:`/`except:` list | an unguarded path (or a guarded action) no test exercises |
| `rails_association` | `has_many :posts, dependent: :destroy` => drop `dependent:` | orphaned-record cleanup no test observes |

- **Scope lambdas** are mutated on the *warm* path. A `-> { ... }` body at class
  level re-executes per call, so ordinary operators mutate it safely
  (`scope :active, -> { where(active: true) }`). Run-once `do ... end` DSL
  blocks (`included do`, `class_eval`) stay excluded.
- **`rails_permit`** runs on the normal warm path.
- **Validations and callbacks** are class-body DSL. They execute once at load,
  so no in-process scheme can judge them. The warm run reports them as
  `isolated_only` (excluded from the score, never gating). `--isolated` gives
  the verdict by baking each deletion into a fresh tree.
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

  class << self
    def key = "authorization"

    def statement? = true
  end

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

faults = Kimera::Operators::Audit.faults([Authorization.new], File.read("app/controllers/orders_controller.rb"))
expect(faults).to(be_empty)
```

---

## How it works

```
source ──Prism──▶ registry (mutation points, JSON) ──┬─▶ synthesis (unparser) ─▶ schemata
                                                      └─▶ reporting
                                                                │
   suite ─load once─▶ overlay schemata ─▶ baseline+coverage ─▶ warm worker-pool kill loop
```

1. **Registry.** Walk the Prism AST and record every mutation point: operator,
   byte/line span, original node, and variant directives. Each gets a globally
   unique integer id. The JSON registry is the single source of truth.
2. **Synthesis.** Replace each schema-safe point with a nested guarded dispatch
   (`if Kimera::Runtime.active?(102) … else …end`) and unparse. Memoized
   expressions (`@x ||= …`) and load-time-only code go to a reload fallback, so
   they can never read as a false "survived".
3. **Execution.** Load the suite once and overlay the schemata. Check the
   baseline is green while recording per-test coverage. With `--jobs N`, the
   coverage pass also fans out across the warm pool (each worker runs a slice
   of the examples). Then fork the warm pool and stream mutants to it from one
   shared, heaviest-first queue. For each mutant, flip `Runtime.active` and run
   only its covering tests. The queue is shared, not split by file, so
   `--jobs N` scales with cores even when mutants sit in one large file.

---

## Design notes & known limits

- **Runs under your bundle.** `unparser` pulls in a `diff-lcs` version that can
  conflict with `rspec-expectations` outside a resolved bundle. Use
  `bundle exec`. A source checkout's `exe/kimera` activates the current
  directory's Gemfile before booting Kimera.
- **Schema-unsafe mutants.** Code that runs once at load (class/module bodies,
  constants) or is memoized can't be toggled in a warm process. Kimera mutates
  only inside method bodies and routes memoized points to a fork-per-mutant
  reload fallback.
- **An un-emittable node costs one method, not a file.** `unparser` refuses to
  re-emit some valid Ruby (an interpolated `%r{}x` pattern, for example). When
  a whole file won't round-trip, Kimera guards and re-emits each method that
  carries points and splices those back into the original text. The offending
  constant stays verbatim and the rest of the file stays mutatable.
- **Standing risks and mitigations:**
  - Global-state leakage: opt-in transaction rollback (`--isolate-db`), cache
    resets, periodic kill-confirmation, one mutant per warm worker at a time.
    Every warm kill is confirmed: the killing test must pass with the mutant
    switched off, then fail again with it on. If it doesn't, state the worker
    kept from earlier tests failed it, not the mutant. The worker is retired,
    the mutant is judged again on a fresh one, and the report lists the test
    under state-leak warnings. On the fresh worker, a test that still fails
    without the mutant is left out. If no other test confirms a kill, the
    mutant is `harness_error`.
  - Selector-induced hangs: a soft per-mutant timeout, plus a watchdog that
    SIGKILLs a wedged worker so a replacement pulls from the shared queue.
    Before the kill it asks the worker for every thread's backtrace (SIGQUIT)
    and puts them in the verdict's `detail`, or in the baseline error. A test
    interrupted by the soft timeout is a `timeout`, not the mutant's killer.
  - Code under test that calls `exit` or `abort` (a rake task, a CLI entry
    point): RSpec and Minitest let the `SystemExit` through, so it would end
    the worker. Kimera records it as that test's failure instead, after the
    test's teardown, with the status, where it was called, and `abort`'s
    message (`SystemExit: exit(1) called from lib/tasks/import.rb:12:in
    'Kernel#abort': no such file`). A mutant that makes a test exit is killed;
    a baseline test that exits turns the baseline red. `exit!` still ends the
    process, and interrupts still stop the run.
  - Slow tests under parallel load: a baseline test whose worker hits the hard
    timeout reruns once, alone. If it passes, the run goes on with a notice and
    the stacks. If it times out again, the baseline is red.
  - Equivalent mutants: a small operator set plus human suppression hooks, not
    a solver.
- **`.rspec` and suite hooks are honored.** The RSpec adapter applies the
  project's `.rspec` (`--require spec_helper`/`rails_helper`, the `spec` load
  path) as the `rspec` executable does. It fires `config.before(:suite)` once
  before the baseline and `after(:suite)` at the end. Libraries install global
  switches there: `webmock/rspec` calls `WebMock.enable!` only in that hook.
  Without it, every stubbed HTTP request would reach the real network.
- **Parallel runs need parallel state.** With `--jobs N` on a Rails app, Kimera
  runs Rails' parallel-testing fork hooks. Each worker gets its own database
  (`app_test_0`, `app_test_1`, …), as with `rails test -j`, and the suite's
  `before(:suite)` setup replays against it. Anything *else* your suite shares
  (Redis, Elasticsearch, a temp directory) needs the same treatment. Register
  a hook and Kimera runs it:
  `ActiveSupport::Testing::Parallelization.after_fork_hook { |i| ... }`.
  Without one, concurrent examples fight over one keyspace. That reads as a red
  baseline, or worse, as kills that are really collisions.
- **Score definition.** `score = killed / evaluable`.
  - Killed includes timeouts and errors (observable misbehaviour).
  - Evaluable excludes `no_coverage`, `ignored`, `isolated_only`,
    `unmutatable`, and `harness_error` mutants. Each is reported separately.
  - An `unmutatable` mutant is one Kimera could not instrument for the warm
    run (its file or method failed to re-emit or load); the detail says why.
    It never gates, and it is not `no_coverage`: a test may well run it.
  - A `harness_error` is a mutant Kimera could not judge: its worker died, or
    its reply was unreadable. It is not a kill. It gates via `--max-errors`
    (default 0). A pool that never produces a result aborts the run.
  - Uncovered mutants don't lower the score, unlike some tools.
    `--fail-on-no-coverage` closes that gap.
- **One top-level constant.** `require "kimera"` defines `::MutantRuntime`,
  aliased to `Kimera::Runtime` unless already bound. Every synthesized guard
  dispatches through it. It stays top-level so an outer measurer can pre-bind
  it. It is the only constant Kimera adds outside its namespace.

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
```

`examples/` holds the runnable fixtures the integration tests drive
(`sample_app` for RSpec, `minitest_app` for Minitest).

## License

MIT
