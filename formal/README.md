# Formal model of the warm worker pool

`WorkerPool.tla` is a TLA+ model of the parent's scheduling loop and the
worker side of the pipe protocol. TLC checks it exhaustively: every
interleaving of workers and parent, including crashes, hangs and watchdog
kills. The pool is the one part of Kimera where a lost or duplicated
message would silently drop a mutant from the gate or record two verdicts
for it, so it gets a proof rather than a handful of examples.

```sh
bin/model-check          # the sizes CI checks (about 3 minutes)
bin/model-check 3 2      # N=3 mutants on 2 jobs: tens of millions of states
```

`bin/model-check` needs Java 11+ and downloads the pinned `tla2tools.jar`
into `tmp/` on first use.

## What is checked

| Property | Meaning |
| --- | --- |
| `CompleteOnExit` | When `WorkerPool#run` returns normally, every mutant has exactly one verdict. |
| `VerdictAtMostOnce` | No mutant is recorded twice (`Schedule#record` never overwrites). |
| `Conservation` | At every step each mutant is in exactly one place: queued, awaiting a recheck, in flight on one live worker, or done. |
| `RequeueAtMostOnce` | A rechecked mutant never returns to a warm run that could requeue it again. |
| `RecheckOnFreshWorker` | A recheck only runs on a worker that has served nothing yet. |
| `FleetWithinJobs`, `SlotsExclusive`, `CanSpawn` | At most `--jobs` workers are live, each on its own test-database slot, and a slot is free whenever the pool spawns. |
| `Termination` | The run ends, assuming only that hung workers are eventually killed by the watchdog. Healthy workers are never relied on to be killed. |

The watchdog may kill any worker at any moment, since a slow test looks like
a hang. Safety must hold under every such race.

## Action map

| TLA+ | Ruby |
| --- | --- |
| `Init`, `RefillStep` | `Fleet#bootstrap`, `Fleet#refill`, `Fleet#replace`, `Fleet#spawn` |
| `Assign`, `Take`, `Following` | `WorkerPool#assign`, `Fleet#take`, `Fleet#following`, `Worker#claim`, `Worker#offer`, `WorkerPool#close` |
| `Service` | `WorkerPool#service` and `#dispatch`: `#finish`, `#relay`, `Fleet#requeue` |
| `Remove` | `Fleet#remove`, `Fleet#charge`, `StillbornGuard#track` |
| `Expire` | `WorkerPool#watch`, `Worker#halt` |
| `ChildRead` | `Shift::Channel#each_request` (EOF means retired) |
| `ChildResult`, `ChildTainted` | `Shift#step`, `Shift#process`, `Shift#tainted?`, `Shift::LeakGuard#check` |
| `ChildRequeue` | `Shift::Suspect#message` (warm only: `Attempt#recheck` settles on a `Doubt`) |
| `ChildCrash`, `ChildHang` | a process that dies, or stops answering |

## What is abstracted

Message payloads beyond their kind and mutant id, timing (a deadline is "may
fire now"), the ledger's verdict details, and the tiers `Schedule` runs after
the pool (reload and quarantine) are left out. Workers are numbered by spawn
order and bounded by `Jobs + 2N`, a bound `CanSpawn` checks rather than
assumes.

## Tying the model to the code

A model proves nothing about code it drifted from.
`spec/property/worker_pool_spec.rb` runs the real `WorkerPool` with forked
children that follow random scripts drawn from the model's child actions
(result, leak, tainted, requeue, crash, hang). It then checks the model's
invariants on what actually happened: one verdict per mutant, of the kind the
script calls for; one requeue per requeued mutant; rechecks only on fresh
workers; slots reused only after their last holder is reaped.

When you change the pool, change the model with it. Each seeded bug below
fails `bin/model-check` (at N=2, Jobs=2) with a counterexample trace:

- rechecks handed to any worker: `RecheckOnFreshWorker`
- a removed worker's in-flight mutant not charged: `Conservation`
- no refill after a removal: `CompleteOnExit`
- a recheck allowed to requeue: `RequeueAtMostOnce`
- a result that leaves the worker in flight: `Conservation`
