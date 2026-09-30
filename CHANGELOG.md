# Changelog

## Unreleased

- `statement_deletion` no longer deletes the expression an interpolation
  embeds. The walker gave every statement inside `"#{…}"` a statement
  position, so `raise NotDefinedError, "no scope for #{find(object)}"` had
  a mutant deleting `find(object)`: a change to the message's text, not the
  deletion of a side-effecting statement the default operator promises.
  Such mutants sat mostly on error and log messages (143 of Lobsters' 1,201
  survivors). The last statement of an interpolation, in a string, symbol,
  regexp, backtick command or heredoc, is now not a statement position.
  Statements before it (`"#{log; x}"`), whose values are discarded, and
  statements in a block inside one stay deletable, and every other operator
  still mutates inside interpolations; `string_literal` covers message
  text. Kimera's own default set loses 232 such mutants.
- A mutant that slows every covering test without failing any no longer
  costs the whole run. Deleting `pool.shutdown` in once-campfire made each
  of 407 tests wait out two `wait_for_termination(1)` calls, about 2s more
  each and never near the 5s soft timeout, so the mutant ran them all and
  survived after 870s, about 90% of the run's wall time. The coverage pass
  now records each test's time, and in the warm pass a covering test that
  passes but runs past its baseline × 10 + 1s, then keeps to that budget
  with the mutant switched off and runs past it again with it on, makes the
  mutant a `timeout` (detected), with a `detail` naming the test, both runs
  and the budget. A slow first test on a fresh worker or a GC pause does not
  repeat, so it is not a verdict. `--timeout-factor` and `--timeout-slack`
  (`timeout_factor:`, `timeout_slack:`) tune it, and `--no-relative-timeout`
  (`relative_timeout: false`) keeps the old behavior. Tests with no baseline
  (`--no-coverage`), and the isolated and reload tiers, keep only the
  absolute timeouts.
- A mutant whose effect outlives its switch-off is judged, not left
  unjudged. A memoized class-level table the mutant poisoned, a `require` a
  later test satisfied, or rows a crashed `before(:all)` left behind made
  the warm confirming run fail without the mutant too, even on a fresh
  worker, so the mutant was `harness_error` and failed the default
  `max_errors: 0` gate, though it was really killed (3 of money's 511
  mutants), and whether it read as unjudged could depend on test order.
  After the warm pass, Kimera now judges each mutant it could not judge
  again in a fresh isolated mirror of its own, against its covering tests;
  a kill stands only if those tests pass in another fresh mirror without
  the mutant. The report carries that verdict and keeps the warm detail as
  the row's `note` (text, JSON, `github` and `sarif`). `--no-rejudge` (or
  `rejudge: false`) keeps the old behavior.
- The worker-pool model (`formal/`) is now checked against the code, not
  only on its own: TLC validates each run of the pool's property spec, with
  scripted children and with the real `Shift`, step by step against it. The
  model also represents half-written lines, and finds the half-written-line
  hang (below) when the old blocking read is put back. CI checks it
  exhaustively up to 3 mutants on 2 jobs, and its invariants up to 5 on 2
  and 4 on 3.

- Kimera's full self-host run passes its own gate again. Seven mutants
  survived it, one had no covering test, and one was unjudged: the isolated
  child died of an `Interrupt` from a fixture test that a broken RSpec
  narrowing let run. Each is now killed by a test (per-worker database
  teardown, the doctor's coverage-floor probe, isolated verdict timing, the
  test-exit fixture), or the code it sat on is gone: a worker's deadline was
  renewed a second time after each result, the ignore-rule glob was matched
  again on points already selected by it, and see the next entry.
- A swapped `&&`/`||` is written with only the parentheses its grouping
  needs, like every other bake: `a && b && c` with its outer `&&` swapped
  reads `a && b || c`, one operator away from the original, not
  `(a && b) || c`. The swap wrapped every `&&`/`||` operand itself, which
  predates the regrouping below; both wrote the same program.
- No mutant leaves a range or regexp literal where Ruby tests a condition.
  Ruby reads a range there as a flip-flop and a regexp as a match against
  `$_`, and no source text keeps the plain value: `!(a...b).cover?(x)` with
  the chain link `.cover?` dropped baked to `!(a...b)`, a flip-flop, not the
  negated range the mutation meant, and `if (a...b).to_a` with `.to_a`
  unwrapped ran the (always truthy) range in warm runs, where the guard
  around it hides the condition, but a flip-flop in `--isolated` and reload.
  Kimera now drops such a variant, from any operator, when it scans a point:
  under `if`, `unless`, `elsif`, `?:`, `while`, `until`, `!` and `not`, and
  through parentheses and the operands of `&&`, `||`, `and` and `or` there.

- A bake keeps a sign that belongs outside a numeric literal. unparser
  wrote minus or plus over a call chain rooted at a literal (`-(0.succ)`)
  as `-0.succ`, and a negative literal raised to a power (`(-1) ** 2`) as
  `-1 ** 2`; Ruby reads the sign as the literal's, so `--1.succ` with
  `-1 => 0` baked to `1` where the warm run returned `-1`. `--isolated` and
  the reload tier judged that different program. Kimera now parenthesizes
  such an operand in the tree before unparser writes it, alongside the
  regrouping below, so it also reads back as the same tree inside an
  interpolated string (`"x#{-(0.succ)}"`), and synthesis, bakes and
  rendered directives all gain it.
- `--isolated` and the reload tier report a point the parser folds into its
  parent (the inner `-1` of `--1`) unmutatable, as warm runs do. Its bake
  found no node to mutate and returned the file unchanged, so each of its
  mutants survived, and failed the gate, though no test could kill it.
- A mutant that regroups an expression is baked as the program it is.
  unparser takes grouping from the parentheses in the parsed source, which a
  mutated tree lacks: with the inner `&&` of `x = p && q && r` swapped to
  `||`, the bake read `x = p || q && r`, which is `p || (q && r)`, and
  `Array(a || b).size` with `Array()` deleted baked to `a || b.size`. Warm
  runs judged the intended mutant, but `--isolated` and reload judged the
  other program. Kimera now writes each operand that binds more loosely than
  its place allows in parentheses.
- Code with an array literal as a range endpoint (`([a, a]...a)`) is
  mutated. unparser writes such an endpoint as a `%w`/`%i` literal, so it
  raised KeyError unless every element was a plain string or symbol (and
  wrote `["a b"]` as `%w[a b]`, a different array). The method's mutants were
  reported unmutatable in warm runs, and with `--isolated` every mutant in
  the file was an error, which counts as killed. Kimera now writes the
  endpoint as an ordinary array literal, which reads back as the same tree,
  as unparser demands inside an interpolated string (`"#{([]...[a]).size}"`).
  A bake unparser still can't write is reported unmutatable with the reason,
  in `--isolated` and reload alike.
- A point keeps one mutant per program it can leave, whichever operators
  made them. Variants were told apart by directive only, so on redundant
  code two operators could emit the same program (`a.to_s.to_s` with
  `.to_s` unwrapped or its chain link dropped; `nil.respond_to?(:abs)`
  deleted or unguarded) and one test gap was reported twice. Each variant
  is now applied to the node as it stands in its file, and the first of
  equal programs is kept. The scan parses each file once more for that:
  over kimera's own `lib/` (280 KB), 1.2s becomes 1.9s.
- `kimera changed` and `--since` keep the lines after an added line that
  starts with `++ b/`. git prints that line as `+++ b/...`, the diff parser
  took it for a new file's header, and every later hunk of the file went to
  a file that does not exist, so the mutants on those lines were skipped.
  The parser now counts each hunk's added lines before it looks for a header.
- `argument_drop` and `element_drop` also count neighbors as equal when they
  differ only by parentheses or by minus on a numeric literal (`[-(1), -1]`,
  `f((a), a)`). Dropping either leaves the same program, but the two were
  compared node for node, so one test gap was still reported twice.
- The schemata grows with the number of mutants, not with their product
  along a nesting path. Each mutant of a node copied the node's guarded
  subtree, so every guard beneath it was copied once per mutant above it.
  With `--operators all`, `cli/mutant.rb` compiled to 1.7 MB from 2.8 KB
  (622x), and kimera's own sources to 18.2x their size; every warm worker
  paid that in compile time and memory. Only one mutant is active at a time,
  so a mutant's copy now leaves out the guards beneath it: `cli/mutant.rb` is
  28 KB (10x), and the sources are 5.5x.
- RSpec: a selected example's `before(:context)`/`after(:context)` hooks run
  whatever ran earlier on the worker. RSpec memoizes which groups have
  examples to run, and an earlier narrowed run left that memo stale: hooks
  were skipped (rubocop-ast's `before(:all) { alias_matcher }` turned the
  baseline red) or ran for a group with nothing selected.
- RSpec: running one example no longer walks its whole top-level group.
  Only the example's ancestor groups run; the others are hidden for the run.
  On rubocop-ast a single example cost 14.4 ms instead of 1.5 ms natively,
  and a full run took 617s; it now takes 98s.
- A source file the suite requires lazily (dry-validation's extensions) is
  registered as loaded once the overlay has evaluated it. The suite's own
  `require` used to load the original over the guarded methods, so their
  mutants read as `no_coverage`, or survived, and the gate could pass.
- `ruby2_keywords`, and a directive under a modifier `if`/`unless`
  (`ruby2_keywords :new if respond_to?(:ruby2_keywords, true)`), run again
  with the methods they flag. Blanked, `Sinatra::Base.new` and devise's
  `ControllerHelpers#process` stopped passing keywords and the baseline was
  red.
- `a || b || c` mutated to `&&` renders as `(a || b) && c`. unparser printed
  `a || b and c`, a syntax error inside an argument list, and the resulting
  `error` counted as detected.
- `--format json`, `sarif` and `github` keep stdout for the report. The suite
  loads in kimera's process, so its prints and `at_exit` hooks (SimpleCov,
  Coveralls) made the document unparseable.
- An in-memory SQLite database (`database: ":memory:"`) survives the fork
  into warm workers. ActiveRecord reconnected each worker to an empty one:
  devise read "no such table: users", and 735 of its 1,554 mutants went
  unjudged.
- A redeclared association keeps its place in `_reflections`. once-campfire's
  `has_many :memberships do ... end` carries mutants, so the overlay ran it
  again after `has_many :users, through: :memberships`, and every `Room`
  raised `HasManyThroughOrderError`.
- `--isolated` times each test, as the warm path does: a child beats a pulse
  file as each test starts. Bounding the whole child by `--hard-timeout`
  failed the isolated baseline of any suite longer than it (kimera's own
  self-gate), and could score a mutant with many covering tests `timeout`.
- The notice about failing tests excluded from the baseline names them, with
  their failure.
- `kimera init` leaves a Rails minitest app's `test/system` out, as
  `rails test` does, and finds minitest files named `test_*.rb` or
  `spec_*.rb`. `kimera doctor` honors `exclude_tests`, skips loading and the
  baseline when no test file matches, finds a coverage floor in any spec or
  test helper, names failing tests from Rails' minitest reporter, names the
  error behind "1 error occurred outside of examples", and explains a
  non-zero exit with no failing test.
- With `--operators all`, a `chain_link_deletion` mutant on a call whose
  receiver carried two or more mutants of its own ran a different program in
  warm workers. It sent the next call to the receiver's guard condition
  (`false.upcase`), not the receiver (`x.ord.upcase`), so its warm verdict
  could disagree with the mutant the report showed and with `--isolated`.
- `argument_drop` and `element_drop` no longer emit two mutants for equal
  neighbors (`f(nil, nil)`, `[7, 7]`): dropping either one leaves the same
  program, so one test gap was counted, and reported, twice.
- `conditional` no longer forces a literal condition to itself (`if true` to
  `condition => true`). That mutant is the original program, a survivor no
  test can kill.
- A mutation point the parser folds into its parent (the inner `-1` of `--1`)
  has no node to guard. It is now reported `unmutatable`. Before, it ran
  unmutated and read as `no_coverage`.
- `default_argument` (`default => required`) no longer runs a mutant warm
  when the warm guard can't match the real signature, which gave wrong
  verdicts. A removal that doesn't parse (a middle optional, or one before a
  splat, as in `def m(a = 1, b = 2, c = 3)`) is no longer emitted. Three kinds
  are now judged by reload instead of warm:
  - one that rebinds positional arguments (in `def m(a = 1, b = 2)`, making `b`
    required turns `m(9)` into `[1, 9]`, while the guard raised);
  - one in a block, where an omitted argument is `nil`;
  - a keyword that follows a default with effects (the guard ran that default
    first, so `m(0)` raised `ZeroDivisionError` instead of "missing keyword").
- A warm worker that wrote part of a message line and then stopped, with its
  pipe still open, hung the whole run: the parent blocked reading the rest of
  the line and never reached its watchdog. The parent now reads what's
  available and buffers partial lines, so the hard timeout kills that worker.
- Property-based specs (`spec/property/`) check the schemata, registry, diff,
  gate and worker-pool invariants on generated programs. A TLA+ model of the
  worker pool (`formal/`) is checked by TLC in CI for three small
  configurations. The fixes above came out of them, and of fault injection
  against the real pool.

- A warm worker re-evaluates only the code of an already-loaded file that
  carries mutants. To install its guards, the overlay evaluated the whole file
  again, so every class-body statement ran twice. Non-idempotent DSL broke the
  baseline or made files `unmutatable`: a `class_attribute` in a concern's
  `included do` reset to its default (a class's `track :name` was lost, or
  doubled), ActionPolicy raised `Pre-check already defined`, a class-level
  registry was reset, and a constant such as `Error = Class.new(StandardError)`
  was replaced, so `rescue Error` stopped catching its existing subclasses.
  Statements with no mutant are now blanked in place (lines don't move).
  Methods and lambdas with mutants still run, with the class, module or
  declaration block (`included`, `class_methods`, `class_eval`, ...) around
  them, and so do visibility calls, `require`s, local variables and an
  `alias` of a mutated method. A file nothing required yet is still evaluated
  whole. Tests that failed only under kimera were often dropped silently as
  "cover no in-scope mutant", which hid their mutants as `no_coverage`.
- A concern's `included`/`prepended` block that the overlay re-runs is chained
  after the original instead of replacing it, so a class that includes the
  concern later (one defined in a test, say) still gets the whole block.
- Re-evaluating a class keeps the superclass it already has. A nested class
  whose superclass constant had been rebound (`Row = Data.define(:cells)` then
  `class PersonRow < Row`) failed with `superclass mismatch`, and the pin only
  covered superclass expressions that weren't constants. It now covers every
  superclass, `class A::B < C` included, and looks the class up in its
  lexical scope.
- `Class.new` and `Module.new` constants with a block are reopened on
  re-evaluation, as `Struct.new` and `Data.define` ones already were, so the
  constant keeps its identity.
- The soft timeout applies to each covering test a mutant runs, not to all of
  them together. A surviving mutant runs every covering test, so one covered
  by, say, 20 tests of 0.3s each always hit the 5s budget and was reported as
  a `timeout`, which counts as detected. The hard watchdog times each test the
  same way: a worker reports each test it starts, and the watchdog renews its
  deadline.
- A warm worker that dies says how. The `detail` of its `harness_error` (and
  of a red baseline) names the signal or exit status and, when Ruby raised
  something (an untrapped `SIGTERM`, `NoMemoryError`), the exception and its
  first frames. It used to read only "worker crashed before result".
- A test that sends its own process a signal nothing traps is explained: the
  detail says to trap the signal in the test or leave the test out with
  `--exclude-test`. In a serial baseline (`--jobs 1`) such a signal ended
  kimera with no output; now that test fails, with the detail, and the
  baseline is red. Interrupts still stop the run.

## 0.1.6 (2026-09-29)

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
- Every report result carries a `key`, such as
  `app/models/discount.rb:44:8557dadd`, that names the mutant in any run. A
  mutant ID numbers every mutant the run scanned, so `--focus 3740` from a
  full report meant nothing, or a different mutant, in a one-file run. The
  key's digest covers the mutant's own code (file, method, operator,
  whitespace-squeezed source, label, and which repeat it is), not its line or
  ID, so it is the same whether the run scanned one file or five hundred.
  `kimera report` and `kimera mutant` show it next to the ID.
- `--focus` (on `run`, `changed`, and `ci`) and `kimera mutant` accept a key
  as well as an ID. A key whose line moved still resolves when its path and
  digest match exactly one mutant; an unknown key is "not in scope".
- `kimera mutant ID --report R --rerun` re-evaluates the right mutant. It
  scanned only the mutant's file, where IDs restart at 1, then focused the
  report's ID, so a mutant outside the report's first file was "not in scope"
  or silently swapped for another. It now focuses the key. A report written
  before keys existed can't be rerun; regenerate it.
- A test that makes code call `exit` or `abort` now fails like any other
  test. RSpec and Minitest let the `SystemExit` through, so it ended the warm
  worker and the mutant was `harness_error` ("worker crashed before result");
  a serial baseline exited kimera silently, and an isolated child died before
  reporting. The test now fails after its teardown, with the exit status,
  where it was called and `abort`'s message in the failure. A mutant that
  makes a test abort is `killed`, and a baseline test that aborts turns the
  baseline red with that message. `exit!` and interrupts are not caught.
- A run whose `--tests` leaves out test files the configured `tests:` glob
  (or the default) would run now says so above the summary: `narrowed run:
  --tests matched 3 of 1,120 test files from the configured tests: glob;
  survivors may be killed by tests outside it`. The JSON report's `run`
  section records `"narrowed": true` and the configured globs. Narrowed runs
  are faster, but their survivors (and kills that hold only within the narrow
  set) used to read like a full run's. Verdicts are unchanged.
- `kimera run --pidfile FILE` writes the run's process id to FILE and removes
  it when the run ends, including on errors. Scripts waiting with `pgrep -f
  "kimera run ..."` matched their own shell and waited forever; they can wait
  on that pid instead.
- `kimera run --evaluate-ignored` (also `changed` and `ci`) runs ignored
  mutants, from `ignore:` and from the baseline, like any other. They keep
  status `ignored`, so they never gate as survivors and still count toward
  `max_ignored`, but each report row gains a `verdict` (`killed`,
  `survived`, ...) and a `detail` such as `ignored (killed): ...`. The text
  report sums them up: how many are now killed (their entries can be
  pruned) and how many still survive. Until now a baselined mutant was never
  evaluated, so finding out which entries were still alive meant copying
  `.kimera.yml` without its `baseline:` line. A `--session` file keeps these
  verdicts across resumes.
- `kimera run --no-baseline` leaves out the `baseline:` file's entries, so
  those mutants are judged and gated like any other; `.kimera.yml`'s own
  `ignore:` entries still apply.
- `kimera baseline review BASELINE.yml --report REPORT.json` judges every
  entry against a report (best one from `--evaluate-ignored` or
  `--no-baseline`): killed and safe to prune, still surviving, unjudged,
  stale (the report covers the file but no mutant matches), or out of the
  report's scope. Without `--report` it still just lists the entries.
- `kimera baseline prune BASELINE.yml --report REPORT.json [--dry-run]`
  rewrites the baseline without the killed and stale entries, keeping the
  order of the rest, prints what it removed, and says by how much
  `max_ignored` can drop. An incremental (`--since`) report holds only the
  mutants on changed lines, so prune never treats an entry missing from it
  as stale. Reports now record `since` in their `run` provenance for this.
- A line-anchored ignore entry that no longer matches at its line (a line
  was added above it) still applies when its other anchors (label, plus
  `original` and `method` when given) single out exactly one mutant in the
  file. Kimera warns `ignore entry re-anchored: path:12 → 13 [label]` so the
  entry can be updated, instead of reporting it stale and bringing the same
  mutant back as a new survivor. `baseline review` and `prune` follow the
  same rule, and `prune` moves such entries to their current line.
- `kimera baseline create` records each survivor's `original` snippet next
  to its file, line, and label, so a re-anchored entry matches only the
  mutant it was written for. Baselines without it keep working.

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
