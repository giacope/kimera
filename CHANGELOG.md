# Changelog

## Unreleased

Self-host gate: what kept the `selfhost` job red on main.

- **A `def` inside a block calls refined methods as the plain suite does.**
  Kimera defines the woven copy of a def in a block a DSL runs on each module
  the block ran on. It did so on every such module, compiling the def on its
  own, which dropped the `using` the file or a class around it had called and
  the file's `# frozen_string_literal: true`, and, on a refinement, the
  refinement its `refine` block activates. A def calling a refined method
  raised NoMethodError or NameError under Kimera only, and the run stopped at
  "harness error: N test(s) fail under kimera but pass in a plain run":
  Kimera's own `Pool::Duty#words` (`Struct.new do`, `error.last_words`) and
  `Shift::Subject#crashed` (`Data.define do`, `error.headline`) kept the
  self-host job red, and holdout q03 (`refine String do`, `truncate_words`
  calling `squish`) never got past its baseline. A module the overlay's own
  run of the file reached (the class of a `Struct.new` block, which the
  overlay reopens, or the refinement `refine` hands back) now keeps the
  overlay's def. On the others (shared example groups, `Module.new`) the def
  is compiled after the comments above the file's first line of code and the
  `using` calls made before it in each scope around it, on its own lines.

Field test round 5, harness: what kimera loads, runs and says.

- **A test that fails only under kimera is a harness error, whatever it
  reached.** A red baseline test that touched an in-scope mutant is rerun
  plainly too before kimera calls the suite "not green": one that passes
  there stops the run with "harness error: N test(s) fail under kimera but
  pass in a plain run", the tests (with what a lost test's worker left, such
  as its after-fork hook's error and frame) and the likely cause, as round 3
  promised.
  Seven of ten libraries in round 5 met "baseline suite is not green" with a
  reproduce command that passed.
- **Kimera loads only what the suite loads.** A file the suite never
  requires is evaluated early only when it defines and nothing else: every
  class and module body in it holds methods, constants and `require`s alone.
  slim's `include.rb` (`after Parser, Include` in a class body) and a module
  body that sets `@limit = 100` ran inside the suite and turned it red. A
  never-loaded file Kimera could not load either (i18n's `key_value.rb` needs
  `active_support/json`, action_policy's ruby-lsp addon) reports its mutants
  `no_coverage`, with the error, never `unmutatable`: 45 and 50 mutants had
  gone unscored.
- **An autoloaded file's class body runs once.** Every pending autoload
  along the constants an unloaded file opens is resolved before the overlay,
  as the suite would resolve it, and a file that is then loaded (the one the
  autoload names, or one it requires) is trimmed to its methods. Evaluated
  whole, the overlay fired the autoload and then ran the class body again:
  kramdown's `@@parsers = {}` emptied the parser registry and 1753 tests
  went red, and `parser/kramdown/list.rb`'s `define_parser(:list, ...)`, run
  twice, would raise; left out, its 173 mutants read "never loads this
  file", alone or beside its parser.
- **A lambda a constant holds stays bound.** `BY_SYMBOL = ->(record) { ... }`
  collected into `self.chain = [BY_SYMBOL]` at load kept the original; the
  overlay bound a guarded copy nothing called, so its mutants read
  `no_coverage` or survived (action_policy's LookupChain). Its body and its
  parameters' defaults are now `isolated_only`, judged in the isolated tier,
  like other load-time code: a default such as `strict_namespace: false`
  went to the reload tier, whose fresh lambda the chain never called either,
  so `false => true` survived though the plain suite fails with it.
- **A library suite with no database configuration runs on several
  workers.** Active Record loaded without a test database configured (a
  suite that connects to `:memory:` in a `before`, cancancan) has no schema
  to load, so the workers no longer fire Rails' per-worker schema hook, which
  raised `AdapterNotSpecified` in each of them.
- **`Minitest.after_run` hooks run.** Once, in the process that loaded the
  suite, when the run ends; workers do not run them. resque's helper stops
  the Redis it started there, which outlived every run. A hook that raises
  or exits is reported and cannot end the run, and SimpleCov's own hook is
  left out: it would write the coverage of kimera's process over the
  project's report, and it exits 1 when it sees an error in flight, so on
  CodeTriage a red baseline ended the run with no message at all.
- **Messages.** A mirror whose `spec_helper` raises while `.rspec` loads it
  reports the error, class and message, not "a coverage floor or exit
  hook?". `kimera doctor --check-baseline` says first when the suite was
  killed by a signal ("killed by SIGKILL before it printed a summary — out
  of memory?") instead of naming a passing example whose title held "error".
- **Validations are judged option by option.** `rails_validation` also drops
  each option of a `validates` call that keeps a validator without it
  (`length:` beside `presence:`, `if:`), so a pull request that adds a
  constraint gets a mutant for it; deleting the whole call was killed by an
  old presence test (CodeTriage).
- **Two new operators, and `kimera init` writes them.** `when_clause` drops
  one `when` of a `case` that has another, and `append_deletion` deletes a
  `<<` statement (`@log << name`), which `statement_deletion` leaves alone.
  `kimera init` now writes `operators:` for every new project: the core, these
  two, and `rails` on a Rails app. Existing configurations are unchanged: one
  without `operators:` keeps the core alone.

- **A `def` inside a block a DSL runs is covered by the tests that run it.**
  `RSpec.shared_examples_for "x" do def be_boolean ... end end` (dry-types'
  `lib/dry/types/spec/types.rb`), `shared_context` and `Module.new` blocks
  define their methods on modules the source cannot name, so the overlay's
  copy reached none of them and every mutant there read "no test executed this
  line". `Kimera::Execution::BlockMethods` notes, before the overlay, each
  module whose method was loaded from such a def, and defines the woven def on
  it afterwards, in the def's lexical scope and with its visibility. On the
  round-4 repro the three `no_coverage` rows are now two kills and the
  `>= => >` survivor the plain suite also lets through.
- **Putting a method back says nothing.** Restoring a method another file had
  wrapped (dry-core's `deprecate_class_method`), or repointing an alias, ran
  `define_method` under the suite's `$VERBOSE`, so a suite that raises on
  warnings (dry-types) lost the file and went red. `Redefinition#redefine`
  now runs silenced.
- **A Method taken at load is named when it turns the baseline red.** Ruby
  cannot keep `method(:to_int)` taken at load `==` to the method once the
  overlay redefines it. When tests fail under Kimera only, the harness error's
  "likely cause" now names each such method (`Coerce.to_int at
  lib/coerce.rb:4`) and the `--exclude` that leaves its file out.
- **`kimera init` picks the test glob whose files define the most tests**, not
  the first with any match: zeitwerk's `test/**/*_test.rb` matched one support
  class and none of its 50 `test/**/test_*.rb` tests. `kimera doctor` fails
  "Test discovery" when the matched files define no test (`def test_…`,
  `test "…"`, `it`, `specify`, `it_behaves_like`).
- **A worker's after-fork setup error is confessed.** An exception in Rails'
  `parallelize_setup` hooks or a worker's schema load left the worker dead with
  stderr discarded, and the advice blamed shared state. The baseline failure
  now reads "worker 1's after-fork setup raised RuntimeError: …" with its first
  frames. A schema path Active Record cannot work out (a suite without Rails
  has no `db_dir`) is no longer "loadable": the worker copies the database.
- **Ctrl-C or SIGTERM stops the suite's process group.** `kimera doctor
  --check-baseline` left its suite running, orphaned and holding every
  inherited descriptor (a shared `flock`). The suite's group is now stopped,
  and the command prints `kimera: interrupted (SIGINT); …` and exits 128 + N
  instead of a backtrace.
- **`next if`, `break if` and `redo if` mutants show their code again.** The
  report, `kimera mutant` and annotations parsed a point's source alone, where
  Prism rejects `next`/`break`/`redo`, and showed no `+` line. They are parsed
  as a fragment of a method now (`next if x.nil?` → `next if false`).
- **doctor tells a coverage floor from shared state.** A split run whose parts
  each exit non-zero with no failing test (SimpleCov's `minimum_coverage` on
  half the suite) was called "shared state between workers"; it is called a
  coverage floor now.
- **The isolated RSpec child sets its streams before the suite's setup runs.**
  Under `$VERBOSE`, `.rspec`'s `--require spec_helper` builds RSpec's reporter,
  and the child's later `output_stream=` warned, so a suite that raises on
  warnings (maintenance_tasks) lost every isolated and mirror verdict.
- **doctor quotes why a suite aborted.** "test command failed" alone now
  carries the output's first lines when no failure or error line explains it
  (Rails' "Migrations are pending … You have 9 pending migrations").

- **Kimera mutates Prism's own tree; the parser gem is gone.** Every rewrite,
  guard and bake is now made on the Prism tree the registry scanned, found by
  the span and node type each point records, so `prism` is Kimera's one
  runtime dependency: parser, ast and racc are no longer pulled in. A point
  the parser gem folded into its parent (the literal in `--1`) is guarded
  like any other instead of reported unmutatable, and a file holding
  `/\xff/`, which the parser gem rejected, renders its variants and compares
  them. A def at the tail of a method is guarded where it stands, so its
  `tail => nil` mutant makes the method return nil instead of emptying the
  def, and a range or regexp a mutation leaves as the body of a tested
  `begin ... rescue` is caught as the flip-flop or `$_` match Ruby reads it
  as. `Kimera::GuardrailInterpolation` is gone: a guard on a string part is
  written as an interpolation (`"a#{if ... end}"`), so string parts are no
  longer spliced or coalesced around it. Custom operators need no change:
  directives are the same data. `kimera doctor` no longer checks the prism
  version, which only the parser-gem translation needed.
- **Kimera writes Ruby itself; the unparser gem is gone.** `Kimera::Scribe`
  writes a Prism tree back as source that reads as the very same tree: across
  Kimera's own sources, Ruby's standard library and every gem a Rails 8.1 app
  installs (7,136 files), 7,132 come back identical, and the other four differ
  only by parentheses. unparser and diff-lcs are no longer pulled in, and the
  four patches on unparser's internals, the spec that guarded them and CI's
  per-release unparser job are gone. What unparser got wrong, and Kimera worked around, Scribe does not:
  - Grouping comes from precedence, not from the parentheses a mutated tree
    lacks: `x = a && b && c` with the inner `&&` swapped reads
    `x = (a || b) && c`, a sign stays outside a call on a numeric literal
    (`-(1.abs)`), a negative literal raised to a power keeps its parentheses
    (`(-1) ** 2`), and `a ** b ** c`, `a + -b` and `!-a` are written plainly.
  - Any string writes, of any shape: statements in one interpolation
    (`"#{a; b}"`, which unparser refused), an `if` straight in a string,
    nested and adjacent parts, empty parts. Heredocs come back as quoted
    strings that read as the same parts, bytes that are not UTF-8 as `\x`
    escapes in every literal (a backtick command came back with the raw byte),
    and non-ASCII characters as `\u` escapes, so a file with a non-UTF-8
    magic comment stays loadable. A regexp keeps the delimiters it was written
    with, and one a mutation rewrites takes the first its pattern does not use.
  - An array range endpoint is an array literal, not `%w`/`%i`, and
    `|(name)|` keeps its parentheses.
  - Locals are bound as Ruby binds them: patterns, named captures, rescue,
    `for`, block and method parameters (a default sees its own parameter). A
    method a local shadows is written `name()`, a modifier is kept where the
    body binds what its condition reads (`a = 1 if a.nil?`), and a read of a
    local nothing binds where it sits is refused rather than written as a
    method call, so the guard that caused it is dropped as before.
  - `and`, `or` and `not` keep their spelling, and `return a ? b : c` stays a
    ternary. A `rescue` list holding a ternary writes too, and `{ frozen?: }`
    is never written as a shorthand Ruby rejects.
  - Nothing is written through a round-trip check, so there is no warning
    noise and no "could not find a round tripping solution". Messages that
    named unparser now name Kimera (`kimera could not write its guard`).
  `prism` is now required at 1.5.1 or later (unparser 0.9 already did).

Follow-ups to field test round 5, how Kimera writes mutants:

- **Every bake, and the overlay with every mutant off, keeps your file's
  lines.** As many lines, and every line outside a rewritten span at its
  number, so `__LINE__`, backtraces and `source_location` in the rest of the
  file read as without Kimera in both tiers. A bake shorter than its span is
  padded with the line breaks it lacks, after it or before its closing `)`,
  `]`, `}` or `end`: a dropped keyword of a multi-line call, a `permit(` list
  one key per line, a deleted heredoc statement or a dropped `rescue` no
  longer move the code below them (the isolated tier scored such moves as
  kills). A guard's alternative is written on its line, an untouched part
  that spans lines written afresh there, so `a &&\n  b && c` no longer adds
  a line to the baseline ("not green" for a green suite that checks a line).
  A method written whole (a dropped `rescue` clause) is laid out to its own
  lines, on one line when written out it would take more, and a point
  outside every method has the file's statement that holds it written so,
  not the whole file; lines inside such a rewrite may read as its first.
  Kimera checks the layout after weaving each file and writing each bake: a
  guard that would move a line is unguardable, a bake that would is
  `unmutatable: kimera could not write it (what it wrote moves the lines
  after it)`, and no file is written whole any more. On the round-5 corpus,
  bakes that change the line count went from 3,848 of 179,695 to 0 of
  185,600 (every operator, source directories) and from 286 to 0 elsewhere;
  4 bakes in one file are now unmutatable instead; overlays that keep every
  line went from 95.1% to 100% with the default operators and from 60.0% to
  100% with every operator (73 written whole before, none now).
- **A deleted statement is `()`, not `nil`.** Same value, same line, but
  `ruby -w` stays silent: a suite that raises on its own files' warnings
  (view_component's and maintenance_tasks' helpers) scored every isolated
  deletion killed by "possibly useless use of nil in void context" (1,863
  of 36,750 Rails bakes; 0 now). `()` and `nil` count as one value when
  Kimera drops duplicate mutants.
- **A bare list or a quoted label no longer costs the file its overlay.**
  `@a, @b = left, right`, `x = *list, 1` and `{ "#{name}_attributes": 1 }`
  were guarded where they stand, which does not parse, so the whole file was
  written again (comments dropped, every line moved). They are guarded with
  the assignment or the hash that holds them.
- **`it` blocks are guarded in place and shown as written.** A mutant inside
  `list.select { it > 10 }` was written `__kimera_it >= 10`, refused, and
  its method written whole; the report and `kimera mutant` showed
  `list.first { |__kimera_it| … }` over three lines. Both now read
  `list.first { it > 10 }`: a mutant is shown with the point's untouched
  text as you wrote it.

Follow-ups to field test round 4, how Kimera writes mutants:

- **Overlays and bakes are spliced into your source, not rewritten whole.**
  Everything outside a rewritten span is the file as written: comments,
  every magic comment, `__END__` and its data, and every line's number. A
  warm overlay guards each mutant at the smallest expression its rewrite
  changes, `(!(::Kimera::RUNTIME.active?(7)) ? (a > b) : (a >= b))`, the
  original slice first and untouched; a bake writes the rewritten node alone,
  padded to the span's lines, and must read back as the mutated tree, or the
  next node out is tried. Before, both rendered the whole file, so a file whose
  `# frozen-string-literal: true` (hyphenated, or after a header or another
  magic comment) Kimera dropped ran with mutable literals, and its baseline
  could go red ("not green" for a green suite); a Sinatra app lost its
  `__END__` templates in every isolated mutant; and `__LINE__`, backtraces and
  `source_location` changed in every mutated file (roda's exception_page specs
  went red). On 147 corpus files (12,220 mutants, every operator) no bake
  fails to parse (was 6) or reads as the original (was 4), every bake keeps the
  leading comment block and `__END__` (was 51%), the lines after its span keep
  their numbers in 99.9% (was 0.6%), and 57% of overlays keep every line
  number (was 3%): an alternative longer than a line, or a dropped `rescue`
  clause, which writes its method whole, moves the lines after it. With the
  default operators, 92% of overlays keep every line number (was 0%).
- **No mutant Kimera could not write is judged.** Every bake and woven file is
  parse-checked; a bake that does not parse or reads as the original is
  `unmutatable: kimera could not write it`. Dropping the last argument before
  a block argument wrote `f(, &blk)`: the warm tier lost the mutant
  ("unguardable") and the isolated tier scored the SyntaxError as a kill
  (dry-types' `try(input, &)`, pundit's `cached_find(record, &:policy)`). It
  now writes `f(&blk)`. A `string_literal` mutant of a part of an interpolated
  regexp (`/\A#{prefix}_id\z/`) baked to the unchanged regexp, a certain
  survivor in every isolated run; the part is now written from its value.
- **A named-capture match is never broken by a guard.** A regexp mutant of
  `/(?<num>\d+)/ =~ s` is guarded with the whole match, so `num` still binds
  with no mutant on (it read `nil`, and the baseline went red under
  `--operators all`).
- **What loading already did is not run again.** A top-level `require` under
  a modifier condition is not replayed by the overlay (pundit's
  `require "pundit/railtie" if defined?(Rails)` failed once a spec had
  defined `Rails`, and every mutant of `lib/pundit.rb` was lost). A constant
  built by a factory Kimera does not know, from a block that defines methods
  (faraday's `RequestOptions = Options.new(...) do ... end`), is reopened like
  a `Struct.new`, not re-bound, so objects made at load are of the
  instrumented class: faraday's baseline is green and its options' methods are
  no longer falsely `no_coverage`.
- A property spec writes every mutant of a seeded sample of Kimera's own
  sources and example apps (every operator) and checks that each parses,
  differs from the original and reads back as the mutated tree.

Follow-ups to field test round 3:

- **`--reuse-coverage` (`reuse_coverage`).** A full run keeps its baseline's
  coverage map in `tmp/kimera/coverage.json`, with the commit, Ruby, the
  settings and a digest of every source, test, support and config file it was
  measured against. An incremental run (`--since`, `ci`, `changed`) with the
  flag reruns only the tests that reached a source file changed since, or one
  in scope, and tests the map does not know; when Ruby, the settings or a
  test, support or config file changed, it measures every test and says why
  in one line. Every test that can cover a changed line gets a fresh
  baseline.
- **A database per worker and mirror without a schema file.** A suite that
  builds its database as it loads (thredded migrates it) gave Rails' hook no
  schema to load, so workers shared one database and its baseline went red
  under `--jobs 2`. Each worker and mirror past the first now gets a copy of
  the database the parent prepared, made after the parent disconnects:
  `CREATE DATABASE <name>_<n> TEMPLATE <name>` on PostgreSQL, a copy of the
  file (and its write-ahead log) on SQLite, never an in-memory database. The
  copies are dropped when the run ends; other adapters still say the workers
  share one database.
- **A run on kimera itself sees every mutant its specs reach.** Kimera's specs
  switch fixture mutants on through `Kimera::RUNTIME`, and they switched it
  off afterwards, which also turned off the run's own mutant: for the rest of
  that example, and through `after` hooks for the examples after it. The specs
  now hand the switch back with `Kimera::Runtime#during`. Of the 9 survivors
  the first full self-run on main reported, 7 were hidden that way; the other
  2, in `WorkerDatabases#separate?`, are killed by a spec that keeps a lone
  worker on the parent's database.

Field test round 3, on MIT libraries and Rails apps (casa, thredded, devise,
rack, grape, jekyll among them): the verdicts that disagreed with the plain
test command, and the setups that kept kimera from running, are fixed here.

- **A test that fails only under kimera stops the run.** A baseline failure
  is rerun plainly; one that passes there is a harness error naming the
  tests and the likely cause (exit 1), and only tests red plainly too are
  excluded, "coverage unknown" (casa's 939 dropped tests became false
  survivors).
- **Suite hooks run once.** Warm workers no longer re-run the `before(:suite)`
  hooks the parent ran; they run Rails' parallel after-fork hooks only.
- **A database per worker on every Rails.** Rails before 8.1 counts as
  parallelized; workers and mirrors get `TEST_ENV_NUMBER`, and numbered
  databases are created and loaded; the parent disconnects before forking
  and before spawning mirrors (`PG::ObjectInUse` is named when it still
  happens); in-memory SQLite is never renamed and survives the fork (devise).
- **Load-time code is judged, not called uncovered.** `.rspec`'s requires load
  inside the load trace, which now follows blocks and lambdas too; every
  `no_coverage` row says why. A file the suite never loads is never
  evaluated; generator templates, vendored and generated files are out of a
  glob's default scope.
- **The work tree is guarded.** A run that changed tracked files fails, naming
  them (a jekyll mutant made its cleaner delete the project's files).
- **Mutated code runs inside Ractors**, and records its coverage there.
- **`kimera ci` finds the base on GitLab, Buildkite or `KIMERA_BASE`**, says when
  it found none and what a full run leaves ungated, and has its own `--help`.
  The report's run section records the effective `judge_isolated_only` and
  `confirm_survivors`.
- Setup: `init` prefers Minitest when the helper runs it, leaves RSpec Rails
  apps' `spec/system` and `spec/features` out, writes `jobs: min(4, cores)`,
  and knows an engine declared in any lib file; `doctor` treats engines as
  Rails, has a watchdog, and checks prism; an old prism on Ruby 4.0 is a
  one-line error.

Round 2:

Field test round 2, on twenty more MIT codebases (Rails apps and engines,
rouge, steep, solargraph, asciidoctor among them): 141 of 143 sampled
verdicts matched the plain test command. The two that did not, and the
seams around them, are fixed here.

- **No kill from an error outside every test.** An isolated child that fails
  with no test named (a load error, a `before(:suite)` hook) is not a kill on
  sight: the mutant runs again, and a recurring error kills only when a fresh
  mirror without the mutant runs clean; otherwise the mutant stays unjudged.
  A Claim-for-Crown-Court-Defence mutant was killed by a deadlock in a
  `DatabaseCleaner` hook.
- **Mirrors are as safe as warm workers.** Each concurrent isolated mirror
  takes its own test database through Rails' parallel-testing hooks, and gets
  a private `.git` snapshot that reads the project's objects, so a gemspec's
  `git ls-files` works in a mirror (asciidoctor's isolated baseline was red)
  and nothing writes the project's `.git`.
- **Survivor confirmation.** `--[no-]confirm-survivors` (`confirm_survivors`)
  runs each warm survivor's covering tests alone in a fresh process with the
  mutant on, fastest first and at most 50; a failure there kills only if the
  test passes alone without the mutant. On by default for incremental runs.
  A rouge lexer survivor was masked by an earlier test's eager load.
- **Per-test soft limit.** A covering test may run for `--soft-timeout` or
  its baseline × 3 + 1s, whichever is longer, capped under the hard watchdog;
  the isolated watchdog takes the same raise. Mirror timeouts say "timed out
  after Ns" instead of "its tests fail".
- RSpec suites with `filter_run_including focus: true` and
  `run_all_when_everything_filtered` run every example, as `rspec` does; a
  baseline whose test files select no test fails loudly instead of scoring
  every mutant uncovered.
- `tests:` keeps the configured order, so a helper listed first loads first.
- On a run narrowed with `--tests`, uncovered mutants read "not covered by the
  narrowed tests" and are neither scored nor gated on under
  `count_no_coverage`.
- Keyed caches are memoization: `@cache[key] ||= …` values are computed once,
  and a lookup's early return plus its store into the same cache carry no
  mutants (solargraph's equivalent survivors).
- Isolated mutants with no coverage of their own (class-body DSL, memoized
  values, load-time code) run the tests in the files that cover their source
  file, plus its conventional spec/test file, instead of the whole suite.
- Reload-tier rows record the tests they ran and their time; a mutated source
  that fails to load says so in the detail.
- `kimera init` writes `count_no_coverage: true` (not the redundant
  `fail_on_no_coverage: false`), and treats an engine with a dummy app as
  Rails.
- The gate's `unjudged` line names its JSON status (`harness_error`), and
  `kimera report --status unjudged` lists those rows; doctor's parallel
  check says it is a sample.
- Isolated child ledgers record the first failure's message.
- Code that relies on a refinement runs warm: the trimmed overlay keeps its
  `using` lines, so a refined call no longer raises NoMethodError in the
  baseline.
- A run on kimera itself numbers its mutants from 1,000,001. Kimera's own
  specs drive the runtime with mutant ids from 1 (a nested harness forks a
  real worker that switches on mutant 1), and in a self-run those specs ran
  under the run's switches: whichever of the run's mutants shared the id
  flipped in the spec's worker. A project's mutants still count from 1.

Field test on ten MIT Ruby and Rails codebases (Sequel, YARD, graphql-ruby,
ruby-lsp, Feedbin, Human Essentials, Chatwoot among them): 217 of 217 sampled
survived and killed verdicts matched the plain test command; these are the
defects it found at the seams, and the defaults it moved toward the
"untested is not passing" stance.

- **Breaking: uncovered mutants count by default.** `count_no_coverage`
  defaults to true: a mutant no test reaches scores as not killed and fails
  the gate in every command. `count_no_coverage: false`
  (`--no-count-no-coverage`) restores reporting without scoring.
- **Rails DSL is judged on incremental runs.** A new `judge_isolated_only`
  setting (`--[no-]judge-isolated-only`) judges the mutants the warm run
  leaves `isolated_only` (validations, callbacks, `dependent:`, lambdas a
  macro registers) in fresh isolated mirrors. Unset, it is on for `--since`,
  `kimera ci` and `kimera changed`, off for full runs. On Feedbin the
  isolated tier judged 15 such mutants in 68s and found 8 holes. `kimera init`
  on a Rails app writes the `rails` operators into `.kimera.yml`.
- A gate that killed nothing while `isolated_only` or `unmutatable` mutants
  were in scope fails ("0 of N mutants killed"), naming `--isolated`, instead
  of passing on "0 of N mutants evaluated" or on a tolerated survivor; next
  actions point at `--isolated` for them.
- Minitest suites that use minitest-hooks (Sequel's) run: each test runs
  inside its class's `with_info_handler`, as a plain run does, so
  `before(:all)`/`around(:all)` work and a failing class hook fails the test.
  Every warm worker used to die with FrozenError.
- A stillborn worker pool prints what the last worker died of (the error's
  real class and its frames); the old hint to re-run with `--jobs 1` showed
  nothing there either.
- A block parameter that destructures one name (`{ |(name)| ... }`) keeps
  its parentheses when kimera re-emits the method. The parser reads it as the
  same node as `{ |name| ... }`, so the instrumented method handed the whole
  array to the block and an unmutated suite went red (found gating hashira).
- A class-body `if`/`unless` holding a mutated method is trimmed like a class
  body on the warm re-evaluation, so an `alias` inside it is not re-bound to
  the redefined method. Sequel's `dataset/query.rb` (`if TRUE_FREEZE; alias
  _clone clone; def clone ...`) read as a red baseline and could not be
  mutated.
- A soft-timeout expiry is a `timeout` only when the test, run alone with the
  mutant off, passes in under half the soft timeout. A test slow (or red) on
  its own kills nothing, and if no other test kills the mutant it is
  unjudged with a hint to raise `--soft-timeout`. On ruby-lsp 3 of 6 timeout
  "kills" passed plainly, and the count moved with machine load.
- `kimera doctor` runs the suite into a file in its own process group, so a
  process the suite leaves running (Feedbin's test helper leaks a
  `redis-server`) no longer keeps it waiting forever; it also prints each
  check as it finishes.
- One load path everywhere: each test file's nearest `test/` and `spec/`, the
  project's own `test/` and `spec/`, and a new `load_path:` setting, used by
  the warm run, `kimera doctor`, the isolated children and every printed
  "reproduce without kimera" command (which hard-coded `-Itest`). `doctor`
  called a Minitest suite under `spec/` broken, and narrowing `--tests` to a
  nested test folder lost the root `test/`.
- `kimera init` reads `Gemfile.lock` (or `gems.locked`) when no `.rspec` or
  helper names the framework, so a Minitest suite under `spec/` is no longer
  set up as RSpec.
- Memoization written as a guarded fill that ends on the ivar (`unless @x;
  ...; @x = value; end; @x`, `@x = value unless @x`, `if @x.nil?`, `if !@x`)
  gets no guard mutant, like `@x ||=`; its `unless false` mutant could never
  be killed.
- `return_value` leaves a `false` tail and `return false` alone, as it already
  did `nil`: no truthiness caller can tell them apart.
- **Breaking: an ignore entry's `column:` is 1-based**, as report.json and the
  text report print it. Copying the column from the report used to un-ignore
  the mutant.
- A test file that defines a top-level constant one of kimera's dependencies
  defines (`class Parser`) fails to load with a message naming the constant
  and the gem.
- `kimera report --report FILE` works like `kimera mutant ID --report FILE`.
- The red-baseline hint for a multi-worker run starts from the printed
  reproduce command: red there means the tests are red on their own.

- An ignore entry whose file no longer exists is reported as stale. An entry
  that matched no mutant counted as stale only while its file still had
  mutants in the run; a deleted file has none, so the entry read as "outside
  this run's scope" and stayed silent. Globs and files that are only out of
  scope still say nothing. On once-campfire, 13 entries for files a refactor
  had removed sat unnoticed.
- A drifted ignore entry no longer re-anchors onto a mutant another entry
  also claims; both stay stale until someone looks. Re-anchoring matches by
  label anywhere in the file, so on once-campfire two entries written for
  different lines claimed one mutant, and a third landed 21 lines away on an
  unrelated guard, which could hide a real survivor there.
- A lambda handed to a class-body macro that no test reached warm reports
  `isolated_only`, not `no_coverage`, and `--isolated` judges it against the
  whole suite. The warm overlay re-declares the class body, and a macro that
  registers its lambda instead of redefining a method (`belongs_to :creator,
  default: -> { Current.user }`, `after_create_commit -> { ... }`) keeps the
  original in front, so the mutated lambda never ran and read as untested,
  even under `--isolated`, which picked its tests from that coverage. On
  once-campfire 8 such mutants (models, controllers' `rate_limit` and
  `allow_browser` lambdas) were `no_coverage` though tests kill each one, and
  `kimera ci` would have failed a pull request on them that no test could fix.
  `scope` lambdas, which redefine a method, stay judged warm.
- A forced condition whose predicate assigns renders as the mutant that runs:
  `if (room = find(id); true)`, not `if true`. The mutant has kept the
  assignment since the predicate pin learned to, but the report still showed
  the bare literal, which reads as a NameError in the body; on once-campfire a
  `RoomMessagesChannel` survivor looked impossible until applied by hand.
- A forced condition renders in the report when its code forwards the
  method's anonymous arguments (`tag.div(class: "a", &)`, `call(*, **)`,
  `call(...)`). Cut out of its method the snippet did not parse, so the
  report's `mutated` was `null` and `kimera mutant` showed no `+` line; on
  once-campfire, both mutants of an `if`/`else` in
  `Messages::AttachmentPresentation`. The snippet is now parsed as if inside a
  method that takes them.
- `condition => true` and `condition => false` keep an assignment the
  predicate makes: `if page = next_page` pins to `if (page = next_page;
  true)`. The bare literal dropped the binding, so unparser could not write
  the body's read of `page`, and the point was dropped as unguardable. On
  once-campfire that hid two points (`Messages::ByBotsController`,
  `Webhook#extract_attachment_from`). A predicate that binds nothing is still
  not evaluated.
- `doctor --check-baseline` no longer calls a Rails suite that parallelizes
  red split across processes. Each of its shards ran the suite's own
  `parallelize`, so the shards' forked workers shared `test.sqlite3_0` and
  the rest ("database is locked"): on once-campfire 236 of 601 tests failed,
  where `kimera run`, which gives each worker its own database, was green.
  Each shard now runs in one process on a test database of its own, through
  the same Rails parallel-testing hooks a worker calls.
- What each new setting costs, on dry-inflector's `lib` (`--operators all`,
  738 mutants, `--jobs 4`, one run each on a shared 4-vCPU VM): default 67s
  (main 72s, same verdicts); `--seed 1` 70s; `--count-no-coverage` 63s (the
  report only); `--flaky-runs 3` 92s (three more runs of the covering
  tests); `--attribution unit` 41s (the 535 `uncovered_by_unit` mutants run
  no tests). `--test-quality` reruns every other covering test of each
  killed mutant alone: two files whose 15 mutants about 620 specs each cover
  took 89s against 14s, and the whole `lib`, about 820 covering specs a
  mutant, ran past 20 minutes. On `examples/rails_app` every new setting
  keeps the expected verdicts with Minitest and RSpec at `--jobs 1` and 4
  (strict attribution turns the request-spec-only ones `uncovered_by_unit`).
- Test quality: `test_quality: true` (`--test-quality`), meant for nightly
  runs, records every covering test that kills each mutant
  (`killing_tests`), each run alone in a fresh fork with the mutant on, not
  only the first, and reports tests that kill none of the mutants they cover,
  redundant tests (every mutant they kill, another test kills too) and tests
  that cover no mutant in scope (`test_quality` in the JSON report, a summary
  in the text report). Verdicts don't change. Off by default. The Minitest
  isolated child now runs every test when not asked to stop at the first
  failure, as the RSpec one does, so an unmutated mirror that fails names
  every failing test.
- Seeds and flaky tests. `seed: N` (`--seed N`) seeds each test's random
  numbers with N and the test's id before it runs, on every tier, and gives
  Minitest N as its seed (it was always 1); `--seed random` draws N and the
  report records it. Unset, nothing changes: Ruby reseeds each forked test,
  as before. `flaky_runs: N` (`--flaky-runs N`) reruns the covering tests N
  more times under other seeds after the baseline; a test whose result
  changes is reported flaky (`flaky_tests` in the JSON report, "Flaky tests"
  in the text report) and never kills a mutant, since its failure says
  nothing about the mutant. A mutant only flaky tests cover reads
  `no_coverage`. Off by default.
- Strict attribution: `attribution: unit` (`--attribution unit`) lets only
  a unit's own tests kill its mutants, by the usual layouts
  (`spec/foo/bar_spec.rb` or `test/foo/bar_test.rb` for `lib/foo/bar.rb`,
  `spec/models/order_spec.rb` for `app/models/order.rb`) and `unit_tests:`
  rules (`--unit-tests GLOB=PATTERN`); `spec/unit/` and `test/unit/` count
  too, as does a directory of specs named after the file
  (`spec/unit/dry/inflector/underscore_spec.rb` for `lib/dry/inflector.rb`).
  A mutant only other units' tests reach
  (a request spec, say) is `uncovered_by_unit`: scored as not killed, gated
  as a survivor, and accepted by `baseline create` like one. Default `any`,
  as before. On `examples/rails_app`, 19 of the RSpec suite's 56 mutants
  become `uncovered_by_unit` (the controllers' and the checkout service's,
  which only its request spec reaches, and one of `Order`'s), and 5 of the
  Minitest suite's (`ApplicationController`, which has no test of its own).
  On dry-inflector (`--operators all`, 738 mutants), 535 are
  `uncovered_by_unit`: the inflection tables, acronyms and rules files have
  no specs of their own and are tested only through `Dry::Inflector`'s.
- `count_no_coverage: true` (`--count-no-coverage`) scores each mutant with
  no covering test as not killed, and fails the gate on it, in every command:
  `kimera run` too, not only `kimera ci` or `--fail-on-no-coverage`, which
  gate on uncovered mutants but leave them out of the score. Off by default.
  `schema/report.schema.json` describes the JSON report, and its `run`
  section records the setting.
- Nine new operator families, all opt-in (`--operators all`, or by name):
  - `super_call`: `super` / `super(...)` => nil.
  - `rescue_clause`: drop one `rescue` clause of a method body or a
    `begin`, or a `rescue` modifier; `ensure_clause`: drop an `ensure`.
    The guard for a method's own clause sits inside its body, so these are
    judged warm like any other mutant.
  - `assignment_deletion`: `@x = v => v`, and a local only where it rebinds
    a name already bound (`name = name.strip => name.strip`). The value is
    still computed and is still the statement's value; only the store goes,
    so a survivor means nothing reads it. Memoizing stores and an
    `@x = nil` in `initialize` are not targets.
  - `nil_literal`: `return nil` (`next`, `break`) and a method's tail `nil`
    => `::Object.new`.
  - `regexp_anchor` (drop `\A`, `^`, `\z`, `\Z`, `$`) and `regexp_quantifier`
    (`+ <=> *`, drop `?`, each `{n,m}` bound one step looser, `{n}` one
    either way), on the pattern's own syntax.
  - `keyword_drop`: drop one keyword argument at a call site.
  - `visibility`: a public instance method => private. A survivor is
    untested API or a method that should not be public. The schemata keeps
    the method public and registers it with the runtime, which makes it
    private when the mutant is activated (every name holding that
    definition, so an alias another file took too, not a later
    redefinition) and public again after; `respond_to?`, `method_missing`,
    `public_send` and Rails' action list see a real private method, and
    `send` still reaches it. A probe at the top of the method records its
    covering tests. The isolated tier bakes `private(:name)` after the
    `def`, and the warm verdicts match it.

  Measured on kimera's own `lib`, dry-inflector and the 22 holdout
  projects, with a reviewer judging a sample of each family's survivors
  (`eval/results/README.md`, O1): survivors judged equivalent or noise ran
  from 30% (`keyword_drop`, `regexp_anchor`) through 41%
  (`assignment_deletion`) to 75 to 80% (`regexp_quantifier`, `super_call`),
  so none joins the default set. Their verdicts agree with a fresh-process
  oracle on all 116 comparable dry-inflector mutants and all 109 holdout
  ones.
- A memo guard written `return @x if defined?(@x)` is read like
  `return @x if @x`: its store is not a target either.

- Faster, with the same verdicts. A mutant's covering tests now run fastest
  first by their baseline time (after the worker's recent killers), so a
  mutant most tests kill dies on a cheap unit test instead of after hundreds
  of slow integration tests. The whole-suite run in order is skipped when
  every mutant in scope already has a covering test, since it only marks
  uncovered points and could change no verdict. In the isolated tier, a
  mutant's child gets its tests fastest first and stops at the first one of
  them that fails, as the Minitest child already did, and the unmutated
  mirror baseline runs only the tests the isolated mutants will run (every
  test still, when one of them needs the whole suite). On a 4-vCPU VM,
  `--jobs 4`, against main:

  | Run | main | now |
  | --- | --- | --- |
  | kimera, 2 files of `lib/kimera/operators` (20 mutants) | 165s | 21s |
  | kimera, `lib/kimera/operators` + `lib/kimera/rewrite` (426) | 322s | 29s |
  | kimera, `lib/kimera/report` (287) | 140s | 31s |
  | kimera, 2 harness-critical files, isolated tier (21) | 254s | 38s |
  | kimera, everything (`.kimera.yml`, 4138) | 84.2 min | 27.3 min |
  | dry-inflector `lib`, `--operators all` (738) | 83s | 62s |

  Every verdict matched main's, except on the whole of kimera, where 37 of
  main's timeouts are now kills and 5 kills are timeouts (both count as
  killed). What is left is mostly the suite itself: the baseline runs each
  test once in a fresh fork, and a survivor runs every test that covers it.
- Code a test runs in a process it forks (a `fork { ... }` block, a forking
  job runner) is covered: while a coverage ledger is open, a forked child
  appends the mutants it touches to a spill file the parent's ledger reads
  back, through `Process._fork`. Such mutants read `no_coverage` before, and
  were never judged; kimera's own zygote child was one.
- An `alias_method` chain reopened in another file no longer hides the
  original's mutants: a method a later file redefined keeps that definition
  through the overlay, and the alias follows the overlaid original. The original's 12 mutants in
  the holdout's alias-chain project read `no_coverage`; they are now judged
  (and killed). Before, a wrapper whose file was not overlaid after the
  original's was replaced by the original, and the baseline went red.
- Code only an earlier test's state reaches (a cache hit) is judged: the
  baseline runs the whole suite once more, in order, in a fresh process, and
  a mutant that run reaches but no single test does is judged in a fresh
  mirror against the whole suite. Under `--no-rejudge` it stays
  `no_coverage`, with the reason as its detail (shown under the mutant in the
  text report).
- A baseline whose failing tests pass when the suite runs in order but fail
  alone in a fresh process is reported as order-dependent, naming those
  tests, instead of only "not green". Tests that also pass alone (shared
  paths across workers) keep the `--jobs 1` advice.
- `eval/holdout` holds 12 state-leak projects and an oracle written by
  another agent blind to kimera's tests (eval case H1). main agrees with
  that oracle on 74.6% of 394 compared mutants, with 100 false survivors and
  13 false `no_coverage`; this branch on all 441, with none.
- Verdicts no longer depend on state a test or an earlier mutant left
  behind. The parent boots the suite and overlays the schemata, then runs no
  test: each baseline test, and each mutant's covering tests, run in a
  process forked from that clean, post-boot state. A memo cache another file
  fills, a cache that hid a later caller from coverage, a registry, a class
  variable, a leaked `ENV` flag: on a corpus of such suites the warm pass
  reported 64 of 152 mutants survived that a fresh `rspec` kills, and 2
  killed that it doesn't; it now agrees on every one (`eval/run`, K1). Doubts
  and soft timeouts no longer retire workers, and nothing is requeued.
  `--leak-every` and `leak_every:` are gone: there is no warm state left to
  re-check. The cost is a fork per baseline test and per mutant, and a cold
  start in each: 3 to 26% on dry-inflector at `--jobs 4` (two runs), 21 to 53%
  on a small Rails suite at `--jobs 4` and 2 to 3 times the time at `--jobs 1`
  (`eval/results/README.md`).
- A warm survivor whose method also ran while the suite loaded (to build a
  constant, say) is judged again in a fresh mirror against the whole suite,
  since what it computed at load never saw the mutant.
- `define_method`, `define_singleton_method`, `lambda`, `proc` and `Proc.new`
  block bodies are mutated like method bodies. Code the scan doesn't mutate
  (any other block outside a method, a file that does not parse) is listed
  under "Not mutated" in the text report and `unmutated` in the JSON report
  and registry, with the reason, instead of being skipped in silence.
- `--since REF` diffs against `git merge-base REF HEAD` (keeping uncommitted
  work), so lines main changed after the branch point are no longer mutated.
- A `--session` is resumed only while its stamp matches: the sources, every
  file under the test roots, `.rspec`, `Gemfile.lock` and the judging
  settings. A kill no longer outlives the test that made it. `--session`
  creates the directory it saves into.
- Kimera runs with `LANG` unset or `LANG=C`: its reads, reports and pipes
  are UTF-8. `kimera mutant` and `kimera doctor` crashed on UTF-8 text there.
- Overlaid files run as `load` runs them, each in its own top-level scope;
  a top-level local one file set no longer leaked into another's lambdas.
- Guards dispatch through `::Kimera::RUNTIME`; `::MutantRuntime` is gone, so
  a project may define its own.
- A coverage ledger keeps each mutant id once: a covering test that loops
  3M times peaked at 440 MB, now 46 MB.
- `--isolated` mirrors run under the project's own Gemfile, so a gem named
  by a relative `path:` resolves; the overlay's alias scan no longer trips
  Rails' deprecated-constant proxies (16 warnings a run) and skips
  non-aliases.
- unparser 0.8.1 to 0.9.x are supported (was `~> 0.9.0`); CI runs the suite
  on each. The README names the whole runtime closure: prism, unparser,
  parser, ast, diff-lcs, racc.
- `examples/rails_app` (Rails 8.1, sqlite, Minitest and RSpec) runs end to
  end in CI in every mode against expected verdicts (`bin/e2e`).
- `bin/model-check` pins TLA+ tools v1.7.4: the v1.8.0 jar is re-published
  nightly, so its checksum never held. Trace validation passes again.
- `eval/run --kimera PATH` measures a checkout against these gaps.

- Survivors are easier to read. A report names each covering and failing
  test by `file:line` and description (a `tests` section in the JSON report,
  kept across `--session` resumes), not by RSpec's positional id alone. Each
  result carries a 1-based `column`, `end_line`, `end_column` and the
  enclosing `method`, and the text report places a mutant as
  `file:line:col  in method`. `kimera mutant` prints the source lines around
  the mutant, marking its own, or says the file changed since the report. A
  run over several files opens with a per-file table, most survivors first.
  A forced condition prints in its original form (`return false if false`),
  not as an if/end block; a multi-line failure detail prints aligned, without
  blank lines. A run with nothing to mutate reports `score=n/a`, not 100%.

- Every run saves its JSON report to `tmp/kimera/report.json` unless given
  `--report FILE` or `--no-report`, and `kimera report`, `kimera mutant` and
  `kimera baseline create` read it when no report is named, so triage needs no
  rerun. The next-action hints no longer suggest a full rerun or a report
  file the run never wrote, and `mutant --rerun` leaves the saved report
  alone.

- `kimera run app/models/order.rb:42` (or `:40-60`) mutates only those
  lines, and `--method NAME` only inside methods of that name. A target that
  matches nothing fails, naming the lines and methods that have mutants.

- A comment disables mutants inline:
  `# kimera:disable[-next-line] [OPERATOR ...]: REASON` ignores the mutants
  starting on that line (of those operators). The reason is required, the
  operators are checked, the mutants count toward `max_ignored`, and a
  comment that disables nothing is warned about. Ignore entries gain the
  `starts:` and `operator:` anchors behind it.

- CI output reads on its own. `--summary FILE` appends a Markdown summary of
  the findings to FILE, and `kimera ci` points it at `$GITHUB_STEP_SUMMARY`;
  `--format markdown` prints the same. `--format github` also writes the text
  report to stderr, so the job log shows the counts and survivors. GitHub
  annotations fold the mutants on one line into one, titled with the count,
  placed by column and carrying each diff, and a notice says where the rest
  are when a level passes the 10 GitHub shows per step. SARIF results carry
  the region's columns and the diff. On a pull request `kimera ci` mutates
  only the changed lines (`--since origin/$GITHUB_BASE_REF`), and a failed
  diff in a shallow clone says to fetch the base ref.

- Shorter errors: an unknown command, option or operator prints one line, a
  "did you mean" where one is close, and the help command to run, not the
  whole help text. Completion and suggestions leave out the old `dump` and
  `survivors` aliases. `kimera baseline --help` lists its commands.

- `kimera baseline create --write` sets `baseline: FILE` in `.kimera.yml`.

- `kimera init` writes a commented `.kimera.yml` that names its JSON schema
  (`schema/kimera.schema.json`, shipped in the gem), so editors complete and
  check the keys. It no longer writes to `AGENTS.md`: `kimera skill` is how
  agents get the guide. A spec checks the skill and the README against the
  commands, flags, config keys and operators the CLI accepts, so neither can
  drift from it.

- Code that the suite reaches through another file is no longer reported as
  uncovered. A method called through an `alias` or `alias_method` declared in
  another file kept running its unguarded body after the overlay, so its
  mutants came out `no_coverage` even with `--isolated`, and `kimera ci`
  failed on mutants the suite kills. The overlay (and the reload fallback) now
  re-points every such alias at the redefined method, so those mutants are
  judged warm. A method the suite only runs while it loads (a class macro that
  `define_method`s, an `included` hook another file's class body triggers)
  runs before any guard exists; its uncovered mutants are now `isolated_only`
  with that reason, out of `--fail-on-no-coverage`, and `--isolated` judges
  them against the whole suite.

- A custom operator declares its key on the instance: `def key =
  "authorization"`, and `def statement? = true` or `def body? = true` when
  it applies, in the class body rather than under `class << self`. An
  operator written the old way fails to register (`must define #key`);
  move its `def`s out of `class << self`. The operator audit is an
  instance too: `Kimera::Operators::Audit.new(operators).faults(source)`.
  Kimera's own code now follows rubocop-kata's rule that class methods only
  construct, and its development tooling tracks rubocop-kata and hashira
  from their main branches.

- Kimera requires unparser 0.9.x (it accepted any 0.x). It patches unparser's
  range writer, local-variable scope and parser builder, and those are
  internals: another release could rename one, and the patch would silently
  stop applying, so bakes would again read back as different programs. A spec
  now fails if any patched method is no longer unparser's to patch.

- `kimera doctor` no longer warns about a coverage floor that already
  applies only when an environment variable asks for it. It flagged any
  helper that mentioned `minimum_coverage` and not `KIMERA`, so pundit's
  floor, which sits under `if ENV["COVERAGE"]` and never runs under Kimera,
  drew a warning and an edit it didn't need. Doctor now parses the helper
  and warns only about a `minimum_coverage` or `minimum_coverage_by_file`
  call that no condition on `ENV` guards: `if`/`unless`/`elsif`, their
  modifier and ternary forms, `&&`/`||`, a `case` on `ENV`, and an earlier
  `return`, `next`, `exit` or `abort` guarded by `ENV` in the same scope all
  count, whatever the key. A floor under any other condition (a Ruby
  version, `defined?(SimpleCov)`) still warns, since that condition holds
  under Kimera too, and the warning now says the floor can fail Kimera's
  partial runs rather than that it does. A helper Prism can't parse is
  judged by the old text match.

- A red baseline from a suite that isn't parallel-safe now says to try
  `--jobs 1`. `kimera init` writes `jobs:` at the core count, and thor
  (every test shares `spec/sandbox`), sinatra (`send_file` tests write and
  delete `test/file.txt`) and devise (generator tests share `tmp/`) are red
  on four workers and green on one. The error named no next step, and on
  thor it listed about 80 test IDs on a single line before the per-worker
  traces. A baseline that ran on several workers now ends with `ran on N
  workers: if these pass with --jobs 1, the suite shares state between
  workers (a directory, file or port)`, and the failing tests are listed one
  per line, the first 10 and then `… and N more`, as `doctor` lists them.
  The baseline Kimera checks in one process (`--no-coverage`, `--jobs 1`)
  gives no such hint. `kimera doctor --check-baseline` ran the suite in one
  process only, so it called these suites green; with `jobs:` over 1 it now
  also runs the suite split across that many processes, dealing each file's
  tests out in turn as the warm pool does, and warns with the failing tests
  when that is red. `--jobs N` checks another width; `--jobs 1` skips it.
- A run whose stderr is not a tty now says how far it has got. Progress drew
  only on a tty, so in CI or under `2> log` a warm run printed nothing
  between the scan warnings and the report: on Lobsters, 61 minutes of
  silence for 4,124 mutants, with no telling a slow run from a wedged one.
  Each phase (the coverage baseline, the warm pool with its reload tier,
  `--isolated`, the re-judge pass) now prints a plain line to stderr when it
  starts, at most one every 30 seconds as mutants complete, and one when it
  ends, with the counts by status, the rate, an ETA and the time elapsed:
  `kimera: mutants (warm) 1210/4124 29%  killed=801 survived=312
  no_coverage=97  1.7/s  ETA 29:03  12:04 elapsed`. The tty bar is
  unchanged; `--progress` off a tty, which printed the bar's text every 10
  seconds, prints these lines too; stdout stays clean under `--format json`,
  `sarif` and `github`. The isolated tier no longer traces one line per
  verdict (4,124 lines on Lobsters); each verdict, with its duration, is in
  the report. `--no-progress` (`progress: false`) now silences all
  progress, including the isolated baseline and re-judge notices it used to
  print.
- Processes a test starts no longer outlive a warm worker the watchdog
  kills. Sinatra's integration tests start server subprocesses and stop
  them in teardown; a worker SIGKILLed mid-test never ran that teardown,
  and the servers, reparented to init, kept running and holding their ports
  an hour after `kimera run` exited. Warm workers (the coverage pass's too)
  and reload children now lead a process group of their own, as isolated
  children already did. The watchdog kills the whole group, and once any
  of these children is reaped, however it ended (a crash, or a worker's
  `exit!` past `at_exit` hooks), what it left running in its group is
  killed too. Outside the terminal's process group they no longer get its
  Ctrl-C, so a run that is interrupted (INT, TERM) or aborts now kills and
  reaps them itself on the way out; an isolated child, already outside it,
  used to keep running after a Ctrl-C. A process that leaves the group on
  purpose (`setsid`, `pgroup: true`) still outlives the run.
- A string literal with a byte escape that is not valid UTF-8, like the
  `"\xFF\xD8\xFF".b` Lobsters sniffs JPEG uploads with, no longer takes its
  whole file down. Ruby and Prism read the escape as that byte, but the
  parser gem under unparser rejected the literal (`literal contains escape
  sequences incompatible with UTF-8`): warm runs reported all 13 of
  `avatars_controller.rb`'s mutants unmutatable, and `--isolated` and
  reload reported each an `error`, which counts as killed, so its survivors
  passed the gate. Kimera now keeps the literal's bytes, in its own parses
  and in unparser's round-trip checks, and unparser writes them back as the
  same escapes, so the file is mutated like any other. Where unparser still
  can't write such a literal (a heredoc without interpolation and
  juxtaposed strings fail, and a backtick command came back with the raw
  byte, which Kimera now refuses), the file is spliced per method, as any
  file unparser can't write, and only the method holding it is unmutatable.
  A bake that unparser can't write for the whole file is now also written
  for its point's method alone and spliced in, as warm runs splice such a
  file, where `--isolated` and reload reported every mutant in it
  unmutatable.
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
  text. Kimera's own default mutant set shrinks from 3,738 to 3,503.
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
