----------------------------- MODULE WorkerPool -----------------------------
(***************************************************************************)
(* The warm worker pool: the parent's scheduling loop                      *)
(* (lib/kimera/execution/worker_pool.rb, worker_pool/fleet.rb,             *)
(* worker_pool/worker.rb, worker_pool/stillborn_guard.rb) and the worker   *)
(* side of the pipe protocol (lib/kimera/execution/shift.rb).              *)
(*                                                                         *)
(* Each worker is a forked child joined to the parent by two FIFO pipes.   *)
(* The parent offers one mutant id at a time; the child answers with       *)
(* "result" then "ready", or "requeue" (a warm run it can't trust) and     *)
(* exits. A child may also crash, hang, or exit after a tainted (soft      *)
(* timeout) result. The parent's hard watchdog may kill any worker at any  *)
(* moment (a slow test looks like a hang).                                 *)
(*                                                                         *)
(* Every action names the Ruby method it models. What is checked:          *)
(*   - no mutant gets two verdicts, and none is lost: when                 *)
(*     WorkerPool#run returns, every mutant has exactly one verdict;       *)
(*   - a recheck only runs on a worker that has served nothing yet;        *)
(*   - at most Jobs workers are live, each on its own database slot;       *)
(*   - the run terminates, even if workers hang, given only that hung      *)
(*     workers are eventually killed by the watchdog.                      *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS N,     \* mutants in the warm queue
          Jobs   \* --jobs

ASSUME N \in Nat /\ Jobs \in Nat \ {0}

Ids   == 1..N
None  == 0
Slots == 0..(Jobs - 1)

\* Workers are numbered by spawn order. Each id is requeued at most once and
\* each crash or kill consumes an id, so Jobs + 2N spawns always suffice.
\* SpawnBound checks that claim.
MaxWorkers == Jobs + 2 * N
Workers    == 1..MaxWorkers

Min(a, b) == IF a < b THEN a ELSE b
Range(s)  == {s[i] : i \in DOMAIN s}

Offer(i, r) == [kind |-> "offer", id |-> i, recheck |-> r]
Msg(k, i)   == [kind |-> k, id |-> i]
EOF         == [kind |-> "eof", id |-> None]

VARIABLES
  queue,      \* Fleet#queue: warm ids not taken yet, heaviest first
  done,       \* Fleet#done
  rechecks,   \* Fleet#rechecks
  rechecked,  \* Fleet#rechecked
  fleet,      \* Fleet#workers: the workers the parent polls
  spawned,    \* workers ever spawned
  slot,       \* Worker#slot
  free,       \* Fleet#slots
  inflight,   \* Worker#inflight
  served,     \* Worker#served
  req,        \* parent -> child pipe
  resp,       \* child -> parent pipe
  child,      \* the child process: "none" | "idle" | "busy" | "hung" | "gone"
  task,       \* the offer the child is evaluating
  refill,     \* spawns left in the current Fleet#refill loop (0: polling)
  verdicts,   \* ledger entries per id (Schedule#record)
  requeues,   \* requeue messages per id
  stale,      \* a recheck was once offered to a worker that had served
  stillborn,  \* StillbornGuard's count
  progressed, \* StillbornGuard#progress! seen
  aborted     \* StillbornGuard raised

vars == <<queue, done, rechecks, rechecked, fleet, spawned, slot, free,
          inflight, served, req, resp, child, task, refill, verdicts,
          requeues, stale, stillborn, progressed, aborted>>

parent == <<queue, done, rechecks, rechecked, fleet, spawned, slot, free,
            inflight, served, refill, verdicts, requeues, stale, stillborn,
            progressed, aborted>>

-----------------------------------------------------------------------------
(* The parent's helpers. Each yields the next values of the variables it   *)
(* writes, so actions can compose them.                                    *)

\* Fleet#following: shift ids off the queue until one is not done.
RECURSIVE Following(_)
Following(q) ==
  IF q = <<>> THEN [id |-> None, queue |-> <<>>]
  ELSE IF Head(q) \in done THEN Following(Tail(q))
  ELSE [id |-> Head(q), queue |-> Tail(q)]

\* Fleet#take: a fresh worker takes a recheck first.
Take(fresh) ==
  IF fresh /\ rechecks # <<>>
    THEN [id |-> Head(rechecks), queue |-> queue, rechecks |-> Tail(rechecks)]
    ELSE LET f == Following(queue)
         IN  [id |-> f.id, queue |-> f.queue, rechecks |-> rechecks]

\* Fleet#pending?
Pending == rechecks # <<>> \/ \E i \in Range(queue) : i \notin done

\* WorkerPool#assign for worker w, whose served flag is fresh = ~served[w].
\* Worker#claim + Worker#offer when an id is taken; WorkerPool#close
\* (Worker#retire, then EOF on the request pipe) when none is left.
Assign(w, fresh, rq) ==
  LET t == Take(fresh) IN
  IF t.id = None
    THEN /\ queue' = t.queue
         /\ rechecks' = t.rechecks
         /\ inflight' = [inflight EXCEPT ![w] = None]
         /\ served' = served
         /\ req' = [rq EXCEPT ![w] = Append(@, EOF)]
         /\ stale' = stale
    ELSE LET r == t.id \in rechecked IN
         /\ queue' = t.queue
         /\ rechecks' = t.rechecks
         /\ inflight' = [inflight EXCEPT ![w] = t.id]
         /\ served' = [served EXCEPT ![w] = TRUE]
         /\ req' = [rq EXCEPT ![w] = Append(@, Offer(t.id, r))]
         /\ stale' = (stale \/ (r /\ ~fresh))

\* Fleet#remove: drop the worker, return its slot, charge its in-flight id
\* (Fleet#charge), then start Fleet#refill.
Remove(w, reason) ==
  LET i        == inflight[w]
      crash    == reason = "crash" /\ i # None /\ ~progressed
      born     == IF crash THEN stillborn + 1 ELSE stillborn
      fleetNow == fleet \ {w}
  IN
  /\ fleet' = fleetNow
  /\ free' = free \cup {slot[w]}
  /\ stillborn' = born
  /\ aborted' = (born > Jobs)
  /\ done' = IF i # None THEN done \cup {i} ELSE done
  \* StillbornGuard#track raises before the loss reaches the ledger.
  /\ verdicts' = IF i # None /\ born <= Jobs
                   THEN [verdicts EXCEPT ![i] = @ + 1] ELSE verdicts
  /\ inflight' = [inflight EXCEPT ![w] = None]
  /\ refill' = IF born > Jobs THEN 0 ELSE Jobs - Cardinality(fleetNow)

-----------------------------------------------------------------------------
Init ==
  /\ queue = [k \in 1..N |-> k]
  /\ done = {}
  /\ rechecks = <<>>
  /\ rechecked = {}
  /\ fleet = {}
  /\ spawned = 0
  /\ slot = [w \in Workers |-> 0]
  /\ free = Slots
  /\ inflight = [w \in Workers |-> None]
  /\ served = [w \in Workers |-> FALSE]
  /\ req = [w \in Workers |-> <<>>]
  /\ resp = [w \in Workers |-> <<>>]
  /\ child = [w \in Workers |-> "none"]
  /\ task = [w \in Workers |-> Offer(None, FALSE)]
  \* Fleet#bootstrap spawns min(jobs, queue.size) workers and assigns each.
  \* With the queue full, that is exactly a refill of that many.
  /\ refill = Min(Jobs, N)
  /\ verdicts = [i \in Ids |-> 0]
  /\ requeues = [i \in Ids |-> 0]
  /\ stale = FALSE
  /\ stillborn = 0
  /\ progressed = FALSE
  /\ aborted = FALSE

Polling == refill = 0 /\ ~aborted

\* Fleet#refill: `missing.times { break unless pending?; replace }`, where
\* Fleet#replace is Fleet#spawn (next free slot) + WorkerPool#assign.
RefillStep ==
  /\ refill > 0 /\ ~aborted
  /\ IF Pending
       THEN LET w == spawned + 1
                s == CHOOSE x \in free : \A y \in free : x <= y
            IN  /\ free # {}
                /\ spawned' = w
                /\ fleet' = fleet \cup {w}
                /\ slot' = [slot EXCEPT ![w] = s]
                /\ free' = free \ {s}
                /\ child' = [child EXCEPT ![w] = "idle"]
                /\ refill' = refill - 1
                /\ Assign(w, TRUE, req)
                /\ UNCHANGED <<done, rechecked, resp, task, verdicts, requeues,
                               stillborn, progressed, aborted>>
       ELSE /\ refill' = 0
            /\ UNCHANGED <<queue, done, rechecks, rechecked, fleet, spawned,
                           slot, free, inflight, served, req, resp, child,
                           task, verdicts, requeues, stale, stillborn,
                           progressed, aborted>>

\* WorkerPool#service: read one line from w's pipe and WorkerPool#dispatch.
Service(w) ==
  /\ Polling /\ w \in fleet /\ resp[w] # <<>>
  /\ LET m == Head(resp[w])
         rest == [resp EXCEPT ![w] = Tail(@)]
     IN
     CASE m.kind = "eof" ->              \* pipe.gets returned nil
            /\ Remove(w, "crash")
            /\ resp' = rest
            /\ UNCHANGED <<queue, rechecks, rechecked, spawned, slot, served,
                           req, child, task, requeues, stale, progressed>>
       [] m.kind = "result" ->           \* WorkerPool#finish
            /\ done' = done \cup {m.id}
            /\ progressed' = TRUE
            /\ verdicts' = [verdicts EXCEPT ![m.id] = @ + 1]
            /\ inflight' = [inflight EXCEPT ![w] = None]
            /\ resp' = rest
            /\ UNCHANGED <<queue, rechecks, rechecked, fleet, spawned, slot,
                           free, served, req, child, task, refill, requeues,
                           stale, stillborn, aborted>>
       [] m.kind = "ready" ->            \* WorkerPool#assign
            /\ Assign(w, ~served[w], req)
            /\ resp' = rest
            /\ UNCHANGED <<done, rechecked, fleet, spawned, slot, free, child,
                           task, refill, verdicts, requeues, stillborn,
                           progressed, aborted>>
       [] m.kind = "requeue" ->          \* WorkerPool#relay + Fleet#requeue, close
            /\ rechecks' = Append(rechecks, m.id)
            /\ rechecked' = rechecked \cup {m.id}
            /\ requeues' = [requeues EXCEPT ![m.id] = @ + 1]
            /\ inflight' = [inflight EXCEPT ![w] = None]
            /\ req' = [req EXCEPT ![w] = Append(@, EOF)]
            /\ resp' = rest
            /\ UNCHANGED <<queue, done, fleet, spawned, slot, free, served,
                           child, task, refill, verdicts, stale, stillborn,
                           progressed, aborted>>
       [] OTHER ->                       \* "leak", "done": the ledger only
            /\ resp' = rest
            /\ UNCHANGED <<queue, done, rechecks, rechecked, fleet, spawned,
                           slot, free, inflight, served, req, child, task,
                           refill, verdicts, requeues, stale, stillborn,
                           progressed, aborted>>

\* WorkerPool#watch: the deadline passed; Worker#halt kills the child and
\* Fleet#remove reaps it. A slow test is indistinguishable from a hang, so
\* this may fire at any moment.
Expire(w) ==
  /\ Polling /\ w \in fleet
  /\ Remove(w, "timeout")
  /\ child' = [child EXCEPT ![w] = "gone"]
  /\ UNCHANGED <<queue, rechecks, rechecked, spawned, slot, served, req, resp,
                 task, requeues, stale, progressed>>

-----------------------------------------------------------------------------
(* The child (Shift#serve). Its pipes outlive the parent's interest: once  *)
(* removed from the fleet, whatever it writes is never read.               *)

Emit(w, msgs) == resp' = [resp EXCEPT ![w] = @ \o msgs]

ChildUnchanged == UNCHANGED parent

\* Channel#each_request: read an offer, or EOF (retired) and exit.
ChildRead(w) ==
  /\ child[w] = "idle" /\ req[w] # <<>>
  /\ LET m == Head(req[w]) IN
     /\ req' = [req EXCEPT ![w] = Tail(@)]
     /\ IF m.kind = "eof"
          THEN /\ Emit(w, <<Msg("done", None), EOF>>)
               /\ child' = [child EXCEPT ![w] = "gone"]
               /\ task' = task
          ELSE /\ child' = [child EXCEPT ![w] = "busy"]
               /\ task' = [task EXCEPT ![w] = m]
               /\ resp' = resp
  /\ ChildUnchanged

\* Shift#step: a trusted result, then "ready". Shift#process may slip a
\* "leak" for an earlier kill in between (LeakGuard#check).
ChildResult(w) ==
  /\ child[w] = "busy"
  /\ \E leak \in BOOLEAN :
       Emit(w, IF leak
                 THEN <<Msg("result", task[w].id), Msg("leak", None), Msg("ready", None)>>
                 ELSE <<Msg("result", task[w].id), Msg("ready", None)>>)
  /\ child' = [child EXCEPT ![w] = "idle"]
  /\ UNCHANGED <<req, task>> /\ ChildUnchanged

\* Shift#tainted?: a soft-timeout result ends the shift.
ChildTainted(w) ==
  /\ child[w] = "busy"
  /\ Emit(w, <<Msg("result", task[w].id), Msg("done", None), EOF>>)
  /\ child' = [child EXCEPT ![w] = "gone"]
  /\ UNCHANGED <<req, task>> /\ ChildUnchanged

\* Suspect#message: a warm run that can't be trusted. A recheck never
\* requeues (Attempt#recheck settles on a Doubt, which rules a result).
ChildRequeue(w) ==
  /\ child[w] = "busy" /\ ~task[w].recheck
  /\ Emit(w, <<Msg("requeue", task[w].id), Msg("done", None), EOF>>)
  /\ child' = [child EXCEPT ![w] = "gone"]
  /\ UNCHANGED <<req, task>> /\ ChildUnchanged

\* The process dies: the kernel closes its end of the pipe.
ChildCrash(w) ==
  /\ child[w] \in {"idle", "busy"}
  /\ Emit(w, <<EOF>>)
  /\ child' = [child EXCEPT ![w] = "gone"]
  /\ UNCHANGED <<req, task>> /\ ChildUnchanged

\* Stuck in a test, or in teardown after it was retired.
ChildHang(w) ==
  /\ child[w] \in {"idle", "busy"}
  /\ child' = [child EXCEPT ![w] = "hung"]
  /\ UNCHANGED <<req, resp, task>> /\ ChildUnchanged

ChildStep(w) ==
  \/ ChildRead(w) \/ ChildResult(w) \/ ChildTainted(w) \/ ChildRequeue(w)
  \/ ChildCrash(w)

\* The parent's loop ends: `poll while fleet.any?`
Finished == (Polling /\ fleet = {}) \/ aborted

Next ==
  \/ RefillStep
  \/ \E w \in Workers : Service(w) \/ Expire(w) \/ ChildStep(w) \/ ChildHang(w)
  \/ (Finished /\ UNCHANGED vars)

\* Healthy children make progress and the parent keeps polling; the
\* watchdog is only relied on to kill children that really hung.
Fairness ==
  /\ WF_vars(RefillStep)
  /\ \A w \in Workers :
       /\ WF_vars(Service(w))
       /\ WF_vars(ChildStep(w))
       /\ WF_vars(child[w] = "hung" /\ Expire(w))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Properties *)

TypeOK ==
  /\ fleet \subseteq Workers
  /\ spawned \in 0..MaxWorkers
  /\ done \subseteq Ids
  /\ rechecked \subseteq Ids
  /\ \A w \in Workers : inflight[w] \in Ids \cup {None}
  /\ \A i \in Ids : verdicts[i] \in Nat /\ requeues[i] \in Nat

\* Schedule#record never overwrites a verdict.
VerdictAtMostOnce == \A i \in Ids : verdicts[i] <= 1

\* A rechecked id never goes back to a warm run that could requeue it.
RequeueAtMostOnce == \A i \in Ids : requeues[i] <= 1

\* A recheck must not inherit a used worker's state.
RecheckOnFreshWorker == ~stale

FleetWithinJobs == Cardinality(fleet) <= Jobs

\* Parallel test databases: each live worker owns a distinct slot.
SlotsExclusive ==
  /\ \A v, w \in fleet : v # w => slot[v] # slot[w]
  /\ \A w \in fleet : slot[w] \in Slots /\ slot[w] \notin free

\* Whenever Fleet#refill spawns, a slot is free and the spawn bound holds.
CanSpawn == (refill > 0 /\ ~aborted /\ Pending) => (free # {} /\ spawned < MaxWorkers)

\* Every id is in exactly one place: waiting, awaiting a recheck, in flight
\* on one live worker, or done.
Holders(i) == {w \in fleet : inflight[w] = i}
Conservation ==
  \A i \in Ids :
    LET places == (IF i \in done THEN 1 ELSE 0)
                + (IF i \in Range(queue) THEN 1 ELSE 0)
                + (IF i \in Range(rechecks) THEN 1 ELSE 0)
                + Cardinality(Holders(i))
    IN aborted \/ places = 1

\* The headline: when WorkerPool#run returns normally, every mutant has
\* exactly one verdict.
CompleteOnExit ==
  (Polling /\ fleet = {}) => \A i \in Ids : verdicts[i] = 1

Termination == <>Finished
=============================================================================
