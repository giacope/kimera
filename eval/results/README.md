# Evaluation results

`before.json` is `main` at 758df8f; `after.json` is the branch merged in #44,
at 8099360. They are a snapshot of those two commits, not of later ones; CI
re-checks part of them on every change (see the last section). Both ran with
`ruby eval/run --kimera PATH --out FILE` (full mode), one after
the other on the same 4-vCPU Xeon VM (2.8 GHz, 15 GB, Ruby 3.4.7). Each
case's oracle runs plain `rspec`/`ruby -Itest` in a fresh process on a copy of
the project with the mutant baked into the source, so it shares nothing with
kimera's warm path. `eval/lib/kimera_eval/cases/*.rb` defines each measure.

## External holdout (H1)

`eval/holdout` holds 12 state-leak projects and their oracle, written by
another agent that did not read kimera's sources, tests or this eval
(`eval/holdout/README.md`). Both versions ran with `--operators all --jobs 2`.

| Project | main: compared / agree / false survived / false no_coverage | branch |
| --- | --- | --- |
| p01 memo cache | 43 / 25 / 18 / 1 | 45 / 45 / 0 / 0 |
| p02 registry | 33 / 27 / 6 / 0 | 33 / 33 / 0 / 0 |
| p03 globals | 41 / 41 / 0 / 0 | 41 / 41 / 0 / 0 |
| p04 class variables | 45 / 22 / 23 / 0 | 45 / 45 / 0 / 0 |
| p05 mutated constant | 25 / 25 / 0 / 0 | 25 / 25 / 0 / 0 |
| p06 `ENV` leak | 41 / 41 / 0 / 0 | 41 / 41 / 0 / 0 |
| p07 `define_method` | 0 mutants | 33 / 33 / 0 / 0 |
| p08 singleton | 51 / 39 / 12 / 0 | 51 / 51 / 0 / 0 |
| p09 `Data` default | 34 / 34 / 0 / 0 | 34 / 34 / 0 / 0 |
| p10 counter | 23 / 23 / 0 / 0 | 23 / 23 / 0 / 0 |
| p11 keyed cache | 49 / 8 / 41 / 0 | 49 / 49 / 0 / 0 |
| p12 alias chain | 9 / 9 / 0 / 12 | 21 / 21 / 0 / 0 |
| **total** | **394 of 408 mutants: 74.6% agree, 100 false survivors, 13 false no_coverage** | **441 of 441: 100%, 0, 0** |

Neither version produced a false kill. "False no_coverage" is a mutant kimera
calls uncovered that the plain suite kills.

## External holdout, batch 2 (H2)

`eval/holdout2` holds 10 more projects, written by another agent blind to
kimera, its tests and this eval, and never used to tune kimera
(`eval/holdout2/README.md`); H1's oracle judges them. `holdout2.json` is one
run at 7627b14 (`lib/` as on `main` at 97c8d90), Ruby 3.4.11, 4 vCPUs, with
`--operators all --jobs 2`; two earlier runs gave the same counts, and so
did a run at 396ed99, after #45 (faster mutation runs) merged into `main`.
"Compared" leaves out `no_coverage` and the oracle's skips.

| Project | mutants | compared / agree | false survived | false killed | no_coverage (false) | oracle skipped |
| --- | --- | --- | --- | --- | --- | --- |
| q01 `prepend` guard | 116 | 104 / 103 | 1 | 0 | 12 (0) | 0 |
| q02 ghost methods | 141 | 138 / 135 | 0 | 3 | 2 (0) | 1 |
| q03 refinements | kimera's baseline is red: no report | | | | | |
| q04 `Thread.current` rates | 88 | 87 / 87 | 0 | 0 | 0 (0) | 1 |
| q05 sorted versions | 206 | 196 / 191 | 5 | 0 | 9 (0) | 1 |
| q06 unit classes | 141 | 137 / 137 | 0 | 0 | 4 (0) | 0 |
| q07 `autoload` tariffs | 65 | 64 / 64 | 0 | 0 | 0 (0) | 1 |
| q08 dynamic dispatch | 118 | 115 / 115 | 0 | 0 | 0 (0) | 3 |
| q09 `before(:all)` catalog | 178 | 173 / 173 | 0 | 0 | 5 (0) | 0 |
| q10 `catch`/`throw` outline | 106 | 102 / 102 | 0 | 0 | 0 (0) | 4 |
| **total** | **1159 in 9 projects** | **1116 / 1107 (99.2%)** | **6** | **3** | **32 (0)** | **11** |

Every disagreement reproduces by hand (mutant baked in, plain `rspec` in
order, and the killing example alone); none is the oracle's doing:

- q03: `lib/textkit/headline.rb` starts with `using TextKit::Refinements`.
  Under kimera the refined methods are missing from that file
  (`undefined method 'ordinalize' for an instance of Integer`), so the
  baseline fails at `--jobs 1` and 2 and nothing is judged. Plain `rspec`
  passes, in order, alone and under random seeds.
- q01, `lib/ledger.rb:24`, `Audit#withdraw`'s `result` deleted: survived,
  oracle killed. `spec/audit_spec.rb` prepends `Audit` to `Account` for the
  rest of the run; in order, the later `spec/overdraft_spec.rb:15` and `:21`
  withdraw through it and fail. Kimera judges the mutant only by
  `audit_spec.rb`'s own example, which does not check the return value.
- q02, `lib/settings.rb:35`, three mutants of `method_missing`'s
  `raise ArgumentError, "...expected #{expected}..."`: killed, oracle
  survived. In order, "returns defaults" has already defined `label`, so
  "rejects arguments to a reader" gets Ruby's own `ArgumentError (given 1,
  expected 0)` and never reaches line 35; run alone it does, and fails.
  Kimera judges it as it runs alone.
- q05, `lib/sem_ver.rb:38, 61, 72` (`split(".")`, `compare_pre`'s first
  condition, `numeric?`), five mutants: survived, oracle killed.
  `lib/releases.rb` sorts `SUPPORTED` and takes its `min` and `max` with
  `SemVer#<=>` while it loads; with the mutant baked in the constants come
  out in another order and the releases specs fail. Kimera judges them
  against constants the original code built, and no example checks those
  comparisons directly.

## Gaps

| Gap | What is measured | main | branch |
| --- | --- | --- | --- |
| K1 | Stateful suites (memo caches, hidden callers, registries, class vars, leaked `ENV`, Minitest, boot-computed constants): verdicts vs the oracle | 152 mutants: 64 false survived, 2 false killed, 56.0% agree | 0 false survived, 0 false killed, 100% agree (2 load-time mutants abstain as `isolated_only` on both) |
| K2 | Lines in `define_method`/`lambda`/`proc` bodies and class-level blocks that are neither mutated nor reported; unparseable files not reported | 8 of 10 silent, 1 unparseable file unreported, 9 mutants | 0 of 10 silent, 0 unreported, 28 mutants, 0 false verdicts |
| K3 | Rails 8.1 app, Minitest and RSpec, `--jobs 1/4`, `--isolate-db`, `--isolated`, vs expected verdicts and the oracle | 0 false verdicts, 79 state-leak warnings, `--isolated` with a relative `path:` gem errors | 0 false verdicts, 0 warnings, 0 errors |
| K4 | Peak RSS of a covering test that loops 3M times | 441.0 MB | 45.9 MB |
| K5 | `--since main` on a branch that main moved past | mutates main's later lines too | only the branch's lines |
| K6 | `--session` resumed after a test changes | 2 stale verdicts | 0 |
| K7 | `LANG` unset and `LANG=C` | 4 failed steps, 10 suite failures | 0, 0 |
| K8 | `bin/model-check` fetch, model check, trace validation | all fail (checksum of a re-published jar) | all pass (v1.7.4 pinned) |
| K9 | unparser releases the gemspec allows, and the suite on each | 0.9.0 only | 0.8.1, 0.8.2, 0.9.0, none broken |
| K10 | Runtime closure named in the README | parser, racc unnamed | all 6 named |
| K11 | Two overlaid files sharing a top-level local name | baseline red, run fails | 0 false verdicts |
| K12 | Top-level constants kimera adds; a project defining `MutantRuntime` | `Kimera`, `MutantRuntime`; collision run errors | `Kimera` only; collision run ok |
| K13 | Overlay-time `ObjectSpace` scan on the Rails app | 0.229 s, 16 deprecation warnings | 0.114 s, 0 warnings |
| X1 | `--session` into a missing directory | crash, nothing saved | saved |

## Speed (S1, and K3's per-mode wall time)

| Run | main | branch | change |
| --- | --- | --- | --- |
| `examples/sample_app`, `--jobs 1` | 1.30 s | 1.85 s | +42% |
| `examples/sample_app`, `--jobs 4` | 1.19 s | 1.40 s | +18% |
| dry-inflector `lib`, `--operators all`, `--jobs 4` (738 mutants) | 62.8 s | 79.2 s | +26% |
| kimera self-host, `lib/kimera/operators` + `lib/kimera/rewrite`, `--jobs 4` | 331.5 s (425 mutants) | 304.6 s (426 mutants) | -8% |
| Rails app, Minitest, `--jobs 1` (56 mutants) | 5.7 s | 15.3 s | +170% |
| Rails app, Minitest, `--jobs 4` | 4.9 s | 7.5 s | +53% |
| Rails app, RSpec, `--jobs 1` | 5.9 s | 14.8 s | +150% |
| Rails app, RSpec, `--jobs 4` | 4.9 s | 7.0 s | +43% |
| Rails app, RSpec, `--isolated --jobs 4` | 41.3 s | 39.3 s | -5% |

The cost of judging in fresh processes is a fork per baseline test and per
mutant, a cold start in each child, and one more run of the whole suite in
order to find code only an earlier test's state reaches. Rails' per-test
setup (fixtures, transaction) runs again in every child, about 90 ms a
mutant, so a small Rails suite at `--jobs 1` takes 2.5 to 3 times as long; at
`--jobs 4` the forks overlap. Both dry-inflector runs agree with the oracle on
all 738 mutants. The previous pair of runs on the same VM measured dry-inflector
at 88.5 s against 91.3 s (+3%), so the run-to-run spread on this shared VM is
large: treat single-run differences under about 25% as noise.

Summed resident memory across the process tree rises (dry-inflector 577 MB to
980 MB) because the sampler counts each short-lived child's copy-on-write
pages again; the largest single process does not grow (243 MB and 216 MB).

## New operators (O1)

Nine operator families were added, each measured on three corpora before
deciding whether it joins the default set: kimera's own `lib` (its
`.kimera.yml`, `--jobs 4`), dry-inflector's `lib` at the S1 revision
(`--jobs 4`), and the 22 holdout projects (`eval/holdout` p01-p12 and the
second batch q01-q10, `--jobs 2`; q03 is left out, since its suite of
refinements is red under kimera with any operator, on main too). Every
run used only the new families. Verdicts were checked against an oracle that
bakes each mutant into a copy and runs the plain suite: on dry-inflector all
116 comparable mutants agree, and on the holdouts all 109 (after one fix,
below).

An independent reviewer, given only the mutated code, its surroundings and
the names of the covering tests, judged a random sample of up to 20
survivors per family (all of them where fewer survived) as useful (a test,
or a change such as making a method private, a developer would make),
equivalent, or noise (observable but not worth a test). "Noise" in the
table is equivalent plus noise.

| family | mutants (kimera / dry-inflector / holdouts) | survived | judged | noise | worker s per mutant (kimera) |
| --- | --- | --- | --- | --- | --- |
| `assignment_deletion` | 321 / 15 / 24 | 21 (5.8%) | 17 | 7 (41%) | 4.7 |
| `keyword_drop` | 549 / 2 / 8 | 85 (15.8%) | 20 | 6 (30%) | 6.8 |
| `visibility` | 447 / 24 / 45 | 58 (11.3%) | 20 | 6 to 12 (30 to 60%) | 3.0 |
| `rescue_clause` | 73 / 0 / 0 | 12 (17.6%) | 12 | 6 (50%) | 4.9 |
| `ensure_clause` | 24 / 0 / 2 | 5 (20.8%) | 5 | 2 (40%) | 26.1 |
| `super_call` | 23 / 0 / 6 | 5 (17.2%) | 5 | 4 (80%) | 0.8 |
| `regexp_anchor` | 3 / 58 / 9 | 47 (67.1%) | 20 | 6 (30%) | 2.2 (dry-inflector) |
| `regexp_quantifier` | 13 / 18 / 12 | 25 (58.1%) | 20 | 15 (75%) | 2.3 (dry-inflector) |
| `nil_literal` | 0 / 0 / 2 | 0 | 0 | n/a | n/a |

- **Noise by family.** `assignment_deletion`'s equivalents are initial
  values a later read can't tell apart (`@flag = false` read only for
  truthiness); a sample of three more, `@x = nil` in `initialize`, is
  excluded by the operator now (an unset ivar reads nil). `keyword_drop`'s
  noise is all `encoding: Encoding::UTF_8`, which only a non-UTF-8 locale
  can observe; its useful survivors include real holes in kimera's own
  suite (a dropped `leaks:` loses reported leaks, a dropped `isolate_db:` is
  silently ignored). `visibility`'s range is the reviewers' split on one
  pattern: an operator's `variants`, the documented extension point, which
  only `self` calls; 5 other survivors are helpers only their own class
  calls. `super_call`'s equivalents are `super` in an `initialize` whose
  parent has none. `regexp_quantifier`'s noise is `.*` => `.+` in inflection
  rules, which only a bare suffix (`us`, `eau`) can tell apart. One
  `super_call` pattern is excluded now too: `super` in
  `respond_to_missing?` (Object's answers false; nil reads the same).
- **Cost.** Worker seconds are summed judge time over the mutants of one
  run, on a 4-vCPU VM that another agent's runs shared (load 8 to 12), so
  read them relative to each other: kimera's default set costs about 1.6 s a
  mutant there unloaded. `ensure_clause` is dear because its mutants sit in
  the harness and run its slowest tests. On dry-inflector, the default set
  takes 61.8 s (141 mutants); all nine new families together 67.8 s (117),
  `regexp_anchor` alone 58.4 s (58), most of it survivors running every
  covering test.
- **Decision: all nine are opt-in families, none joins the default set.**
  The closest, `assignment_deletion`, still had 7 of 17 judged survivors
  equivalent or noise, and would add 321 mutants (8%) to kimera's own
  gate; `keyword_drop` would add 549 (13%) at the highest cost per mutant.
  `nil_literal` has too few mutants on these corpora to measure (2, both
  killed).
- **Fix found by the oracle.** The first holdout run had one false kill:
  in p12 (alias chain), making `Order#total` private flipped the wrapper a
  later file defines under that name, where a `private :total` after the
  original's `def` reaches only the original and the alias taken of it. The
  runtime flip now applies to the names that hold the original definition;
  the 3 visibility mutants of p12 then agree with the oracle.
- **Schemata.** `spec/kimera` and the schemata properties (which now
  generate rescue, ensure, ivar, keyword and regexp forms) pass on unparser
  0.8.1, 0.8.2 and 0.9.0, and every file of kimera's `lib` and
  `examples` reduces to each of its mutants' bakes under all operators.

## In CI, and before a release

CI's `eval` job runs, on every push to main and every pull request, the
cases that need no network, Java or Rails app and whose result does not ride
on machine speed:

```sh
gem install rspec -v "~> 3.13"   # H1's oracle runs plain rspec, outside the bundle
ruby eval/run --kimera . --only H1,K1,K2,K4,K5,K6,K7,K11,X1 \
  --baseline eval/results/after.json --out tmp/eval.json
```

It exits 1 when one of them fails that `after.json` records passing: a false
survivor, false kill or false `no_coverage`, a silent line, a stale verdict, a
wrong `--since` selection. About 5 minutes on a
4-vCPU machine. K4 passes under 150 MB of peak RSS (46 MB measured), far from
the 441 MB it guards against. Left out: S1 measures wall time; K3 and K13 need
`examples/rails_app` (the `rails` job runs it end to end); K8 needs Java and
downloads tla2tools.jar (the `model-check` job); K9 and K10 resolve gems from
rubygems.org (the `unparser` job covers the allowed releases). H2 is
deterministic and takes 2 minutes, but it fails today, and a pass/fail gate
cannot hold a case that already fails; once kimera passes it, record it in
`after.json` and add it to the job's `CASES`. K12 is out for the same reason:
since c5cf269 put `require "tmpdir"` in `lib/kimera/runtime.rb`, loading
kimera also adds the top-level constants `Etc` and `FileUtils`. Put it back in
`CASES` once that is fixed.

Before a release, run every case on the previous release and on the
candidate, one after the other on the same machine, then update the tables
and the first paragraph:

```sh
git worktree add ../kimera-before PREVIOUS_RELEASE_COMMIT
ruby eval/run --kimera ../kimera-before --out eval/results/before.json
ruby eval/run --kimera . --baseline eval/results/after.json --out eval/results/after.json
```

The full run needs network access, Java 21 and `rspec` outside the bundle;
the last command exits 1 if a case regressed against the recorded
`after.json`, which it reads before replacing (until H2 passes, it fails
on H2, which `after.json` does not hold). Wall times and memory (S1, K3's
per-mode times, K4, K13) compare only between runs on the same machine;
across machines, compare verdicts.
