# External holdout corpus

Twelve small Ruby projects, `p01_memo_cache` to `p12_alias_chain`, each with
an RSpec suite that is green under plain `rspec`, passes example by example
and under random seeds, and leaks state between tests in its own way: a
class-level memo, a registry, globals, class variables, a mutated constant,
`ENV`, `define_method` bodies, a lazy singleton, a memoised `Data` default, a
counter, a keyed cache, and an `alias_method` wrapper reopened in a second
file.

They and `oracle.rb` were written by a separate agent that did not read
kimera's sources, its tests, or the rest of `eval/`, to check the fixes
against cases nobody tuned them on. They are copied here unchanged.

`oracle.rb PROJECT REPORT.json --json OUT` bakes every mutant of a kimera
JSON report into a fresh copy of the project by replacing its reported
source span, and runs plain `rspec` in a new process: a non-zero exit (or a
30 s timeout) is killed, zero is survived. A deleted statement is applied
both as a removal and as `nil`; the mutant is skipped if those disagree.

`eval/run` runs them as case H1 (`eval/lib/kimera_eval/cases/h1_holdout.rb`)
with `kimera run --operators all --jobs 2` and scores agreement, false
survivors, false kills, and false `no_coverage` (a mutant kimera calls
uncovered that the plain suite kills).
