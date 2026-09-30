--------------------------- MODULE WorkerPoolTrace ---------------------------
(***************************************************************************)
(* Trace validation: is a run of the real parent a behavior of             *)
(* WorkerPool?                                                             *)
(*                                                                         *)
(* spec/property/worker_pool_spec.rb logs each step the real WorkerPool    *)
(* takes (spec/property/support/pool_trace.rb) and bin/model-check         *)
(* --traces hands the logs to TLC with this module. Each logged step must  *)
(* be one parent action of WorkerPool, taken from the state the model      *)
(* reached, with the same outcome: the same slot spawned, the same offer   *)
(* or close sent, the same id charged, the loop ending (or aborting) when  *)
(* the model's does. The children are not logged: between logged steps    *)
(* any child steps may happen, so the model's children must be able to     *)
(* explain what the parent read. A trace is accepted when TLC reaches a    *)
(* state past its last step.                                               *)
(*                                                                         *)
(* A logged step is a record:                                              *)
(*   act    "spawn" | "read" | "expire" | "finish" | "abort"               *)
(*   w      the worker's slot                                              *)
(*   kind   for a read: "part", "eof", or the message's kind               *)
(*   id     for a read of a result or requeue, its id; for "eof" and       *)
(*          "expire", the id charged (Worker#inflight), None if none       *)
(*   reply  what the parent sent w in the same step: "offer", "close" or   *)
(*          "none"; offer and recheck describe the offer                   *)
(***************************************************************************)
EXTENDS WorkerPool, Json

CONSTANT TraceFile  \* JSON: {traces: <<[queue, slots, steps], ...>>}

Traces == JsonDeserialize(TraceFile).traces

VARIABLES tr, l  \* the trace being matched, and its next step

T == Traces[tr].steps

\* What the parent wrote to w's request pipe in this step.
Sent(w, e) ==
  req'[w] = CASE e.reply = "offer" -> Append(req[w], Offer(e.offer, e.recheck))
              [] e.reply = "close" -> Append(req[w], EOF)
              [] OTHER             -> req[w]

\* The fragment at the head of w's pipe is the one the parent read.
Read(w, e) ==
  LET m == Head(resp[w]) IN
  /\ m.kind = e.kind
  /\ m.kind \in {"result", "requeue"} => m.id = e.id

\* A healthy child's long line read in pieces: the parent buffers the start
\* of a line that is already whole in the model. Nothing it can observe
\* changes until the rest arrives.
SplitRead(w) ==
  /\ Polling /\ w \in fleet /\ resp[w] # <<>>
  /\ Head(resp[w]).kind \notin {"part", "eof"}
  /\ UNCHANGED vars

Step(e) ==
  CASE e.act = "spawn" ->
         RefillStep /\ Pending /\ Head(free) = e.w /\ Sent(e.w, e)
    [] e.act = "read" /\ e.kind = "eof" ->
         Service(e.w) /\ Read(e.w, e) /\ inflight[e.w] = e.id
    [] e.act = "read" /\ e.kind = "part" ->
         \/ Service(e.w) /\ Read(e.w, e)
         \/ SplitRead(e.w)
    [] e.act = "read" /\ e.kind \notin {"eof", "part"} ->
         Service(e.w) /\ Read(e.w, e) /\ Sent(e.w, e)
    [] e.act = "expire" ->
         Expire(e.w) /\ inflight[e.w] = e.id
    [] e.act = "finish" ->
         Finished /\ ~aborted /\ UNCHANGED vars
    [] e.act = "abort" ->
         aborted /\ UNCHANGED vars

TraceInit ==
  /\ tr \in DOMAIN Traces
  /\ l = 1
  /\ InitWith(Traces[tr].queue, Traces[tr].slots)

\* Unlogged steps: Fleet#refill stopping because nothing is pending
\* (`break unless pending?`), and the children's. A child's steps touch only
\* its own state and pipes, so they commute with every parent step on
\* another worker: any behavior that matches the log can be reordered so a
\* child steps only just before the parent reads its pipe, and one that
\* hangs or is killed without being read can drop those steps. Allowing
\* child steps only there loses no match, and saves TLC every other
\* interleaving. A hang is never needed to explain a log.
TraceNext ==
  /\ l <= Len(T)
  /\ \/ /\ T[l].act = "read" /\ ChildStep(T[l].w)
        /\ UNCHANGED <<tr, l>>
     \/ /\ RefillStep /\ ~Pending
        /\ UNCHANGED <<tr, l>>
     \/ /\ Step(T[l])
        /\ l' = l + 1
        /\ UNCHANGED tr

ASSUME \A k \in DOMAIN Traces : TLCSet(k, 0)

\* Never violated: prints how far each trace has been matched, each time
\* that grows. bin/model-check --traces accepts a trace printed past its
\* last step.
Matched ==
  IF l > TLCGet(tr) THEN PrintT(<<"matched", tr, l - 1>>) /\ TLCSet(tr, l)
                    ELSE TRUE
=============================================================================
