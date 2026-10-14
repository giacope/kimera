# examples/rails_app

A Rails 8.1 app on sqlite: validations, callbacks, associations with
`dependent:`, strong params, a transaction that rolls back, and a job, with
a Minitest suite (`test/`) and an RSpec one (`spec/`, `.kimera-rspec.yml`).
Its Gemfile names kimera by a relative path, as a monorepo names its engines.

```sh
bundle install
bundle exec kimera run                              # Minitest, one worker
bundle exec kimera run --jobs 4 --isolate-db        # per-worker databases, rolled back
bundle exec kimera run --config .kimera-rspec.yml   # RSpec
bin/e2e                                             # every mode against expected.json
```

`expected.json` holds, for each mutant, what a fresh `bin/rails test` (or
`rspec`) run says with that mutant baked in; `eval/run --only K3` checks it
against that oracle. `bin/e2e --write` records the current verdicts.
