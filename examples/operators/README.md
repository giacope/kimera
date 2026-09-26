# Custom operators

Seven operators a host app could write for itself, in the shape kimera loads.
Each encodes a rule specific to *this* app that a general-purpose tool can't
see: a call whose deletion should break a test, a keyword whose absence should
be caught.

Wire them up:

```yaml
# .kimera.yml
require: [examples/operators/kimera_plugin.rb]
operators: [custom]      # or [all], or [comparison, custom]
```

or `kimera run --require examples/operators/kimera_plugin.rb --operators custom`.

| operator | mutation | what a survivor means |
|---|---|---|
| `authorization` | delete `authorize!` / `policy_scope` | nothing asserts the 403; the check is load-bearing only in production |
| `bang_call` | `create! => create` | the failure path is never exercised; the validation meant to abort never raises in a test |
| `background_dispatch` | `perform_later => perform_now`, `deliver_later => deliver_now` | no test asserts the enqueue; work never backgrounded looks identical to the suite |
| `http_status` | drop `status:` (falls back to 200) | request specs assert the body and let 201, 202 and 422 pass as 200 |
| `cache_expiry` | drop `expires_in:` | the TTL is decorative; nothing covers the re-read after expiry |
| `money_rounding` | `round(2) => round`, `floor <=> ceil` | money precision is untested; an invoice off by a cent passes |
| `encrypted_attribute` | delete `encrypts :tax_id` | the compliance claim has no test behind it; the suite cannot tell an encrypted column from a plaintext one |

## Writing your own

`variants` receives a [Prism](https://github.com/ruby/prism) node and returns
`Variant`s. A variant is a label for the report plus a *directive*: a rewrite
kimera already knows, with its arguments. `solo` and `deletion` are shorthands
for the common one-variant cases. The helpers in `Kimera::Operators::Vocabulary`
(`matches?`, `chained?`, `bare?`, `keywords`, `arguments`) cover most node
matching.

Two class-level flags control where an operator fires:

- `statement?`: the operator deletes or replaces a whole statement, so it runs
  only in statement position.
- `body?`: the operator applies to class-body DSL (`encrypts`, `validates`),
  which runs once at load. Those mutants are `isolated_only` on the warm path
  and need `--isolated` for a verdict.

## Before you gate on one

A run won't show two operator bugs: a directive that can't render, and one
that rebuilds the original source. The second is an equivalent mutant that
survives every run and gets hand-added to the ignore list. Audit against a
representative snippet:

```ruby
require "kimera/operators/audit"

faults = Kimera::Operators::Audit.faults(MyApp::Operators::ALL.map(&:new), File.read("app/controllers/orders_controller.rb"))
raise(faults.map(&:to_s).join("\n")) if faults.any?
```

`spec/kimera/operators/audit_spec.rb` runs exactly that against these seven.

## What you cannot do yet

Custom *rewrite handlers*. An operator composes the directives kimera already
ships: `selector_swap`, `drop_argument`, `kwarg_pair_drop`, `kwarg_element_drop`,
`statement_deletion`, `boolean_literal`, `condition`, `drop_element`,
`drop_receiver_link` and the rest of `Kimera::Rewrite::Directive::HANDLERS`.
Emitting an unknown directive type raises rather than silently passing.
