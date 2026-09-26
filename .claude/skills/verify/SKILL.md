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

# Self-host (~2,550 mutants, several minutes with jobs:4 from .kimera.yml;
# gated at max_survivors: 0, so exit 0):
bundle exec kimera run --report /tmp/self.json
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

- Survivors gate via `--max-survivors`. `no_coverage` mutants do NOT gate and
  do not lower the score (0 covered mutants → "score=100.0%", exit 0).
- `--since REF` silently selects 0 mutants when the project root is a
  subdirectory of the git repo (git emits repo-root-relative paths; the
  registry uses project-relative ones). Test `--since` only in a repo whose
  root is the project root.
- `examples/sample_app` sits inside this repo, so `--since` can't be tested
  there; copy it out and `git init`.
- In zsh, `time cmd | head` mangles `$?`/pipestatus; capture exit codes
  without `time` or pipes.
- The `parser` gem prints a Ruby 4.0 frozen-string deprecation warning on
  minitest runs; harmless.
