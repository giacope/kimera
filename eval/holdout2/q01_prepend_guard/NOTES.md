# q01_prepend_guard

`OverdraftGuard` is `Module#prepend`ed into `Account` from a second file at load time, and `Audit` is
prepended at runtime by a spec and stays prepended for the rest of the process. `Account#withdraw`'s own
`InsufficientFunds` branch is shadowed by the guard (only reachable via `super`), and the guard's
`limit` is a class-level setting that one context sets and never resets.
