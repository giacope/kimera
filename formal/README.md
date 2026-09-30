# Formal model of the warm worker pool

`WorkerPool.tla` is a TLA+ model of the parent's scheduling loop
(`WorkerPool`, `Fleet`, `Worker`, `StillbornGuard`) and the worker side of the
pipe protocol (`Shift`). It was written by reading that code, not extracted
from it. It exists because the pool is where a lost or duplicated message
would silently drop a mutant from the gate, or record two verdicts for one.

```sh
bin/model-check              # the instances CI checks (about 2 minutes)
bin/model-check --deep       # larger instances, run by hand or from the Actions tab
bin/model-check 4 2          # any N (mutants) and Jobs: invariants and Termination
bin/model-check --safety 5 3 # invariants only, with symmetry reduction
```

`bin/model-check` needs Java 11+ and downloads the pinned `tla2tools.jar`
into `tmp/` on first use.

## What this establishes, and what it doesn't

TLC explores every reachable state of the model, but only for the finite
instances it's run on. In each, every interleaving of parent and children
satisfies the properties below, including crashes, hangs and watchdog kills at
any step. CI checks:

| N, Jobs | Checks | Distinct states | Time (4 cores) |
| --- | --- | --- | --- |
| 2, 2 | all | 15,103 | 3 s |
| 3, 1 | all | 2,011 | 1 s |
| 1, 3 | all | 130 | < 1 s |
| 3, 2 | all | 160,621 | 18 s |
| 5, 2 | invariants, symmetry | 164,282 | 14 s |
| 4, 3 | invariants, symmetry | 944,723 | 80 s |

"All" is every invariant and `Termination`, with no reduction. The
symmetry runs check the invariants only (see below). CI also checks that
the parent as it was before #2 (`Blocking = TRUE`, below) violates
`Termination` at (1, 1), so the model can't silently lose the ability to
see that bug.

It does **not** establish:
- correctness for other pool sizes (the small-scope hope is that bugs show up
  in small instances, but nothing here proves it);
- `Termination` beyond the sizes checked without symmetry;
- anything about the Ruby code beyond what the model captures. The model can
  drift from the code, and what it abstracts away (below) is unchecked.

### Why the state space is small, and why symmetry is sound

A live worker is named by the test-database slot it holds, and `Remove`
resets everything the model keeps for a removed worker (its pipes are closed
and its process reaped, so the parent never looks at it again). A state
therefore holds only what can still influence the run. Before this, workers
were numbered by spawn order and a dead worker's leftovers stayed in the
state: (3, 2) passed 39.7 million distinct states without finishing, where
it now has 45,498 with atomic messages and 160,621 with the framing below.
The seeded bugs below are still caught.

Nothing in the spec compares, orders or singles out an id or a slot: the
queue and `Fleet#slots` are sequences, the initial orders are one `CHOOSE`n
permutation (only `Init` uses it), and every property quantifies over all
ids or all workers. So renaming ids or slots maps each step to a step and
each state to a state that satisfies the same invariants, and TLC may keep
one state per orbit of `Permutations(Ids) \cup Permutations(Slots)` when it
checks invariants. It may not when it checks liveness: TLC's symmetry
reduction can miss or invent cycles, so `Termination` is only ever checked
without it.

## Properties

| Property | Meaning |
| --- | --- |
| `CompleteOnExit` | When `WorkerPool#run` returns normally, every mutant has exactly one verdict. |
| `VerdictAtMostOnce` | No mutant is recorded twice (`Schedule#record` never overwrites). |
| `Conservation` | At every step each mutant is in exactly one place: queued, awaiting a recheck, in flight on one live worker, or done. |
| `RequeueAtMostOnce` | A rechecked mutant never returns to a warm run that could requeue it again. |
| `RecheckOnFreshWorker` | A recheck only runs on a worker that has served nothing yet. |
| `Framed` | A worker's line buffer holds only the start of the next line: its rest is next in the pipe, or the child is still writing it, hung or dead. |
| `FleetWithinJobs`, `SlotsExclusive`, `CanSpawn` | At most `--jobs` workers are live; the live workers and `Fleet#slots` hold every slot exactly once between them, so no two live workers share a test database; a slot is free whenever the pool spawns. |
| `Reaped` | A worker leaves the fleet only with its process reaped. |
| `Termination` | The run ends, under the fairness assumptions below. |

## Fairness and abstractions

`Termination` holds only under the spec's weak-fairness assumptions:
- the parent keeps refilling, and keeps dispatching every worker's complete
  lines: `WF(Complete(w) /\ Service(w))`, where `Complete(w)` says the pipe
  holds a whole line or EOF. Nothing obliges the parent to read the start of
  a line whose rest may never come;
- each healthy child keeps taking steps (reads its offer, then answers,
  requeues, crashes or exits, possibly pausing partway through its first
  line);
- a hung child is eventually killed by the watchdog. Healthy children are
  never assumed to be killed.

### Framing

A pipe carries fragments: complete lines, `Part` (the start of a line whose
rest is the next fragment) and EOF. A child may stop partway through writing
its first line (`ChildTear`), then finish it, crash or hang. The parent
keeps a `Part` in the worker's line buffer (`buf`, `Worker#unread`) and
dispatches a line only once its rest arrives; at EOF a buffered start is
dropped, as `WorkerPool#hangup`'s `parse` drops it. `Framed` checks the
buffer only ever holds the start of the next line.

Until #2 the model had atomic messages and assumed every read completes.
That assumption was false of the parent then, which read with `pipe.gets`:
a child that wrote half a line and hung left it blocked in the read, before
its watchdog could run. Fault injection found that, not the model. The
constant `Blocking` puts the old parent back: reading a `Part` leaves it
stuck (`blocked`) until the rest or EOF arrives, and in the meantime it reads
no other pipe and runs no watchdog. TLC then finds the hang in 107 states at
(1, 1): the child tears its result line, the parent reads the start, the
child hangs, and the parent waits forever. With `Blocking = FALSE`
(`read_nonblock` and a line buffer, as the code is now) every CI instance
passes. Only tears before a child's first line of a reply are modeled; a
tear later in the reply is handled by the same buffer, and a long line read
in pieces from a healthy child is a stuttering step.

The model abstracts away:
- **Time.** A deadline is "may fire at any step"; there are no clocks.
- Message payloads beyond kind and mutant id, verdict details, and the tiers
  `Schedule` runs after the pool (reload and quarantine).
- Worker identity beyond the slot: two workers that held the same slot at
  different times share a name. `Fleet#slots` is modeled as the FIFO it is
  (spawn takes the head, remove appends).

## Action map

| TLA+ | Ruby |
| --- | --- |
| `Init`, `RefillStep` | `Fleet#bootstrap`, `Fleet#refill`, `Fleet#replace`, `Fleet#spawn` |
| `Assign`, `Take`, `Following` | `WorkerPool#assign`, `Fleet#take`, `Fleet#following`, `Worker#claim`, `Worker#offer`, `WorkerPool#close` |
| `Service` | `WorkerPool#service`, `Worker#lines`, `#hangup` and `#dispatch`: `#finish`, `#relay`, `Fleet#requeue` |
| `Remove` | `Fleet#remove`, `Fleet#charge`, `StillbornGuard#track` |
| `Expire` | `WorkerPool#watch`, `Worker#halt` |
| `ChildRead` | `Shift::Channel#each_request` (EOF means retired) |
| `ChildResult`, `ChildTainted` | `Shift#step`, `Shift#process`, `Shift#tainted?`, `Shift::LeakGuard#check` |
| `ChildRequeue` | `Shift::Suspect#message` (warm only: `Attempt#recheck` settles on a `Doubt`) |
| `ChildTear` | a write cut short: the start of a line, flushed |
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
- a removed worker's slot not returned: `SlotsExclusive`
- the parent blocking in `pipe.gets` (`Blocking = TRUE`): `Termination`,
  checked by CI at (1, 1)

They are also caught at (3, 2) with symmetry reduction.
