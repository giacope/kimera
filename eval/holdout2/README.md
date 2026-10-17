# External holdout corpus, batch 2

Ten small Ruby projects, `q01_prepend_guard` to `q10_catch_throw_outline`, each a
realistic library of 40 to 95 lines of code with an RSpec suite (no gems beyond
rspec). Each suite passes under plain `rspec`, passes one example at a time and
passes under random seeds. Each one also leaks or depends on process state in a
way the first batch (`p01`..`p12`) does not cover:

| project | hard case |
| --- | --- |
| `q01_prepend_guard` | `Module#prepend`: a guard prepended from a second file at load time, and an audit wrapper prepended at runtime by a spec that stays prepended. The base method's own branch is shadowed by `super`. |
| `q02_ghost_methods` | `method_missing` / `respond_to_missing?` accessors that `define_method` a real method on first use, so later examples never reach the ghost path. |
| `q03_refinements` | `refine String` / `refine Integer`, activated with `using` in another lib file and in one spec file. |
| `q04_thread_local_rates` | A cross-rate memo in `Thread.current` (fiber-local storage) that is never cleared, and is seeded directly by one example. |
| `q05_sorted_versions` | `Comparable#<=>` that runs at load time to sort a frozen constant and take its `min`/`max`, and is called from C by `sort`, `between?` and `clamp`. |
| `q06_unit_classes` | Anonymous `Class.new` unit classes built in a loop at load time, named with `const_set` and given class-level ivars, plus a frozen index of them. |
| `q07_autoload_tariffs` | `Module#autoload`ed files whose load-time tables are built inside whichever example first names the constant. |
| `q08_dynamic_dispatch` | `__method__` forwarding, `send` to guard and hook names built from strings, `public_send` replay. Also a `let!` that sets a `class << self` accessor and never resets it. |
| `q09_before_all_catalog` | The parser's success path runs only in a `before(:all)` hook, outside any example. It uses a keyword_init `Struct` with a class-level default, and examples mutate the shared object. |
| `q10_catch_throw_outline` | `catch`/`throw` early exit and an `ensure` pop on a process-wide stack. A section left open is noticed only by later examples, such as a spec file that calls nothing that pushes. |

Each project's `NOTES.md` describes its case in a few lines. The suites assert
exact values, both sides of each conditional and the boundaries, so they kill
most mutants. Each one still leaves a few realistic gaps, such as untested
defaults, equivalent sign-only `<=>` results and unasserted history entries.

These projects were written on 2026-10-14 by an agent that did not read
kimera's sources, its tests, `eval/` (apart from `eval/holdout/README.md` and
`eval/holdout/oracle.rb`), the README, the CHANGELOG or the git history. That
agent did not install or run kimera either. The purpose is to check kimera
against cases nobody tuned it on. The batch is meant for kimera's JSON mutation reports,
the files `oracle.rb` reads, which are scored by the copied `oracle.rb`. The
reports are meant to include `killed`, `survived` and `no_coverage` mutants.

`oracle.rb` is an unchanged copy of `eval/holdout/oracle.rb`. To use it, run
`ruby oracle.rb PROJECT REPORT.json --json OUT`. For each mutant in the report,
it copies `lib/`, `spec/`, `.rspec` and `.kimera.yml` (if present) into a
fresh directory and applies the mutant by replacing its reported source span.
It then runs plain `rspec` in a new process. A non-zero exit, or a timeout,
counts as killed; zero counts as survived. Every project matches that layout:

- `lib/` holds the code.
- `spec/spec_helper.rb` puts `lib/` on the load path and requires the entry file.
- `.rspec` contains `--require spec_helper`.
- There is no Gemfile, and `rspec` must be on `PATH`.
- `.rspec` sets no order, so plain `rspec` runs in defined order, the same way the oracle runs it.
- All sources are ASCII, so the oracle's column arithmetic is not affected by the locale.

`verify.rb` checks the suites. Run it as `ruby verify.rb [PROJECT ...]`. For each
project, it runs the following:

1. `rspec`
2. `rspec --dry-run --format json` to list the examples, then `rspec FILE:LINE`
   for every example location
3. `rspec --order rand:SEED` for seeds 1, 42, 1234, 31337, 65535 and 20261014

The last run (2026-10-14, ruby 4.0.7, rspec 3.13) was green for every project.
Each project has 10 to 19 examples, 135 in total. Every example location also
passed on its own.

As a smoke test of the oracle with this layout, I fed it a crude
hand-generated report for each project. The report held operator, literal and
boolean swaps, 261 mutants in all. The oracle accepted every project, and the
suites killed 216 of those mutants, with 38 surviving and 7 skipped. The
skipped mutants were `<` in `class X < Y`, which is invalid Ruby once mutated.

## In this repository

The batch is copied here unchanged except for `oracle.rb`, which is left
out: it matched `eval/holdout/oracle.rb` byte for byte, and `eval/run` runs
the batch as case H2 (`eval/lib/kimera_eval/cases/h2_holdout.rb`) against that
one copy, with `kimera run --operators all --jobs 2`, scored as H1 is.
