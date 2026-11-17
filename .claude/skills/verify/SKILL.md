---
name: verify
description: How to build, run, and verify the kimera mutation-testing gem end-to-end
---

# Verifying kimera

Kimera is a CLI gem: `bundle exec kimera <command>` (`kimera help` lists
`init`, `doctor`, `run`, `changed`, `ci`, `report`, `mutant`, `registry`,
`synthesize`, `baseline`). Verify by
driving the CLI against the runnable fixtures, never by unit-calling lib code.

## Setup

```sh
bundle check || bundle install   # repo root; Ruby >= 3.4 required
```

## Drive it

```sh
# RSpec fixture (28 mutants, 5 known survivors, exit 2):
cd examples/sample_app
bundle exec kimera run app --tests 'spec/**/*_spec.rb' --report /tmp/report.json

# Minitest fixture (15 mutants, 1 known survivor):
cd examples/minitest_app
bundle exec kimera run app --framework minitest --tests 'test/**/*_test.rb'

# Self-host (about 7,400 mutants, gated at max_survivors: 0, so exit 0; CI's
# job took 63 minutes at b701df4, before the runtime and the two child
# entrypoints were in scope, so run it only when asked):
bundle exec kimera run --report /tmp/self.json

# A self-host subset (776 mutants, about 100 s with --jobs 4 on 4 vCPUs):
bundle exec kimera run lib/kimera/operators lib/kimera/rewrite --jobs 4
```

Cross-check modes: on sample_app, `--jobs 4` and `--isolated` must produce
verdicts identical to the serial warm run (compare `results[].status` by
`mutant_id` in the JSON reports). On minitest_app,
`--framework minitest --isolated` must match its warm run.

Ground truth for a single verdict: apply the mutation by hand to the fixture
source, run `bundle exec rspec`, then restore the file. Careful:
`git checkout -- <file>` also reverts any uncommitted work in it.

## Out-of-tree fixtures

```sh
BUNDLE_GEMFILE=<kimera repo>/Gemfile bundle exec kimera run app --tests '...'
```

## Expected exit codes

`0` pass, `1` usage/setup error or baseline not green (clean one-line error),
`2` gate failed (survivors, uncovered, ignore budget, or unjudged).

## Gotchas

- Survivors gate via `--max-survivors`. `no_coverage` mutants also gate and
  score as not killed by default (`count_no_coverage: true`); pass
  `--no-count-no-coverage` to report them without scoring them.
- `--since REF` works when the project root is a subdirectory of the git
  repo (a copy of `examples/sample_app` at `services/shop` of a fresh repo
  selects the changed file's 22 mutants). To test it on a fixture, copy the
  fixture out and `git init`, so the edit that makes the diff stays out of
  this checkout.
- A change to `lib/kimera` changes the suite a self-host run uses as its
  tests: a switch read from `ENV` in `lib` also reaches kimera's own specs
  and turns the baseline red. Time such an experiment on another project
  (`eval/tmp/dry-inflector`, set up as eval case S1 does).
- In zsh, `time cmd | head` mangles `$?`/pipestatus; capture exit codes
  without `time` or pipes.
