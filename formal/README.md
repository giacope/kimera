# Formal model of the warm worker pool

`WorkerPool.tla` is a TLA+ model of the parent's scheduling loop
(`WorkerPool`, `Fleet`, `Worker`, `StillbornGuard`) and the worker side of the
pipe protocol (`Shift`). It was written by reading that code, not extracted
from it. It exists because the pool is where a lost or duplicated message
would silently drop a mutant from the gate, or record two verdicts for one.

```sh
bin/model-check          # the instances CI checks (about 3 minutes)
bin/model-check 3 2      # any other N (mutants) and Jobs; 3 2 is tens of millions of states
```

`bin/model-check` needs Java 11+ and downloads the pinned `tla2tools.jar`
into `tmp/` on first use.

## What this establishes, and what it doesn't

TLC explores every reachable state of the model, but only for the finite
instances it's run on. CI checks (N, Jobs) = (2, 2), (3, 1) and (1, 3), and in
each of them every interleaving of parent and children satisfies the
properties below, including crashes, hangs and watchdog kills at any step.

It does **not** establish:
- correctness for other pool sizes (the small-scope hope is that bugs show up
  in small instances, but nothing here proves it);
- anything about the Ruby code beyond what the model captures. The model can
  drift from the code, and what it abstracts away (below) is unchecked.

A longer run of (3, 2) explored 39.7 million distinct states without a
violation before it was stopped. That run was not exhaustive.

## Properties

| Property | Meaning |
| --- | --- |
| `CompleteOnExit` | When `WorkerPool#run` returns normally, every mutant has exactly one verdict. |
| `VerdictAtMostOnce` | No mutant is recorded twice (`Schedule#record` never overwrites). |
| `Conservation` | At every step each mutant is in exactly one place: queued, awaiting a recheck, in flight on one live worker, or done. |
| `RequeueAtMostOnce` | A rechecked mutant never returns to a warm run that could requeue it again. |
| `RecheckOnFreshWorker` | A recheck only runs on a worker that has served nothing yet. |
| `FleetWithinJobs`, `SlotsExclusive`, `CanSpawn` | At most `--jobs` workers are live, each on its own test-database slot, and a slot is free whenever the pool spawns. |
| `Termination` | The run ends, under the fairness assumptions below. |

## Fairness and abstractions

`Termination` holds only under the spec's weak-fairness assumptions:
- the parent keeps refilling, and keeps servicing every worker whose pipe
  holds a message, and each such read completes (`Service` is one atomic step);
- each healthy child keeps taking steps (reads its offer, then answers,
  requeues, crashes or exits);
- a hung child is eventually killed by the watchdog. Healthy children are
  never assumed to be killed.

The model abstracts away:
- **Framing.** A message is atomic. A child that writes part of a line and
  stops is not represented. The Ruby parent used to block in `pipe.gets` on
  exactly that, before its watchdog could run: the second fairness assumption
  was false of the code. Fault injection found this, not the model. The parent
  now reads with `read_nonblock` and buffers partial lines per worker (see
  `WorkerPool#service`); regression specs are in
  `spec/kimera/execution/worker_pool_spec.rb` and
  `spec/property/worker_pool_spec.rb`.
- **Time.** A deadline is "may fire at any step"; there are no clocks.
- Message payloads beyond kind and mutant id, verdict details, and the tiers
  `Schedule` runs after the pool (reload and quarantine).
- Workers are numbered by spawn order, bounded by `Jobs + 2N`; `CanSpawn`
  checks that bound rather than assuming it.

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

## How the model relates to the code

The connection is model-inspired fault-injection testing, not conformance.
`spec/property/worker_pool_spec.rb` runs the real parent (`WorkerPool`,
`Fleet`, `Worker`, `StillbornGuard`) against forked children that follow
random scripts drawn from the model's child actions (result, leak, tainted,
requeue, crash, hang), plus one the model lacks (half a line, then silence).
It checks the model's safety invariants on what actually happened: one verdict
per mutant, of the kind the script calls for; one requeue per requeued mutant;
rechecks only on fresh workers; slots reused only after their holder is
reaped. It checks that an abort happens only when `StillbornGuard`'s condition
held. Each run is supervised in its own process group with an external
deadline.

It does not run the real `Shift` (the children are scripts that speak its
pipe protocol), does not replay TLC traces, and does not check that each real
step corresponds to a model transition. Stronger conformance claims would
need that evidence, such as trace validation of the real parent against the
spec.

## Evidence the invariants have teeth

Each bug below, seeded into the model, fails `bin/model-check` at N=2, Jobs=2
with a counterexample trace:

- rechecks handed to any worker: `RecheckOnFreshWorker`
- a removed worker's in-flight mutant not charged: `Conservation`
- no refill after a removal: `CompleteOnExit`
- a recheck allowed to requeue: `RequeueAtMostOnce`
- a result that leaves the worker in flight: `Conservation`
