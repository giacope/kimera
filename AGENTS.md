# Working on kimera

Kimera is a mutation-testing gem for Ruby (RSpec and Minitest). The CLI is
`exe/kimera`; everything else is under `lib/kimera`. `README.md` is the user
manual, `skills/kimera/SKILL.md` is the agent skill the gem ships
(`.claude/skills/kimera` is a symlink to it), and
`.claude/skills/verify/SKILL.md` says how to drive the CLI against the
fixtures in `examples/`.

## Checks

Run what your change can break. Times are from a 4 vCPU machine, Ruby 4.0.2.

| Command | What it checks | Time |
| --- | --- | --- |
| `bin/spec` | all specs, about 3,400 examples | 6 to 8 min |
| `bin/spec spec/kimera/path/to_spec.rb` | one file | seconds |
| `bundle exec rubocop` | style, with sekisho's dogmatic profile | under 1 min |
| `bundle exec sekisho lint --ratchet` | lint against `.sekisho_baseline.json`: no cop may gain an offense | under 1 min |
| `bundle exec sekisho doctor` | dead lint configuration, and the inline-disable budget | under 1 min |
| `bundle exec sekisho design --fail-on all` | design and architecture (`.sekisho.yml`); `crap` needs a `COVERAGE=1 bin/spec` run first | 10 s |
| `bundle exec kimera run --since origin/main --fail-on-no-coverage` | kimera on its own changed files; no survivor is allowed | 1 min and up |
| `examples/rails_app/bin/e2e` | a Rails app end to end | 2 min |
| `ruby eval/run --kimera . --out tmp/eval.json` | verdicts against oracles; `--only H1,K2` runs a subset | 17 min |
| `bin/model-check` | TLA+ model of the worker pool (needs Java) | not measured here |

## Shipping

Kimera is developed trunk-based, and there is no GitHub CI: every change is
committed on `main` and pushed straight to `origin/main` from an Amp orb, and
the agent that pushes is the CI. Before each push, rebase onto `origin/main`
and run, one after another, everything below. Push only when all of them
pass; when one fails, check it on `origin/main` without your change before
calling it not yours, and say so.

1. `bundle exec sekisho lint --ratchet`, `bundle exec sekisho doctor`
2. `COVERAGE=1 bin/spec`, then `bundle exec sekisho design --fail-on all`,
   which reads that run's coverage for `crap`; then `bin/spec` again on
   Ruby 3.4, the oldest the gemspec allows, which `.agents/setup` installs
   off `PATH`:
   `PATH="$(echo /opt/hostedtoolcache/Ruby/3.4.*/x64/bin):$PATH" bin/spec`
3. `bundle exec kimera run --since origin/main --fail-on-no-coverage`
4. `examples/rails_app/bin/e2e`
5. `gem install rspec -v "~> 3.13" --no-document` (once per orb), then
   `ruby eval/run --kimera . --only H1,K1,K2,K4,K5,K6,K7,K11,K12,X1 --baseline eval/results/after.json --out tmp/eval.json`
   (about 5 minutes; `eval/results/README.md` says why these cases)
6. `bin/model-check`

A change to Markdown files only needs `bin/spec spec/kimera/usage_drift_spec.rb`.
If the push is rejected because `main` moved, rebase and run the gate again.

Too slow to gate each push, and run when asked or after a change to what they
cover: the full self-host run (`bundle exec kimera run --judge-isolated-only
--reuse-coverage --report tmp/selfhost.json`, about an hour, which also stores
the coverage map later `--since` runs reuse), `bin/model-check --deep`, and
`PBT_SCALE=10 bin/spec spec/property`.

## Rules the linters enforce

`.rubocop.yml` inherits sekisho's dogmatic profile, its strictest: the
strict Elegant Objects profile plus one-word names, one level of nesting, and
tests with no hooks, sleeps or reflection. `lib`, `exe` and the specs keep
zero offenses, so `.sekisho_baseline.json` records none; `sekisho lint
--ratchet` fails on any offense. A spec that runs kimera in-process hands it
a `FakeBench`, whose environment is a Hash, so the run's `KIMERA` variables
stay out of `ENV`; a fake test that must take time advances the stubbed
`Kimera::Execution::Stopwatch::CLOCK` instead of sleeping. Run
`bundle exec rubocop` on the files you touch before the suite. The cops hit
most often:

- No comments in `lib` (`Sekisho/NoComments`); a `rubocop:disable` needs a
  reason after `--` (`Sekisho/JustifiedDirective`).
- Names are whole words, no abbreviations (`Sekisho/RealWords`), and a method
  or variable name is one word (`Sekisho/GoodMethodName`,
  `Sekisho/GoodVariableName`).
- No branch inside a branch (`Metrics/BlockNesting`, `Max: 1`); a modifier
  `if` is not a level.
- A class has at most 4 instance variables, 4 public methods and 100 lines;
  a method at most 10 lines, with no blank line inside.
- Collaborators are handed in, usually as `@options.fetch(:name) { build }`
  (`Sekisho/NoHardWiring`); a constructor only stores them
  (`Sekisho/ConstructorDiscipline`).
- A method either answers or acts, not both (`Sekisho/CommandQuery`). No
  getters, setters, boolean flags, `nil` arguments or `nil` returns.
- `ENV`, the clock and IO are read at the edges only (`Sekisho/EnvDiscipline`,
  `Sekisho/ClockDiscipline`, `Sekisho/IoDiscipline`).
- Specs use no mocks (`Sekisho/NoMock`), no `before`/`after`/`around` hooks
  (`Sekisho/NoTestHook`), no timed `sleep` (`Sekisho/NoTestSleep`) and no
  `__send__` to a private method (`Sekisho/NoReflection`); an example is at most
  5 lines and a line at most 120 columns.
- `Sekisho/JustifiedDirective: MaxDisables` holds the inline disables at their
  count; `sekisho doctor` fails past it. Raise it in the change that adds one.

`.kimera.yml` gates kimera on itself at `max_survivors: 0` and
`max_ignored: 0`: a new line of `lib` needs a test that fails when the line
is mutated, and no `ignore:` entry or `kimera:disable` comment is accepted.

`lib/kimera/runtime.rb` is loaded into every project kimera tests. Requiring
it may define no constant outside `Kimera` (eval case K12 checks this).

## Things that are easy to get wrong

- A file the warm workers run through while they judge a mutant cannot be
  judged by them. List it in `Kimera::SelfProtection::HARNESS_CRITICAL_SUFFIXES`
  so its mutants go to the isolated tier.
- Kimera's own specs are the test suite of a self-host run, so a switch read
  from `ENV` in `lib` reaches them and turns the baseline red. Time an
  experiment on another project (eval case S1 sets up dry-inflector).
- Do not edit a tracked file of the project a kimera run is judging while
  it runs (for a self-host run, any file of this repository): the run
  reports the change and exits 1.
- `lib/kimera/runtime.rb` and the two isolated-child entrypoints are judged
  in the isolated tier, each mutant against the whole suite: a change there
  costs about 4 minutes of `kimera run lib/kimera/runtime.rb --jobs 4`.
- A change that alters verdicts needs an eval run: compare the scoreboard
  with `eval/results/after.json`, which the pre-push gate uses as its baseline, and do not
  edit that file to make a case pass.
- A behavior change gets a `CHANGELOG.md` entry under "Unreleased" with the
  numbers that justify it, and the README, the skill and
  `schema/kimera.schema.json` say the same thing as the code
  (`spec/kimera/usage_drift_spec.rb` checks flags and keys).
