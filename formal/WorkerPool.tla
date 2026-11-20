----------------------------- MODULE WorkerPool -----------------------------
(***************************************************************************)
(* The warm worker pool: the parent's scheduling loop                      *)
(* (lib/kimera/execution/worker_pool.rb, worker_pool/fleet.rb,             *)
(* worker_pool/backlog.rb, worker_pool/worker.rb,                          *)
(* worker_pool/stillborn_guard.rb) and the worker side of the pipe         *)
(* protocol (lib/kimera/execution/shift.rb).                               *)
(*                                                                         *)
(* Each worker is a forked child joined to the parent by two FIFO pipes.   *)
(* The parent offers one mutant id at a time; the child answers with       *)
(* "result" then "ready", and with "done" when it is retired. A child may  *)
(* also crash, hang, or stop partway through a line. The parent's hard     *)
(* watchdog may kill any worker at any moment (a slow test looks like a    *)
(* hang).                                                                  *)
(*                                                                         *)
(* Every action names the Ruby method it models; the model was written by  *)
(* reading that code and is not derived from it mechanically. TLC checks   *)
(* the properties at the end of this module exhaustively, but only for     *)
(* the finite instances it is run on (bin/model-check lists them). That    *)
(* says nothing about larger pools, and nothing about the Ruby code beyond *)
(* what this model captures.                                               *)
(*                                                                         *)
(* A live worker is named by its test-database slot, and a removed         *)
(* worker's state is reset, so a state holds only what the parent can      *)
(* still observe; renaming ids or slots maps behaviors to behaviors, which *)
(* lets safety runs use symmetry reduction.                                *)
(*                                                                         *)
(* A pipe carries fragments: complete lines, the start of a line whose     *)
(* rest may follow (a child that stops partway through a write), and EOF.  *)
(* The parent keeps the start in the worker's line buffer and dispatches a *)
(* line only once it is complete. Blocking = TRUE is the parent before #2, *)
(* which read with pipe.gets: TLC finds it never terminates (see           *)
(* bin/model-check). Time is abstract, so the watchdog may fire at any     *)
(* step; message payloads, verdict details and the tiers Schedule runs     *)
(* after the pool are left out.                                            *)
(*                                                                         *)
(* Termination rests on the fairness below: the parent keeps refilling and *)
(* keeps dispatching each worker's complete lines (nothing makes it read   *)
(* half a line), each healthy child keeps taking steps, and a hung child   *)
(* is eventually killed. Healthy children are never assumed to be killed.  *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS Ids,      \* the mutants in the warm queue
          Slots,    \* test-database slots, one per --jobs
          None,     \* no mutant: a value outside Ids
          Blocking  \* TRUE: the parent reads a line with a blocking pipe.gets,
                    \* as before #2; FALSE: WorkerPool#service as it is now

ASSUME None \notin Ids /\ Slots # {} /\ Blocking \in BOOLEAN

N    == Cardinality(Ids)
Jobs == Cardinality(Slots)

\* A live worker is named by the slot it holds. Fleet#remove returns the
\* slot, and Remove resets everything the model keeps for the worker, so a
\* slot's next worker starts from nothing its predecessor left.
Workers == Slots

Min(a, b) == IF a < b THEN a ELSE b
Range(s)  == {s[i] : i \in DOMAIN s}

\* The orders a finite set can be listed in. The warm queue (heaviest first)
\* and Fleet#slots start in one of them; which one doesn't matter, since no
\* property tells two ids or two slots apart.
Orders(S)  == {s \in [1..Cardinality(S) -> S] : Range(s) = S}
QueueOrder == CHOOSE s \in Orders(Ids) : TRUE
SlotOrder  == CHOOSE s \in Orders(Slots) : TRUE

\* Renaming ids or slots maps behaviors to behaviors (nothing compares or
\* orders them), so TLC may check invariants on one state per orbit.
\* bin/model-check uses this for safety runs only: TLC's symmetry reduction
\* is unsound for liveness.
Symmetry == Permutations(Ids) \cup Permutations(Slots)

Offer(i)    == [kind |-> "offer", id |-> i]
Msg(k, i)   == [kind |-> k, id |-> i]
EOF         == [kind |-> "eof", id |-> None]
\* The start of a line a child is still writing. Its rest arrives as the
\* next fragment, which is the whole message: a line is dispatched only
\* once it is complete.
Part        == [kind |-> "part", id |-> None]
NoTask      == Offer(None)

VARIABLES
  queue,      \* Backlog#queue: warm ids not taken yet, heaviest first
  fleet,      \* Fleet#workers: the workers the parent polls
  free,       \* Fleet#slots, a FIFO: spawn takes the head, remove appends
  inflight,   \* Worker#inflight
  req,        \* parent -> child pipe: offers and EOF
  resp,       \* child -> parent pipe: lines, Part and EOF, in write order
  buf,        \* Worker#unread holds the start of a line
  blocked,    \* {w}: the parent is stuck in a read of w's pipe (Blocking)
  child,      \* the child process: "none" | "idle" | "busy" | "torn" |
              \* "hung" | "gone"; torn is busy with half a line written
  task,       \* the offer the child is evaluating (NoTask unless busy)
  refill,     \* spawns left in the current Fleet#refill loop (0: polling)
  verdicts,   \* ledger entries per id (Schedule#record)
  stillborn,  \* StillbornGuard's count
  progressed, \* StillbornGuard#progress! seen
  aborted     \* StillbornGuard raised

vars == <<queue, fleet, free, inflight, req, resp, buf, blocked, child, task,
          refill, verdicts, stillborn, progressed, aborted>>

parent == <<queue, fleet, free, inflight, buf, blocked, refill, verdicts,
            stillborn, progressed, aborted>>

-----------------------------------------------------------------------------
(* The parent's helpers. Each yields the next values of the variables it   *)
(* writes, so actions can compose them.                                    *)

\* Backlog#pending?
Pending == queue # <<>>

\* WorkerPool#assign for worker w: Backlog#take, then Worker#claim +
\* Worker#offer when an id is left; WorkerPool#close (Worker#retire, then
\* EOF on the request pipe) when none is.
Assign(w, rq) ==
  IF queue = <<>>
    THEN /\ queue' = queue
         /\ inflight' = [inflight EXCEPT ![w] = None]
         /\ req' = [rq EXCEPT ![w] = Append(@, EOF)]
    ELSE /\ queue' = Tail(queue)
         /\ inflight' = [inflight EXCEPT ![w] = Head(queue)]
         /\ req' = [rq EXCEPT ![w] = Append(@, Offer(Head(queue)))]

\* Fleet#remove: drop the worker, return its slot, close its pipes and reap
\* it, charge its in-flight id (Fleet#charge), then start Fleet#refill.
\* Nothing of the worker is looked at again, so all it held is reset.
Remove(w, reason) ==
  LET i        == inflight[w]
      crash    == reason = "crash" /\ i # None /\ ~progressed
      born     == IF crash THEN stillborn + 1 ELSE stillborn
      fleetNow == fleet \ {w}
  IN
  /\ fleet' = fleetNow
  /\ free' = Append(free, w)
  /\ stillborn' = born
  /\ aborted' = (born > Jobs)
  \* StillbornGuard#track raises before the loss reaches the ledger.
  /\ verdicts' = IF i # None /\ born <= Jobs
                   THEN [verdicts EXCEPT ![i] = @ + 1] ELSE verdicts
  /\ refill' = IF born > Jobs THEN 0 ELSE Jobs - Cardinality(fleetNow)
  /\ inflight' = [inflight EXCEPT ![w] = None]
  /\ req' = [req EXCEPT ![w] = <<>>]
  /\ resp' = [resp EXCEPT ![w] = <<>>]
  /\ buf' = [buf EXCEPT ![w] = FALSE]
  /\ child' = [child EXCEPT ![w] = "none"]
  /\ task' = [task EXCEPT ![w] = NoTask]

-----------------------------------------------------------------------------
\* The parent starts with the queue in order q and Fleet#slots in order f.
InitWith(q, f) ==
  /\ queue = q
  /\ fleet = {}
  /\ free = f
  /\ inflight = [w \in Workers |-> None]
  /\ req = [w \in Workers |-> <<>>]
  /\ resp = [w \in Workers |-> <<>>]
  /\ buf = [w \in Workers |-> FALSE]
  /\ blocked = {}
  /\ child = [w \in Workers |-> "none"]
  /\ task = [w \in Workers |-> NoTask]
  \* Fleet#bootstrap spawns min(jobs, queue.size) workers and assigns each.
  \* With the queue full, that is exactly a refill of that many.
  /\ refill = Min(Jobs, Len(q))
  /\ verdicts = [i \in Ids |-> 0]
  /\ stillborn = 0
  /\ progressed = FALSE
  /\ aborted = FALSE

Init == InitWith(QueueOrder, SlotOrder)

\* The parent is in its loop, not in a refill and not stuck in a read.
Polling == refill = 0 /\ ~aborted /\ blocked = {}

\* Fleet#refill: `missing.times { break unless pending?; replace }`, where
\* Fleet#replace is Fleet#spawn (the next free slot) + WorkerPool#assign.
RefillStep ==
  /\ refill > 0 /\ ~aborted
  /\ IF Pending
       THEN /\ free # <<>>
            /\ LET w == Head(free) IN
               /\ fleet' = fleet \cup {w}
               /\ free' = Tail(free)
               /\ child' = [child EXCEPT ![w] = "idle"]
               /\ refill' = refill - 1
               /\ Assign(w, req)
            /\ UNCHANGED <<resp, buf, blocked, task, verdicts, stillborn,
                           progressed, aborted>>
       ELSE /\ refill' = 0
            /\ UNCHANGED <<queue, fleet, free, inflight, req, resp, buf,
                           blocked, child, task, verdicts, stillborn,
                           progressed, aborted>>

\* WorkerPool#service: read one fragment from w's pipe. The start of a line
\* goes to the worker's buffer (Worker#feed); a complete line goes to
\* WorkerPool#dispatch. With Blocking, the start of a line leaves the
\* parent stuck in pipe.gets until the rest or EOF arrives: no other
\* worker is read and the watchdog doesn't run.
Service(w) ==
  /\ refill = 0 /\ ~aborted /\ blocked \subseteq {w}
  /\ w \in fleet /\ resp[w] # <<>>
  /\ LET m == Head(resp[w])
         rest == [resp EXCEPT ![w] = Tail(@)]
         line == /\ resp' = rest
                 /\ buf' = [buf EXCEPT ![w] = FALSE]
                 /\ blocked' = {}
     IN
     CASE m.kind = "part" ->             \* Worker#feed keeps it
            /\ resp' = rest
            /\ buf' = [buf EXCEPT ![w] = TRUE]
            /\ blocked' = IF Blocking THEN {w} ELSE {}
            /\ UNCHANGED <<queue, fleet, free, inflight, req, child, task,
                           refill, verdicts, stillborn, progressed, aborted>>
       [] m.kind = "eof" ->              \* WorkerPool#hangup: a partial
            /\ Remove(w, "crash")        \* rest doesn't parse
            /\ blocked' = {}
            /\ UNCHANGED <<queue, progressed>>
       [] m.kind = "result" ->           \* WorkerPool#finish
            /\ progressed' = TRUE
            /\ verdicts' = [verdicts EXCEPT ![m.id] = @ + 1]
            /\ inflight' = [inflight EXCEPT ![w] = None]
            /\ line
            /\ UNCHANGED <<queue, fleet, free, req, child, task, refill,
                           stillborn, aborted>>
       [] m.kind = "ready" ->            \* WorkerPool#assign
            /\ Assign(w, req)
            /\ line
            /\ UNCHANGED <<fleet, free, child, task, refill, verdicts,
                           stillborn, progressed, aborted>>
       [] OTHER ->                       \* "done": nothing to dispatch
            /\ line
            /\ UNCHANGED <<queue, fleet, free, inflight, req, child, task,
                           refill, verdicts, stillborn, progressed, aborted>>

\* The pipe holds a complete line, or EOF: a read that returns one.
Complete(w) == \E k \in DOMAIN resp[w] : resp[w][k].kind # "part"

\* Stuck in a read (Blocking only): the parent is alive and does nothing.
Wait == blocked # {} /\ UNCHANGED vars

\* WorkerPool#watch: the deadline passed; Worker#halt kills the child and
\* Fleet#remove reaps it. A slow test is indistinguishable from a hang, so
\* this may fire at any moment.
Expire(w) ==
  /\ Polling /\ w \in fleet
  /\ Remove(w, "timeout")
  /\ UNCHANGED <<queue, blocked, progressed>>

-----------------------------------------------------------------------------
(* The child (Shift#serve). Its pipes outlive the parent's interest: once  *)
(* removed from the fleet, whatever it writes is never read. The offer it  *)
(* is evaluating matters only while it is busy.                            *)

Emit(w, msgs) == resp' = [resp EXCEPT ![w] = @ \o msgs]

Become(w, state) ==
  /\ child' = [child EXCEPT ![w] = state]
  /\ task' = [task EXCEPT ![w] = NoTask]

ChildUnchanged == UNCHANGED parent

\* Channel#ids: read an offer, or EOF (retired) and exit.
ChildRead(w) ==
  /\ child[w] = "idle" /\ req[w] # <<>>
  /\ LET m == Head(req[w]) IN
     /\ req' = [req EXCEPT ![w] = Tail(@)]
     /\ IF m.kind = "eof"
          THEN /\ Emit(w, <<Msg("done", None), EOF>>)
               /\ Become(w, "gone")
          ELSE /\ child' = [child EXCEPT ![w] = "busy"]
               /\ task' = [task EXCEPT ![w] = m]
               /\ resp' = resp
  /\ ChildUnchanged

Busy(w) == child[w] \in {"busy", "torn"}

\* Shift#judging: the verdict, a soft timeout included, then "ready". From
\* torn, the first line finishes the one already started.
ChildResult(w) ==
  /\ Busy(w)
  /\ Emit(w, <<Msg("result", task[w].id), Msg("ready", None)>>)
  /\ Become(w, "idle")
  /\ UNCHANGED req /\ ChildUnchanged

\* A child stops partway through writing its first line: the pipe holds
\* the start of it, flushed. What follows is the rest, EOF, or nothing.
ChildTear(w) ==
  /\ child[w] = "busy"
  /\ Emit(w, <<Part>>)
  /\ child' = [child EXCEPT ![w] = "torn"]
  /\ UNCHANGED <<req, task>> /\ ChildUnchanged

\* The process dies: the kernel closes its end of the pipe.
ChildCrash(w) ==
  /\ child[w] \in {"idle", "busy", "torn"}
  /\ Emit(w, <<EOF>>)
  /\ Become(w, "gone")
  /\ UNCHANGED req /\ ChildUnchanged

\* Stuck in a test, or in teardown after it was retired.
ChildHang(w) ==
  /\ child[w] \in {"idle", "busy", "torn"}
  /\ Become(w, "hung")
  /\ UNCHANGED <<req, resp>> /\ ChildUnchanged

ChildStep(w) ==
  \/ ChildRead(w) \/ ChildResult(w) \/ ChildTear(w) \/ ChildCrash(w)

\* The parent's loop ends: `poll while fleet.any?`
Finished == (Polling /\ fleet = {}) \/ aborted

Next ==
  \/ RefillStep
  \/ \E w \in Workers : Service(w) \/ Expire(w) \/ ChildStep(w) \/ ChildHang(w)
  \/ Wait
  \/ (Finished /\ UNCHANGED vars)

\* Healthy children make progress, and the parent keeps refilling and
\* dispatches every line that is complete. Nothing makes it read the start
\* of a line whose rest may never come: under Blocking that read never
\* returns. The watchdog is only relied on to kill children that really
\* hung.
Fairness ==
  /\ WF_vars(RefillStep)
  /\ \A w \in Workers :
       /\ WF_vars(Complete(w) /\ Service(w))
       /\ WF_vars(ChildStep(w))
       /\ WF_vars(child[w] = "hung" /\ Expire(w))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Properties *)

TypeOK ==
  /\ fleet \subseteq Workers
  /\ free \in Seq(Slots)
  /\ blocked \subseteq fleet /\ Cardinality(blocked) <= 1
  /\ \A w \in Workers : inflight[w] \in Ids \cup {None}
  /\ \A i \in Ids : verdicts[i] \in Nat

\* Schedule#record never overwrites a verdict.
VerdictAtMostOnce == \A i \in Ids : verdicts[i] <= 1

FleetWithinJobs == Cardinality(fleet) <= Jobs

\* Parallel test databases: the live workers and Fleet#slots hold every
\* slot exactly once between them, so no two live workers share a slot and
\* a spawn never takes one a live worker holds.
SlotsExclusive ==
  /\ Len(free) + Cardinality(fleet) = Jobs
  /\ Range(free) \cup fleet = Slots

\* A buffered start of a line belongs to a child still writing it, stuck or
\* dead, or its rest is next in the pipe: lines are never spliced.
Framed ==
  \A w \in fleet :
    buf[w] => \/ child[w] \in {"torn", "hung", "gone"}
              \/ resp[w] # <<>> /\ Head(resp[w]).kind \notin {"part", "eof"}

\* A worker leaves the fleet only once its process is reaped.
Reaped == \A w \in Workers \ fleet : child[w] = "none"

\* Whenever Fleet#refill spawns, a slot is free.
CanSpawn == (refill > 0 /\ ~aborted /\ Pending) => free # <<>>

\* Every id is in exactly one place: waiting, in flight on one live
\* worker, or recorded in the ledger.
Holders(i) == {w \in fleet : inflight[w] = i}
Conservation ==
  \A i \in Ids :
    LET places == verdicts[i]
                + (IF i \in Range(queue) THEN 1 ELSE 0)
                + Cardinality(Holders(i))
    IN aborted \/ places = 1

\* The headline: when WorkerPool#run returns normally, every mutant has
\* exactly one verdict.
CompleteOnExit ==
  (Polling /\ fleet = {}) => \A i \in Ids : verdicts[i] = 1

Termination == <>Finished
=============================================================================
