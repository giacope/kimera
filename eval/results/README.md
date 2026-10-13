# Evaluation results

`before.json` is `main` at 758df8f; `after.json` is this branch at 896c80f.
Both ran with `ruby eval/run --kimera PATH --out FILE` (full mode), one after
the other on the same idle 4-vCPU Xeon VM (2.8 GHz, 15 GB, Ruby 3.4.7). Each
case's oracle runs plain `rspec`/`ruby -Itest` in a fresh process on a copy of
the fixture with the mutant baked into the source, so it shares nothing with
kimera's warm path. `eval/lib/kimera_eval/cases/*.rb` defines each measure.

## Gaps

| Gap | What is measured | main | branch |
| --- | --- | --- | --- |
| K1 | Stateful suites (memo caches, hidden callers, registries, class vars, leaked `ENV`, Minitest, boot-computed constants): verdicts vs the oracle | 152 mutants: 64 false survived, 2 false killed, 56.0% agree | 0 false survived, 0 false killed, 100% agree (2 load-time mutants abstain as `isolated_only` on both) |
| K2 | Lines in `define_method`/`lambda`/`proc` bodies and class-level blocks that are neither mutated nor reported; unparseable files not reported | 8 of 10 silent, 1 unparseable file unreported, 9 mutants | 0 of 10 silent, 0 unreported, 28 mutants, 0 false verdicts |
| K3 | Rails 8.1 app, Minitest and RSpec, `--jobs 1/4`, `--isolate-db`, `--isolated`, vs expected verdicts and the oracle | 0 false verdicts, 81 state-leak warnings, `--isolated` with a relative `path:` gem errors | 0 false verdicts, 0 warnings, 0 errors |
| K4 | Peak RSS of a covering test that loops 3M times | 440.4 MB | 46.0 MB |
| K5 | `--since main` on a branch that main moved past | mutates main's later lines too | only the branch's lines |
| K6 | `--session` resumed after a test changes | 2 stale verdicts | 0 |
| K7 | `LANG` unset and `LANG=C` | 4 failed steps, 10 suite failures | 0, 0 |
| K8 | `bin/model-check` fetch, model check, trace validation | all fail (checksum of a re-published jar) | all pass (v1.7.4 pinned) |
| K9 | unparser releases the gemspec allows, and the suite on each | 0.9.0 only | 0.8.1, 0.8.2, 0.9.0, none broken |
| K10 | Runtime closure named in the README | parser, racc unnamed | all 6 named |
| K11 | Two overlaid files sharing a top-level local name | baseline red, run fails | 0 false verdicts |
| K12 | Top-level constants kimera adds; a project defining `MutantRuntime` | `Kimera`, `MutantRuntime`; collision run errors | `Kimera` only; collision run ok |
| K13 | Overlay-time `ObjectSpace` scan on the Rails app | 0.174 s, 16 deprecation warnings | 0.168 s, 0 warnings |
| X1 | `--session` into a missing directory | crash, nothing saved | saved |

## Speed (S1, and K3's per-mode wall time)

| Run | main | branch | change |
| --- | --- | --- | --- |
| `examples/sample_app`, `--jobs 1` | 1.36 s | 2.64 s | +94% |
| `examples/sample_app`, `--jobs 4` | 1.36 s | 1.46 s | +7% |
| dry-inflector `lib`, `--operators all`, `--jobs 4` (738 mutants) | 88.5 s | 91.3 s | +3% |
| kimera self-host, `lib/kimera/operators` + `lib/kimera/rewrite`, `--jobs 4` | 421.1 s (425 mutants) | 205.0 s (426 mutants) | -51% |
| Rails app, Minitest, `--jobs 1` (56 mutants) | 6.4 s | 14.1 s | +119% |
| Rails app, Minitest, `--jobs 4` | 5.8 s | 8.2 s | +40% |
| Rails app, RSpec, `--jobs 1` | 6.0 s | 15.1 s | +152% |
| Rails app, RSpec, `--jobs 4` | 6.2 s | 7.5 s | +21% |
| Rails app, RSpec, `--isolated --jobs 4` | 53.6 s | 40.7 s | -24% |

The cost of judging in fresh processes is a fork per baseline test and per
mutant, plus a cold start in each child: Rails' per-test setup (fixtures,
transaction) runs again in every child, about 90 ms a mutant. It shows most
on small suites at `--jobs 1`; at `--jobs 4` the forks overlap. dry-inflector
(plain Ruby, fast tests) pays 3%. Both dry-inflector runs agree with the
oracle on all 738 mutants. The self-host subset ran faster on the branch, which
no longer runs main's periodic state-leak re-checks (main's run reported 4
leak warnings); the gap was not broken down further, so don't read it as a
general speed-up.

Summed resident memory across the process tree rises (dry-inflector 580 MB to
976 MB; Rails `--jobs 4` 497 MB to 811 MB) because the sampler counts each
short-lived child's copy-on-write pages again; the largest single process is
unchanged (220 MB and 214 MB).

Timings are single runs on a shared VM: treat differences under about 10% as
noise.
