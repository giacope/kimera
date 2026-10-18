# q08_dynamic_dispatch

Event methods call `fire(__method__, ...)`; `fire` builds guard and hook names (`:"can_#{event}?"`,
`:"on_#{event}"`) and reaches them with `respond_to?(name, true)` + `send`, and `.replay` dispatches
script words with `public_send`. Class-level state lives in `class << self` accessors: a `let!` sets
`strict = true` and never resets it, `refund_window_days` is reassigned by examples, and the journal only
grows. The default window (`= 14`) is never observed on its own.
