# Evaluation results

`before.json` is `main` at 758df8f; `after.json` is this branch at 8099360.
Both ran with `ruby eval/run --kimera PATH --out FILE` (full mode), one after
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
